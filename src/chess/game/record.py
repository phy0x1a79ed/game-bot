from __future__ import annotations

import io
from dataclasses import dataclass, field
from typing import Any

import chess
import chess.pgn

from game.state import STARTING_FEN, GameState, Outcome


@dataclass
class Game:
    """A played or in-progress game. `to_dict` is the save format."""

    initial_fen: str = STARTING_FEN
    moves: list[str] = field(default_factory=list)
    players: dict[str, str] = field(default_factory=lambda: {"white": "?", "black": "?"})
    outcome: Outcome | None = None
    meta: dict[str, Any] = field(default_factory=dict)

    def state(self) -> GameState:
        return GameState.from_moves(self.initial_fen, self.moves)

    def san_moves(self) -> list[str]:
        state = GameState.from_fen(self.initial_fen)
        sans = []
        for uci in self.moves:
            sans.append(state.san(uci))
            state.push(uci)
        return sans

    def to_dict(self) -> dict[str, Any]:
        return {
            "initial_fen": self.initial_fen,
            "moves": list(self.moves),
            "players": dict(self.players),
            "outcome": (
                {"result": self.outcome.result, "reason": self.outcome.reason}
                if self.outcome
                else None
            ),
            "meta": dict(self.meta),
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Game:
        outcome = data.get("outcome")
        game = cls(
            initial_fen=data.get("initial_fen", STARTING_FEN),
            moves=list(data.get("moves", [])),
            players=dict(data.get("players", {"white": "?", "black": "?"})),
            outcome=Outcome(outcome["result"], outcome["reason"]) if outcome else None,
            meta=dict(data.get("meta", {})),
        )
        game.state()  # validates the move list
        return game

    def to_pgn(self) -> str:
        board = chess.Board(self.initial_fen)
        for uci in self.moves:
            board.push_uci(uci)
        pgn = chess.pgn.Game.from_board(board)
        pgn.headers["Event"] = str(self.meta.get("event", "chess arena"))
        pgn.headers["Site"] = "local"
        pgn.headers["Round"] = str(self.meta.get("round", "?"))
        pgn.headers["White"] = self.players.get("white", "?")
        pgn.headers["Black"] = self.players.get("black", "?")
        if "date" in self.meta:
            pgn.headers["Date"] = str(self.meta["date"])
        pgn.headers["Result"] = self.outcome.result if self.outcome else "*"
        if self.outcome:
            pgn.headers["Termination"] = self.outcome.reason
        return str(pgn) + "\n"

    @classmethod
    def from_pgn(cls, text: str) -> Game:
        pgn = chess.pgn.read_game(io.StringIO(text))
        if pgn is None:
            raise ValueError("no game found in PGN")
        if pgn.errors:
            raise ValueError(f"PGN errors: {pgn.errors}")
        headers = pgn.headers
        result = headers.get("Result", "*")
        outcome = None
        if result != "*":
            outcome = Outcome(result, headers.get("Termination", "unknown"))
        meta = {}
        if headers.get("Round", "?") != "?":
            meta["round"] = headers["Round"]
        return cls(
            initial_fen=pgn.board().fen(),
            moves=[m.uci() for m in pgn.mainline_moves()],
            players={"white": headers.get("White", "?"), "black": headers.get("Black", "?")},
            outcome=outcome,
            meta=meta,
        )
