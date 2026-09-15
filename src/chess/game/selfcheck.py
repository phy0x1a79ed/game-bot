"""Smoke check of the rules wrapper: `python -m game.selfcheck`."""

from game import Game, GameState, perft

KIWIPETE = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"


def main() -> None:
    assert perft(GameState.initial(), 3) == 8902
    assert perft(GameState.from_fen(KIWIPETE), 2) == 2039

    state = GameState.initial()
    for uci in ["f2f3", "e7e5", "g2g4", "d8h4"]:
        state = state.apply(uci)
    outcome = state.outcome()
    assert outcome is not None and (outcome.result, outcome.reason) == ("0-1", "checkmate")

    stalemate = GameState.from_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    assert stalemate.outcome().reason == "stalemate"
    assert not stalemate.legal_moves()

    game = Game(moves=state.moves, players={"white": "a", "black": "b"}, outcome=outcome)
    assert Game.from_dict(game.to_dict()) == game
    back = Game.from_pgn(game.to_pgn())
    assert (back.moves, back.outcome, back.players) == (game.moves, outcome, game.players)
    print("game selfcheck ok")


if __name__ == "__main__":
    main()
