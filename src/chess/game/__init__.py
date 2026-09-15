"""Chess rules for the arena: positions, legal moves, outcomes, and game records.

This package is the only code that imports python-chess. Its API exposes plain
strings (UCI moves, FEN positions, square names) and the small types below.
"""

from game.state import (
    STARTING_FEN,
    GameState,
    IllegalMoveError,
    Outcome,
    Piece,
    perft,
)
from game.record import Game

__all__ = [
    "STARTING_FEN",
    "Game",
    "GameState",
    "IllegalMoveError",
    "Outcome",
    "Piece",
    "perft",
]
