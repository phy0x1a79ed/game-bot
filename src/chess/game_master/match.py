"""Plays a series of games between two bot processes on the `game` library."""

from __future__ import annotations

import asyncio
import dataclasses
import datetime
import json
import logging
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from coms.protocol import (
    GameOver,
    GameStart,
    Move,
    MoveRejected,
    MoveRequest,
    ProtocolError,
    Resign,
    RpcError,
)
from game import STARTING_FEN, Game, GameState, Outcome
from game_master.bots import DISCONNECTED, BotProcess
from game_master.seats import is_external

log = logging.getLogger(__name__)

UCI_RE = re.compile(r"^[a-h][1-8][a-h][1-8][qrbn]?$")

STOPPED = object()

Emit = Callable[[str, dict[str, Any]], None]


@dataclass
class Settings:
    white: str
    black: str
    games: int = 1
    alternate: bool = True
    fen: str | None = None
    move_timeout_s: float = 5.0
    max_attempts: int = 5
    max_plies: int = 500
    seed: int | None = None
    # Per slot, not per color, because `alternate` swaps colors. None is no limit.
    seat_timeout_s: list[float | None] | None = None
    min_ply_s: float = 0.0

    _TYPES = {
        "white": str, "black": str, "games": int, "alternate": bool, "fen": str,
        "move_timeout_s": float, "max_attempts": int, "max_plies": int, "seed": int,
        "seat_timeout_s": list, "min_ply_s": float,
    }
    _NULLABLE = {"fen", "seed", "seat_timeout_s"}

    @classmethod
    def from_params(cls, params: dict[str, Any]) -> Settings:
        unknown = set(params) - set(cls._TYPES)
        if unknown:
            raise RpcError("invalid_params", f"unknown params: {sorted(unknown)}")
        for key in ("white", "black"):
            if key not in params:
                raise RpcError("invalid_params", f"missing param {key!r}")
        for key, value in params.items():
            if value is None and key in cls._NULLABLE:
                continue
            if not _is_type(value, cls._TYPES[key]):
                raise RpcError("invalid_params", f"{key}: bad value {value!r}")
        settings = cls(**params)
        settings.move_timeout_s = float(settings.move_timeout_s)
        if settings.games < 1 or settings.max_attempts < 1 or settings.max_plies < 1:
            raise RpcError("invalid_params", "games, max_attempts and max_plies must be >= 1")
        if settings.move_timeout_s <= 0:
            raise RpcError("invalid_params", "move_timeout_s must be > 0")
        names = (settings.white, settings.black)
        timeouts = settings.seat_timeout_s
        if timeouts is None:
            timeouts = [None if is_external(n) else settings.move_timeout_s for n in names]
        if len(timeouts) != 2 or not all(
            t is None or (_is_type(t, float) and t > 0) for t in timeouts
        ):
            raise RpcError("invalid_params", "seat_timeout_s must be two numbers > 0 or null")
        for name, timeout in zip(names, timeouts):
            if timeout is None and not is_external(name):
                raise RpcError("invalid_params", f"bot {name!r} needs a time limit")
        settings.seat_timeout_s = [None if t is None else float(t) for t in timeouts]
        settings.min_ply_s = float(settings.min_ply_s)
        if settings.min_ply_s < 0:
            raise RpcError("invalid_params", "min_ply_s must be >= 0")
        if settings.fen is not None:
            try:
                GameState.from_fen(settings.fen)
            except ValueError as exc:
                raise RpcError("invalid_params", str(exc)) from exc
        return settings

    def to_dict(self) -> dict[str, Any]:
        return {f.name: getattr(self, f.name) for f in dataclasses.fields(self)}


def _is_type(value: Any, kind: type) -> bool:
    if kind is float:
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if kind is int:
        return isinstance(value, int) and not isinstance(value, bool)
    return isinstance(value, kind)


@dataclass
class GameRecord:
    index: int
    game_id: str
    white_slot: int
    game: Game
    think_s: list[float] = field(default_factory=list)
    rejected: list[dict[str, Any]] = field(default_factory=list)

    def __post_init__(self) -> None:
        self.state = self.game.state()

    @property
    def finished(self) -> bool:
        return self.game.outcome is not None

    def slot_of(self, color: str) -> int:
        return self.white_slot if color == "white" else 1 - self.white_slot

    def to_dict(self) -> dict[str, Any]:
        return {
            "index": self.index,
            "game_id": self.game_id,
            "white_slot": self.white_slot,
            "game": self.game.to_dict(),
            "think_s": list(self.think_s),
            "rejected": list(self.rejected),
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> GameRecord:
        return cls(
            index=data["index"],
            game_id=data["game_id"],
            white_slot=data["white_slot"],
            game=Game.from_dict(data["game"]),
            think_s=list(data.get("think_s", [])),
            rejected=list(data.get("rejected", [])),
        )

    def history(self, fens: bool = False) -> dict[str, Any]:
        """The game's moves. With `fens`, each move carries the position after it."""
        state = GameState.from_fen(self.game.initial_fen)
        first = state.turn
        other = "black" if first == "white" else "white"
        moves = []
        for ply, (uci, san) in enumerate(zip(self.game.moves, self.game.san_moves())):
            move = {
                "ply": ply,
                "side": first if ply % 2 == 0 else other,
                "uci": uci,
                "san": san,
                "think_s": self.think_s[ply] if ply < len(self.think_s) else None,
            }
            if fens:
                state.push(uci)
                move["fen"] = state.fen
            moves.append(move)
        return {
            "game_id": self.game_id,
            "index": self.index,
            "players": dict(self.game.players),
            "initial_fen": self.game.initial_fen,
            "moves": moves,
            "rejected": list(self.rejected),
            "outcome": _outcome_dict(self.game.outcome),
        }


def _outcome_dict(outcome: Outcome | None) -> dict[str, str] | None:
    return {"result": outcome.result, "reason": outcome.reason} if outcome else None


class Match:
    """A series of games between bot slot 0 and bot slot 1."""

    def __init__(self, sid: str, settings: Settings, bots: list[BotProcess], records: Path,
                 emit: Emit | None = None):
        self.sid = sid
        self.settings = settings
        self.bots = bots
        self.records = records
        self.games: list[GameRecord] = []
        self.score = [0.0, 0.0]
        self.labels: dict[str, str] = {}
        self._emit = emit or (lambda event, data: None)
        self._phase = "stopped"
        self.note: str | None = None
        self.awaiting: dict[str, Any] | None = None
        self._task: asyncio.Task | None = None
        self._stop_requested = False
        self._ply_budget: int | None = None
        self._last_ply_at = 0.0
        self._resigned: tuple[str, Outcome] | None = None
        # Rung by anything that can end an open move request or a pace hold early.
        self._wake = asyncio.Event()

    @classmethod
    def from_save(
        cls, sid: str, data: dict[str, Any], bots: list[BotProcess], records: Path,
        emit: Emit | None = None,
    ) -> Match:
        match = cls(sid, Settings.from_params(data["settings"]), bots, records, emit)
        match.games = [GameRecord.from_dict(g) for g in data.get("games", [])]
        match.score = [float(x) for x in data.get("score", [0.0, 0.0])]
        match.labels = dict(data.get("labels", {}))
        if match._series_done():
            match.phase = "finished"
        return match

    @property
    def current(self) -> GameRecord | None:
        return self.games[-1] if self.games else None

    @property
    def phase(self) -> str:
        return self._phase

    @phase.setter
    def phase(self, value: str) -> None:
        if value != self._phase:
            self._phase = value
            self._emit("phase", {"phase": value, "note": self.note})

    # --- control ---

    def start(self, ply_budget: int | None = None) -> None:
        if self.phase == "running":
            raise RpcError("busy", "play is already running")
        if self.phase == "finished":
            raise RpcError("busy", "the series is finished")
        self._stop_requested = False
        self._ply_budget = ply_budget
        self._last_ply_at = asyncio.get_running_loop().time()
        self.phase = "running"
        self._task = asyncio.create_task(self._run())

    async def step(self) -> None:
        """Play exactly one ply from `stopped`, without the pace hold."""
        if self.phase != "stopped":
            raise RpcError("busy", f"cannot step while {self.phase}")
        if self._seat_to_move().external:
            raise RpcError("busy", "an external seat is to move; submit its move instead")
        self.start(ply_budget=1)
        await asyncio.shield(self._task)

    def set_pace(self, min_ply_s: float) -> dict[str, float]:
        if min_ply_s < 0:
            raise RpcError("invalid_params", "min_ply_s must be >= 0")
        self.settings.min_ply_s = float(min_ply_s)
        self._wake.set()
        self._emit("pace", {"min_ply_s": self.settings.min_ply_s})
        return {"min_ply_s": self.settings.min_ply_s}

    async def stop(self) -> None:
        if self.phase != "running":
            raise RpcError("busy", f"cannot stop while {self.phase}")
        self._stop_requested = True
        self._wake.set()
        await asyncio.shield(self._task)

    def submit_move(self, color: str, game_id: str, ply: int, move: Any) -> dict[str, Any]:
        """Hand an external seat's move to the waiting play loop.

        An invalid move is recorded and answered with the legal moves. It never forfeits.
        """
        rec = self.current
        if self.phase != "running":
            raise RpcError("busy", f"cannot move while {self.phase}")
        if rec is None or rec.finished or (game_id, ply) != (rec.game_id, len(rec.game.moves)):
            raise RpcError("stale", f"{game_id} ply {ply} is not the position in play")
        seat = self.bots[rec.slot_of(color)]
        if not seat.external:
            raise RpcError("not_your_turn", f"{color} is played by bot {seat.name}")
        waiting = self.awaiting
        if waiting is None or (waiting["color"], waiting["game_id"], waiting["ply"]) != (
            color, game_id, ply
        ):
            raise RpcError("not_your_turn", f"no open move request for {color}")
        state = rec.state
        if isinstance(move, str) and UCI_RE.match(move) and state.is_legal(move):
            self.awaiting = None
            seat.put(Move(game_id, ply, move))
            return {"accepted": True, "san": state.san(move)}
        reason = "illegal" if isinstance(move, str) and UCI_RE.match(move) else "malformed"
        self._reject(rec, ply, color, move, reason)
        return {"accepted": False, "reason": reason, "legal_moves": state.legal_moves()}

    async def resign(self, color: str) -> dict[str, str]:
        """Resign the current game for an external seat, on either side's turn or while stopped."""
        rec = self.current
        if rec is None or rec.finished:
            raise RpcError("no_game", "no game is in play")
        seat = self.bots[rec.slot_of(color)]
        if not seat.external:
            raise RpcError("invalid_params", f"{color} is played by bot {seat.name}")
        outcome = Outcome.win_for("black" if color == "white" else "white", "resignation")
        if self.phase == "running":
            self._resigned = (rec.game_id, outcome)
            self._wake.set()
            while not rec.finished and self.phase == "running":
                await asyncio.sleep(0.01)
        if not rec.finished:
            await self._finish(rec, outcome)
            if self._series_done():
                self.phase = "finished"
        return {"result": rec.game.outcome.result, "reason": rec.game.outcome.reason}

    async def shutdown(self) -> None:
        if self._task is not None and not self._task.done():
            self._task.cancel()
            await asyncio.gather(self._task, return_exceptions=True)
        rec = self.current
        if rec is not None and not rec.finished:
            for bot in self.bots:
                if bot.announced_game == rec.game_id:
                    await bot.send(GameOver(rec.game_id, "1/2-1/2", "stopped"))
            self._write_records(rec)
        await asyncio.gather(*(bot.close() for bot in self.bots))

    # --- queries ---

    def status(self) -> dict[str, Any]:
        rec = self.current
        return {
            "phase": self.phase,
            "game_id": rec.game_id if rec else None,
            "game_index": rec.index if rec else 0,
            "games": self.settings.games,
            "score": list(self.score),
            "note": self.note,
            "min_ply_s": self.settings.min_ply_s,
            "labels": dict(self.labels),
            "bots": [
                {
                    "slot": bot.slot,
                    "name": bot.name,
                    "color": ("white" if rec.white_slot == bot.slot else "black") if rec else None,
                    "points": self.score[bot.slot],
                    "pid": bot.pid,
                    "alive": bot.alive,
                    "external": bot.external,
                }
                for bot in self.bots
            ],
        }

    def state(self) -> dict[str, Any]:
        rec = self.current
        if rec is None:
            state = GameState.from_fen(self.settings.fen or STARTING_FEN)
            return {"game_id": None, "fen": state.fen, "turn": state.turn, "ply": 0,
                    "legal_moves": state.legal_moves(), "last_move": None, "outcome": None,
                    "players": None, "awaiting": None}
        state = rec.state
        return {
            "game_id": rec.game_id,
            "fen": state.fen,
            "turn": state.turn,
            "ply": len(rec.game.moves),
            "legal_moves": [] if rec.finished else state.legal_moves(),
            "last_move": state.last_move,
            "outcome": _outcome_dict(rec.game.outcome),
            "players": dict(rec.game.players),
            "awaiting": dict(self.awaiting) if self.awaiting else None,
        }

    def history(self, game_id: str | None = None, fens: bool = False) -> dict[str, Any]:
        if game_id is None:
            if self.current is None:
                raise RpcError("not_found", "no game has started")
            return self.current.history(fens)
        for rec in self.games:
            if rec.game_id == game_id:
                return rec.history(fens)
        raise RpcError("not_found", f"no game {game_id!r} in this session")

    def to_save(self) -> dict[str, Any]:
        return {
            "format": 1,
            "sid": self.sid,
            "saved_at": datetime.datetime.now().isoformat(timespec="seconds"),
            "settings": self.settings.to_dict(),
            "labels": dict(self.labels),
            "score": list(self.score),
            "games": [rec.to_dict() for rec in self.games],
        }

    # --- play ---

    def _series_done(self) -> bool:
        rec = self.current
        return len(self.games) >= self.settings.games and (rec is None or rec.finished)

    async def _run(self) -> None:
        try:
            while True:
                rec = self.current
                if (rec is None or rec.finished) and self._series_done():
                    self.phase = "finished"
                    return
                if self._stop_requested or self._ply_budget == 0:
                    self.phase = "stopped"
                    return
                if rec is None or rec.finished:
                    rec = self._new_game()
                for bot in self.bots:
                    await self._announce(rec, bot)
                outcome = await self._play_ply(rec)
                if self._ply_budget is not None:
                    self._ply_budget -= 1
                if outcome is not None:
                    await self._finish(rec, outcome)
                    dead = [bot.label for bot in self.bots if not bot.alive]
                    if dead:
                        self.note = f"bot disconnected: {', '.join(dead)}"
                        self.phase = "finished"
                        return
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            log.exception("play loop failed")
            self.note = f"play loop failed: {exc!r}"
            self.phase = "stopped"

    def _white_slot(self, index: int) -> int:
        return (index - 1) % 2 if self.settings.alternate else 0

    def _seat_to_move(self) -> BotProcess:
        rec = self.current
        if rec is not None and not rec.finished:
            return self.bots[rec.slot_of(rec.state.turn)]
        white_slot = self._white_slot(len(self.games) + 1)
        turn = GameState.from_fen(self.settings.fen or STARTING_FEN).turn
        return self.bots[white_slot if turn == "white" else 1 - white_slot]

    def _new_game(self) -> GameRecord:
        index = len(self.games) + 1
        white_slot = self._white_slot(index)
        game = Game(
            initial_fen=self.settings.fen or STARTING_FEN,
            players={"white": self.bots[white_slot].name, "black": self.bots[1 - white_slot].name},
            meta={
                "event": f"arena {self.sid}",
                "round": index,
                "date": datetime.date.today().strftime("%Y.%m.%d"),
            },
        )
        rec = GameRecord(index=index, game_id=f"{self.sid}-{index}", white_slot=white_slot, game=game)
        self.games.append(rec)
        log.info("game %s: %s (white) vs %s (black)", rec.game_id, *game.players.values())
        self._emit("game_start", {"game_id": rec.game_id, "index": index,
                                  "players": dict(game.players), "white_slot": white_slot,
                                  "initial_fen": game.initial_fen})
        return rec

    async def _announce(self, rec: GameRecord, bot: BotProcess) -> None:
        if bot.announced_game == rec.game_id:
            return
        color = "white" if rec.white_slot == bot.slot else "black"
        await bot.send(GameStart(
            game_id=rec.game_id,
            color=color,
            opponent=self.bots[1 - bot.slot].name,
            initial_fen=rec.game.initial_fen,
            move_timeout_s=self.settings.seat_timeout_s[bot.slot],
            max_attempts=self.settings.max_attempts,
        ))
        bot.announced_game = rec.game_id

    def _automatic_outcome(self, rec: GameRecord) -> Outcome | None:
        outcome = rec.state.outcome()
        if outcome is None and len(rec.game.moves) >= self.settings.max_plies:
            outcome = Outcome.draw("max_plies")
        return outcome

    async def _play_ply(self, rec: GameRecord) -> Outcome | None:
        outcome = self._automatic_outcome(rec)
        if outcome is not None:
            return outcome
        color = rec.state.turn
        bot = self.bots[rec.slot_of(color)]
        reply = await self._request_move(rec, bot, color)
        if reply is None or isinstance(reply, Outcome):
            return reply
        uci, think_s = reply
        if not bot.external and self._ply_budget is None:
            await self._pace_hold()
            if self._resigned is not None and self._resigned[0] == rec.game_id:
                return self._resigned[1]
        ply = len(rec.game.moves)
        san = rec.state.san(uci)
        rec.state.push(uci)
        rec.game.moves.append(uci)
        rec.think_s.append(round(think_s, 4))
        self._last_ply_at = asyncio.get_running_loop().time()
        self._emit("move", {"game_id": rec.game_id, "ply": ply, "side": color, "uci": uci,
                            "san": san, "fen": rec.state.fen, "think_s": rec.think_s[-1]})
        return self._automatic_outcome(rec)

    async def _pace_hold(self) -> None:
        """Hold a landed bot move until `min_ply_s` has passed since the previous ply."""
        loop = asyncio.get_running_loop()
        while True:
            self._wake.clear()
            remaining = self._last_ply_at + self.settings.min_ply_s - loop.time()
            if remaining <= 0 or self._stop_requested or self._resigned is not None:
                return
            try:
                await asyncio.wait_for(self._wake.wait(), remaining)
            except TimeoutError:
                return

    async def _request_move(
        self, rec: GameRecord, bot: BotProcess, color: str
    ) -> tuple[str, float] | Outcome | None:
        """The seat's legal move and think time, a forfeit, or None when a stop ends the wait."""
        state = rec.state
        ply = len(rec.game.moves)
        await bot.send(MoveRequest(
            game_id=rec.game_id, ply=ply, fen=state.fen, moves=list(rec.game.moves),
            legal_moves=state.legal_moves(), deadline_s=self.settings.seat_timeout_s[bot.slot],
        ))
        self.awaiting = {"slot": bot.slot, "color": color, "seat": bot.name,
                         "external": bot.external, "game_id": rec.game_id, "ply": ply,
                         "since": round(time.time(), 3)}
        self._emit("turn", {**self.awaiting, "fen": state.fen, "legal_moves": state.legal_moves(),
                            "deadline_s": self.settings.seat_timeout_s[bot.slot]})
        try:
            return await self._await_move(rec, bot, color, ply)
        finally:
            self.awaiting = None

    def _interrupt(self, rec: GameRecord, bot: BotProcess) -> Outcome | object | None:
        if self._resigned is not None and self._resigned[0] == rec.game_id:
            return self._resigned[1]
        # A bot's move is already on its way, so a stop waits for it. A person may never move.
        if self._stop_requested and bot.external:
            return STOPPED
        return None

    async def _next_item(self, rec: GameRecord, bot: BotProcess, timeout: float | None) -> Any:
        frame = asyncio.ensure_future(bot.next_frame(timeout))
        try:
            while not frame.done():
                self._wake.clear()
                interrupt = self._interrupt(rec, bot)
                if interrupt is not None:
                    return interrupt
                wake = asyncio.ensure_future(self._wake.wait())
                try:
                    await asyncio.wait({frame, wake}, return_when=asyncio.FIRST_COMPLETED)
                finally:
                    wake.cancel()
            return frame.result()
        finally:
            frame.cancel()

    async def _await_move(
        self, rec: GameRecord, bot: BotProcess, color: str, ply: int
    ) -> tuple[str, float] | Outcome | None:
        opponent = "black" if color == "white" else "white"
        state = rec.state
        timeout = self.settings.seat_timeout_s[bot.slot]
        loop = asyncio.get_running_loop()
        started = loop.time()
        invalid = 0
        while True:
            remaining = None if timeout is None else started + timeout - loop.time()
            if remaining is not None and remaining <= 0:
                return Outcome.win_for(opponent, "timeout")
            try:
                item = await self._next_item(rec, bot, remaining)
            except TimeoutError:
                return Outcome.win_for(opponent, "timeout")
            if item is STOPPED:
                return None
            if isinstance(item, Outcome):
                return item
            if item is DISCONNECTED:
                return Outcome.win_for(opponent, "disconnect")
            if isinstance(item, ProtocolError):
                log.warning("bot %s protocol error: %s", bot.label, item)
                return Outcome.win_for(opponent, "protocol_error")
            if (item.game_id, item.ply) != (rec.game_id, ply):
                continue
            if isinstance(item, Resign):
                return Outcome.win_for(opponent, "resignation")
            assert isinstance(item, Move)
            move = item.move
            if isinstance(move, str) and UCI_RE.match(move) and state.is_legal(move):
                return move, loop.time() - started
            if bot.external:
                continue
            reason = "illegal" if isinstance(move, str) and UCI_RE.match(move) else "malformed"
            invalid += 1
            self._reject(rec, ply, color, move, reason)
            if invalid >= self.settings.max_attempts:
                return Outcome.win_for(opponent, "illegal_move")
            await bot.send(MoveRejected(
                game_id=rec.game_id, ply=ply, move=move, reason=reason,
                legal_moves=state.legal_moves(),
                attempts_left=self.settings.max_attempts - invalid,
                remaining_s=round(max(started + timeout - loop.time(), 0.0), 3),
            ))

    def _reject(self, rec: GameRecord, ply: int, color: str, move: Any, reason: str) -> None:
        rejected = {"ply": ply, "side": color, "move": move, "reason": reason}
        rec.rejected.append(rejected)
        self._emit("rejected", {"game_id": rec.game_id, **rejected})

    async def _finish(self, rec: GameRecord, outcome: Outcome) -> None:
        rec.game.outcome = outcome
        self._resigned = None
        for bot in self.bots:
            await bot.send(GameOver(rec.game_id, outcome.result, outcome.reason))
        winner = outcome.winner
        if winner is None:
            self.score[0] += 0.5
            self.score[1] += 0.5
        else:
            self.score[rec.slot_of(winner)] += 1.0
        self._write_records(rec)
        self._emit("game_over", {"game_id": rec.game_id, "result": outcome.result,
                                 "reason": outcome.reason, "plies": len(rec.game.moves),
                                 "score": list(self.score)})
        log.info("game %s over: %s (%s) after %d plies",
                 rec.game_id, outcome.result, outcome.reason, len(rec.game.moves))

    def _write_records(self, rec: GameRecord) -> None:
        self.records.mkdir(parents=True, exist_ok=True)
        (self.records / f"game_{rec.index}.pgn").write_text(rec.game.to_pgn())
        (self.records / "record.json").write_text(json.dumps(self.to_save(), indent=1) + "\n")
