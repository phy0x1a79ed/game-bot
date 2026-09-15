from __future__ import annotations

import math

from coms.bot import Bot
from coms.protocol import GameStart, MoveRequest
from game import GameState

PIECE_VALUES = {"pawn": 1, "knight": 3, "bishop": 3, "rook": 5, "queen": 9, "king": 0}
MATE = 10_000


class SimpleBot(Bot):
    name = "simple"
    version = "1"
    depth = 2

    def on_game_start(self, start: GameStart) -> None:
        self.initial_fen = start.initial_fen

    def choose_move(self, request: MoveRequest) -> str:
        state = GameState.from_request(request, initial_fen=getattr(self, "initial_fen", None))
        best = -math.inf
        best_moves: list[str] = []
        for uci in self._ordered(state, request.legal_moves):
            state.push(uci)
            # Searching with alpha just under the best score keeps ties exact,
            # so every equally good move joins the random tie-break.
            score = -self._negamax(state, self.depth - 1, -math.inf, -(best - 0.5))
            state.pop()
            if score > best:
                best, best_moves = score, [uci]
            elif score == best:
                best_moves.append(uci)
        return self.rng.choice(best_moves)

    def _negamax(self, state: GameState, depth: int, alpha: float, beta: float) -> float:
        outcome = state.outcome()
        if outcome is not None:
            # The side to move is never the winner. Sooner mates score higher.
            return 0 if outcome.winner is None else -(MATE + depth)
        if depth == 0:
            return self._material(state)
        for uci in self._ordered(state, state.legal_moves()):
            state.push(uci)
            score = -self._negamax(state, depth - 1, -beta, -alpha)
            state.pop()
            if score >= beta:
                return score
            alpha = max(alpha, score)
        return alpha

    @staticmethod
    def _material(state: GameState) -> int:
        me = state.turn
        total = 0
        for piece in state.pieces().values():
            value = PIECE_VALUES[piece.kind]
            total += value if piece.color == me else -value
        return total

    @staticmethod
    def _ordered(state: GameState, moves: list[str]) -> list[str]:
        return sorted(moves, key=lambda uci: not state.is_capture(uci))
