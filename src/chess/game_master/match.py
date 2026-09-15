"""Plays a series of games between two bot processes on the `game` library."""

from __future__ import annotations

import asyncio
import dataclasses
import datetime
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

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

log = logging.getLogger(__name__)

UCI_RE = re.compile(r"^[a-h][1-8][a-h][1-8][qrbn]?$")


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

    _TYPES = {
        "white": str, "black": str, "games": int, "alternate": bool, "fen": str,
        "move_timeout_s": float, "max_attempts": int, "max_plies": int, "seed": int,
    }
    _NULLABLE = {"fen", "seed"}

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

    def history(self) -> dict[str, Any]:
        first = GameState.from_fen(self.game.initial_fen).turn
        other = "black" if first == "white" else "white"
        moves = []
        for ply, (uci, san) in enumerate(zip(self.game.moves, self.game.san_moves())):
            moves.append({
                "ply": ply,
                "side": first if ply % 2 == 0 else other,
                "uci": uci,
                "san": san,
                "think_s": self.think_s[ply] if ply < len(self.think_s) else None,
            })
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

    def __init__(self, sid: str, settings: Settings, bots: list[BotProcess], records: Path):
        self.sid = sid
        self.settings = settings
        self.bots = bots
        self.records = records
        self.games: list[GameRecord] = []
        self.score = [0.0, 0.0]
        self.phase = "stopped"
        self.note: str | None = None
        self._task: asyncio.Task | None = None
        self._stop_requested = False

    @classmethod
    def from_save(
        cls, sid: str, data: dict[str, Any], bots: list[BotProcess], records: Path
    ) -> Match:
        match = cls(sid, Settings.from_params(data["settings"]), bots, records)
        match.games = [GameRecord.from_dict(g) for g in data.get("games", [])]
        match.score = [float(x) for x in data.get("score", [0.0, 0.0])]
        if match._series_done():
            match.phase = "finished"
        return match

    @property
    def current(self) -> GameRecord | None:
        return self.games[-1] if self.games else None

    # --- control ---

    def start(self) -> None:
        if self.phase == "running":
            raise RpcError("busy", "play is already running")
        if self.phase == "finished":
            raise RpcError("busy", "the series is finished")
        self._stop_requested = False
        self.phase = "running"
        self._task = asyncio.create_task(self._run())

    async def stop(self) -> None:
        if self.phase != "running":
            raise RpcError("busy", f"cannot stop while {self.phase}")
        self._stop_requested = True
        await asyncio.shield(self._task)

    async def shutdown(self) -> None:
        if self._task is not None and not self._task.done():
            self._task.cancel()
            await asyncio.gather(self._task, return_exceptions=True)
        rec = self.current
        if rec is not None and not rec.finished:
            for bot in self.bots:
                if bot.announced_game == rec.game_id:
                    await bot.send(GameOver(rec.game_id, "1/2-1/2", "stopped"))
            self._write_pgn(rec)
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
            "bots": [
                {
                    "slot": bot.slot,
                    "name": bot.name,
                    "color": ("white" if rec.white_slot == bot.slot else "black") if rec else None,
                    "points": self.score[bot.slot],
                    "pid": bot.pid,
                    "alive": bot.alive,
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
                    "players": None}
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
        }

    def history(self, game_id: str | None = None) -> dict[str, Any]:
        if game_id is None:
            if self.current is None:
                raise RpcError("not_found", "no game has started")
            return self.current.history()
        for rec in self.games:
            if rec.game_id == game_id:
                return rec.history()
        raise RpcError("not_found", f"no game {game_id!r} in this session")

    def to_save(self) -> dict[str, Any]:
        return {
            "format": 1,
            "sid": self.sid,
            "saved_at": datetime.datetime.now().isoformat(timespec="seconds"),
            "settings": self.settings.to_dict(),
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
                if self._stop_requested:
                    self.phase = "stopped"
                    return
                rec = self.current
                if rec is None or rec.finished:
                    if self._series_done():
                        self.phase = "finished"
                        return
                    rec = self._new_game()
                for bot in self.bots:
                    await self._announce(rec, bot)
                outcome = await self._play_ply(rec)
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

    def _new_game(self) -> GameRecord:
        index = len(self.games) + 1
        white_slot = (index - 1) % 2 if self.settings.alternate else 0
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
            move_timeout_s=self.settings.move_timeout_s,
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
        if isinstance(reply, Outcome):
            return reply
        uci, think_s = reply
        rec.state.push(uci)
        rec.game.moves.append(uci)
        rec.think_s.append(round(think_s, 4))
        return self._automatic_outcome(rec)

    async def _request_move(
        self, rec: GameRecord, bot: BotProcess, color: str
    ) -> tuple[str, float] | Outcome:
        opponent = "black" if color == "white" else "white"
        state = rec.state
        ply = len(rec.game.moves)
        legal = state.legal_moves()
        timeout = self.settings.move_timeout_s
        loop = asyncio.get_running_loop()
        started = loop.time()
        await bot.send(MoveRequest(
            game_id=rec.game_id, ply=ply, fen=state.fen, moves=list(rec.game.moves),
            legal_moves=legal, deadline_s=timeout,
        ))
        invalid = 0
        while True:
            remaining = started + timeout - loop.time()
            if remaining <= 0:
                return Outcome.win_for(opponent, "timeout")
            try:
                item = await bot.next_frame(remaining)
            except TimeoutError:
                return Outcome.win_for(opponent, "timeout")
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
            reason = "illegal" if isinstance(move, str) and UCI_RE.match(move) else "malformed"
            invalid += 1
            rec.rejected.append({"ply": ply, "side": color, "move": move, "reason": reason})
            if invalid >= self.settings.max_attempts:
                return Outcome.win_for(opponent, "illegal_move")
            await bot.send(MoveRejected(
                game_id=rec.game_id, ply=ply, move=move, reason=reason, legal_moves=legal,
                attempts_left=self.settings.max_attempts - invalid,
                remaining_s=round(max(started + timeout - loop.time(), 0.0), 3),
            ))

    async def _finish(self, rec: GameRecord, outcome: Outcome) -> None:
        rec.game.outcome = outcome
        for bot in self.bots:
            await bot.send(GameOver(rec.game_id, outcome.result, outcome.reason))
        winner = outcome.winner
        if winner is None:
            self.score[0] += 0.5
            self.score[1] += 0.5
        else:
            self.score[rec.slot_of(winner)] += 1.0
        self._write_pgn(rec)
        log.info("game %s over: %s (%s) after %d plies",
                 rec.game_id, outcome.result, outcome.reason, len(rec.game.moves))

    def _write_pgn(self, rec: GameRecord) -> None:
        self.records.mkdir(parents=True, exist_ok=True)
        (self.records / f"game_{rec.index}.pgn").write_text(rec.game.to_pgn())
