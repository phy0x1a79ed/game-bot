"""The play loop against in-process bots, one Contract A rule per test."""

import asyncio

from ai_naive.__main__ import NaiveBot
from coms.bot import Bot
from coms.protocol import GameOver, GameStart, MoveRejected, MoveRequest
from game import GameState
from helpers import (
    ScriptedBot,
    disconnect,
    legal,
    raw,
    resign,
    running_match,
    send,
    settle,
    silent,
    stale_then_legal,
)


def _only_game(match):
    assert len(match.games) == 1
    rec = match.games[0]
    assert rec.state.fen == rec.game.state().fen
    return rec


async def test_naive_series_with_real_bot_class():
    async with running_match(NaiveBot(seed=1), NaiveBot(seed=2), games=2, max_plies=60) as match:
        match.start()
        assert await settle(match) == "finished"
        assert [rec.white_slot for rec in match.games] == [0, 1]
        assert all(rec.finished for rec in match.games)
        assert sum(match.score) == 2
        for rec in match.games:
            assert rec.game.state().outcome() == rec.game.outcome or rec.game.outcome.reason == "max_plies"
            assert (match.records / f"game_{rec.index}.pgn").is_file()
        assert match.games[1].game.players == {"white": "naive", "black": "naive"}


async def test_illegal_move_is_rejected_with_legal_moves_then_retry_continues():
    white = ScriptedBot("w", send("e2e5"))
    black = ScriptedBot("b")
    async with running_match(white, black, max_plies=4, max_attempts=3) as match:
        match.start()
        assert await settle(match) == "finished"
        rec = _only_game(match)
        assert rec.rejected == [{"ply": 0, "side": "white", "move": "e2e5", "reason": "illegal"}]
        assert len(rec.game.moves) == 4
        assert rec.game.outcome.reason == "max_plies"
        (rejected,) = white.prompts(MoveRejected)
        assert sorted(rejected.legal_moves) == sorted(GameState.initial().legal_moves())
        assert rejected.attempts_left == 2
        assert 0 < rejected.remaining_s <= match.settings.move_timeout_s


async def test_malformed_moves_are_rejected():
    white = ScriptedBot("w", send(42), send("nonsense"), send(None))
    async with running_match(white, ScriptedBot("b"), max_plies=2) as match:
        match.start()
        await settle(match)
        rec = _only_game(match)
        assert [r["reason"] for r in rec.rejected] == ["malformed"] * 3
        assert [r.attempts_left for r in white.prompts(MoveRejected)] == [4, 3, 2]
        assert len(rec.game.moves) == 2


class RetryBot(Bot):
    name = "retry"

    def __init__(self):
        super().__init__()
        self.rejections = []

    def choose_move(self, request: MoveRequest) -> str:
        return "a1a1" if not self.rejections else request.legal_moves[0]

    def on_move_rejected(self, rejected, request):
        self.rejections.append(rejected)
        return super().on_move_rejected(rejected, request)


async def test_bot_base_class_retries_after_rejection():
    bot = RetryBot()
    async with running_match(bot, ScriptedBot("b"), max_plies=2) as match:
        match.start()
        assert await settle(match) == "finished"
        rec = _only_game(match)
        assert len(bot.rejections) == 1
        assert rec.game.moves[0] == bot.rejections[0].legal_moves[0]


async def test_attempt_cap_forfeits():
    white = ScriptedBot("w", *[send("e2e5")] * 3)
    async with running_match(white, ScriptedBot("b"), max_attempts=3) as match:
        match.start()
        await settle(match)
        rec = _only_game(match)
        assert (rec.game.outcome.result, rec.game.outcome.reason) == ("0-1", "illegal_move")
        assert len(rec.rejected) == 3
        assert len(white.prompts(MoveRejected)) == 2
        assert match.score == [0.0, 1.0]


async def test_timeout_forfeits():
    async with running_match(ScriptedBot("w", silent), ScriptedBot("b"),
                             move_timeout_s=0.3) as match:
        match.start()
        await settle(match)
        rec = _only_game(match)
        assert (rec.game.outcome.result, rec.game.outcome.reason) == ("0-1", "timeout")


async def test_retries_share_one_deadline():
    async def slow_illegal(ws, msg):
        await asyncio.sleep(0.2)
        await send("e2e5")(ws, msg)

    white = ScriptedBot("w", *[slow_illegal] * 4)
    async with running_match(white, ScriptedBot("b"), move_timeout_s=0.5, max_attempts=10) as match:
        match.start()
        await settle(match)
        rec = _only_game(match)
        assert rec.game.outcome.reason == "timeout"
        assert len(rec.rejected) == 2


async def test_stale_moves_are_ignored():
    async with running_match(ScriptedBot("w", stale_then_legal), ScriptedBot("b"),
                             max_plies=2) as match:
        match.start()
        await settle(match)
        rec = _only_game(match)
        assert rec.rejected == []
        assert rec.game.moves[0] == GameState.initial().legal_moves()[0]


async def test_disconnect_forfeits_and_ends_the_series():
    async with running_match(ScriptedBot("w", disconnect), ScriptedBot("b"), games=3) as match:
        match.start()
        assert await settle(match) == "finished"
        rec = _only_game(match)
        assert (rec.game.outcome.result, rec.game.outcome.reason) == ("0-1", "disconnect")
        assert "bot disconnected: 0:w" in match.note


async def test_protocol_error_forfeits():
    async with running_match(ScriptedBot("w"), ScriptedBot("b", raw("not json"))) as match:
        match.start()
        await settle(match)
        rec = _only_game(match)
        assert (rec.game.outcome.result, rec.game.outcome.reason) == ("1-0", "protocol_error")


async def test_resignation():
    black = ScriptedBot("b", resign)
    async with running_match(ScriptedBot("w"), black) as match:
        match.start()
        await settle(match)
        rec = _only_game(match)
        assert (rec.game.outcome.result, rec.game.outcome.reason) == ("1-0", "resignation")
        assert black.prompts(GameOver) == [GameOver(rec.game_id, "1-0", "resignation")]
        assert [s.color for s in black.prompts(GameStart)] == ["black"]


class SlowNaive(NaiveBot):
    async def choose_move(self, request):
        await asyncio.sleep(0.01)
        return self.rng.choice(request.legal_moves)


async def test_stop_and_resume():
    async with running_match(SlowNaive(seed=3), SlowNaive(seed=4), max_plies=40) as match:
        match.start()
        await asyncio.sleep(0.15)
        await match.stop()
        assert match.phase == "stopped"
        rec = _only_game(match)
        played = len(rec.game.moves)
        assert 0 < played < 40
        await asyncio.sleep(0.2)
        assert len(rec.game.moves) == played
        match.start()
        assert await settle(match) == "finished"
        assert len(rec.game.moves) > played
        assert rec.finished
