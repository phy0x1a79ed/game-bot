from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

import chess

STARTING_FEN = chess.STARTING_FEN

PIECE_KINDS = {
    chess.PAWN: "pawn",
    chess.KNIGHT: "knight",
    chess.BISHOP: "bishop",
    chess.ROOK: "rook",
    chess.QUEEN: "queen",
    chess.KING: "king",
}

_AUTOMATIC_ENDINGS = {
    chess.Termination.CHECKMATE: "checkmate",
    chess.Termination.STALEMATE: "stalemate",
    chess.Termination.INSUFFICIENT_MATERIAL: "insufficient_material",
    chess.Termination.SEVENTYFIVE_MOVES: "seventyfive_moves",
    chess.Termination.FIVEFOLD_REPETITION: "fivefold_repetition",
}


class IllegalMoveError(ValueError):
    pass


@dataclass(frozen=True)
class Outcome:
    result: str  # "1-0", "0-1" or "1/2-1/2"
    reason: str

    @property
    def winner(self) -> str | None:
        return {"1-0": "white", "0-1": "black"}.get(self.result)

    @classmethod
    def win_for(cls, color: str, reason: str) -> Outcome:
        return cls("1-0" if color == "white" else "0-1", reason)

    @classmethod
    def draw(cls, reason: str) -> Outcome:
        return cls("1/2-1/2", reason)


@dataclass(frozen=True)
class Piece:
    color: str  # "white" or "black"
    kind: str  # "pawn", "knight", "bishop", "rook", "queen", "king"
    symbol: str  # FEN letter, uppercase for white


def _color_name(color: bool) -> str:
    return "white" if color == chess.WHITE else "black"


def _piece(p: chess.Piece) -> Piece:
    return Piece(_color_name(p.color), PIECE_KINDS[p.piece_type], p.symbol())


class GameState:
    """One position plus the moves that led to it from its root FEN."""

    __slots__ = ("_board",)

    def __init__(self, board: chess.Board):
        self._board = board

    @classmethod
    def initial(cls) -> GameState:
        return cls(chess.Board())

    @classmethod
    def from_fen(cls, fen: str) -> GameState:
        try:
            return cls(chess.Board(fen))
        except ValueError as exc:
            raise ValueError(f"invalid FEN {fen!r}: {exc}") from exc

    @classmethod
    def from_moves(cls, initial_fen: str, moves: list[str]) -> GameState:
        state = cls.from_fen(initial_fen)
        for uci in moves:
            state.push(uci)
        return state

    @classmethod
    def from_request(
        cls, request: Mapping[str, Any] | Any, initial_fen: str | None = None
    ) -> GameState:
        """Rebuild the position of a `move_request`.

        With `initial_fen` (from `game_start`) the move history is replayed, so
        repetition counts are exact. Without it the state starts at `fen`.
        """
        get = request.get if isinstance(request, Mapping) else lambda k: getattr(request, k)
        fen = get("fen")
        if initial_fen is not None:
            state = cls.from_moves(initial_fen, list(get("moves")))
            if state.fen == fen:
                return state
        return cls.from_fen(fen)

    @property
    def fen(self) -> str:
        return self._board.fen()

    @property
    def initial_fen(self) -> str:
        return self._board.root().fen()

    @property
    def moves(self) -> list[str]:
        return [m.uci() for m in self._board.move_stack]

    @property
    def turn(self) -> str:
        return _color_name(self._board.turn)

    @property
    def ply(self) -> int:
        return self._board.ply()

    @property
    def last_move(self) -> str | None:
        return self._board.move_stack[-1].uci() if self._board.move_stack else None

    def legal_moves(self) -> list[str]:
        return [m.uci() for m in self._board.legal_moves]

    def is_legal(self, uci: str) -> bool:
        try:
            move = chess.Move.from_uci(uci)
        except (ValueError, TypeError):
            return False
        return self._board.is_legal(move)

    def _parse(self, uci: str) -> chess.Move:
        try:
            move = chess.Move.from_uci(uci)
        except (ValueError, TypeError) as exc:
            raise IllegalMoveError(f"malformed move {uci!r}") from exc
        if not self._board.is_legal(move):
            raise IllegalMoveError(f"illegal move {uci!r} in {self.fen}")
        return move

    def push(self, uci: str) -> None:
        self._board.push(self._parse(uci))

    def pop(self) -> str:
        return self._board.pop().uci()

    def apply(self, uci: str) -> GameState:
        new = self.copy()
        new.push(uci)
        return new

    def copy(self) -> GameState:
        return GameState(self._board.copy(stack=True))

    def san(self, uci: str) -> str:
        return self._board.san(self._parse(uci))

    def is_capture(self, uci: str) -> bool:
        return self._board.is_capture(self._parse(uci))

    def gives_check(self, uci: str) -> bool:
        return self._board.gives_check(self._parse(uci))

    def piece_at(self, square: str) -> Piece | None:
        p = self._board.piece_at(chess.parse_square(square))
        return _piece(p) if p else None

    def pieces(self) -> dict[str, Piece]:
        return {
            chess.square_name(sq): _piece(p) for sq, p in self._board.piece_map().items()
        }

    def is_check(self) -> bool:
        return self._board.is_check()

    def outcome(self) -> Outcome | None:
        o = self._board.outcome(claim_draw=False)
        if o is None:
            return None
        return Outcome(o.result(), _AUTOMATIC_ENDINGS[o.termination])

    def ascii(self) -> str:
        rows = str(self._board).splitlines()
        board = [f"{8 - i} {row}" for i, row in enumerate(rows)]
        return "\n".join(board + ["  a b c d e f g h"])

    def __eq__(self, other: object) -> bool:
        return isinstance(other, GameState) and self.fen == other.fen

    def __repr__(self) -> str:
        return f"GameState({self.fen!r})"


def perft(state: GameState, depth: int) -> int:
    """Count leaf nodes of the legal move tree, the standard move-generator check."""
    if depth == 0:
        return 1
    total = 0
    for uci in state.legal_moves():
        state.push(uci)
        total += perft(state, depth - 1)
        state.pop()
    return total
