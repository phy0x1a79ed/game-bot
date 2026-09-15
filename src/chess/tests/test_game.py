import pytest

from game import STARTING_FEN, Game, GameState, IllegalMoveError, Outcome, perft

KIWIPETE = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"


@pytest.mark.parametrize("depth, nodes", [(1, 20), (2, 400), (3, 8902)])
def test_perft_initial(depth, nodes):
    assert perft(GameState.initial(), depth) == nodes


def test_perft_kiwipete():
    assert perft(GameState.from_fen(KIWIPETE), 2) == 2039


def _play(moves, fen=STARTING_FEN):
    return GameState.from_moves(fen, moves)


@pytest.mark.parametrize(
    "state, outcome",
    [
        (_play(["f2f3", "e7e5", "g2g4", "d8h4"]), Outcome("0-1", "checkmate")),
        (GameState.from_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"), Outcome("1/2-1/2", "stalemate")),
        (GameState.from_fen("8/8/8/4k3/8/8/8/4K3 w - - 0 1"),
         Outcome("1/2-1/2", "insufficient_material")),
        (GameState.from_fen("7k/8/8/8/8/8/8/R6K w - - 150 100"),
         Outcome("1/2-1/2", "seventyfive_moves")),
        (_play(["g1f3", "g8f6", "f3g1", "f6g8"] * 4), Outcome("1/2-1/2", "fivefold_repetition")),
    ],
    ids=["checkmate", "stalemate", "insufficient_material", "seventyfive_moves", "fivefold"],
)
def test_outcome_reasons(state, outcome):
    assert state.outcome() == outcome


def test_threefold_is_not_claimed():
    assert _play(["g1f3", "g8f6", "f3g1", "f6g8"] * 2).outcome() is None


def test_push_pop_round_trip():
    state = GameState.initial()
    for uci in ["e2e4", "e7e5", "g1f3"]:
        state.push(uci)
    assert state.moves == ["e2e4", "e7e5", "g1f3"]
    assert (state.turn, state.ply, state.last_move) == ("black", 3, "g1f3")
    assert [state.pop() for _ in range(3)] == ["g1f3", "e7e5", "e2e4"]
    assert state == GameState.initial()


def test_apply_leaves_original_unchanged():
    state = GameState.initial()
    after = state.apply("e2e4")
    assert state.fen == STARTING_FEN
    assert after.moves == ["e2e4"]
    assert after.initial_fen == STARTING_FEN
    assert after.piece_at("e4").kind == "pawn"


@pytest.mark.parametrize("move", ["e2e5", "a1a1", "nonsense", ""])
def test_push_rejects_bad_moves(move):
    state = GameState.initial()
    assert not state.is_legal(move)
    with pytest.raises(IllegalMoveError):
        state.push(move)
    assert state.fen == STARTING_FEN


def test_from_request_replays_history():
    moves = ["g1f3", "g8f6", "f3g1", "f6g8"] * 2
    fen = _play(moves).fen
    request = {"fen": fen, "moves": moves}
    replayed = GameState.from_request(request, initial_fen=STARTING_FEN)
    assert replayed.moves == moves
    assert GameState.from_request(request).moves == []
    mismatched = GameState.from_request({"fen": fen, "moves": ["e2e4"]}, STARTING_FEN)
    assert (mismatched.fen, mismatched.moves) == (fen, [])


def _sample_game(fen=STARTING_FEN):
    state = GameState.from_fen(fen)
    for _ in range(6):
        state.push(state.legal_moves()[0])
    return Game(initial_fen=fen, moves=state.moves, players={"white": "a", "black": "b"},
                outcome=Outcome.draw("max_plies"), meta={"round": 2})


@pytest.mark.parametrize("fen", [STARTING_FEN, KIWIPETE])
def test_dict_round_trip(fen):
    game = _sample_game(fen)
    assert Game.from_dict(game.to_dict()) == game


@pytest.mark.parametrize("fen", [STARTING_FEN, KIWIPETE])
def test_pgn_round_trip(fen):
    game = _sample_game(fen)
    back = Game.from_pgn(game.to_pgn())
    assert (back.initial_fen, back.moves, back.players, back.outcome) == (
        game.initial_fen, game.moves, game.players, game.outcome)


def test_from_dict_rejects_illegal_history():
    with pytest.raises(IllegalMoveError):
        Game.from_dict({"moves": ["e2e4", "e2e4"]})
