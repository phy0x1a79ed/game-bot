"""External seats: moves by control call, per-seat time limits, stop and resign mid-request."""

import asyncio

import pytest

from coms.protocol import RpcError
from game_master.match import Settings
from helpers import ScriptedBot, legal, running_match, settle, wait_awaiting


def _code(call, *args):
    with pytest.raises(RpcError) as info:
        call(*args)
    return info.value.code


def test_seat_time_limits():
    assert Settings.from_params(
        {"white": "@human", "black": "naive", "move_timeout_s": 2}).seat_timeout_s == [None, 2.0]
    assert Settings.from_params(
        {"white": "naive", "black": "@human", "seat_timeout_s": [1, 60]}).seat_timeout_s == [1.0, 60.0]
    for bad in ([None, None], [1], [0, 1], ["x", 1]):
        assert _code(Settings.from_params,
                     {"white": "naive", "black": "@human", "seat_timeout_s": bad}) == "invalid_params"


async def test_external_seat_outlasts_the_bot_limit_and_rejects_without_forfeit():
    async with running_match("@human", ScriptedBot("b"), move_timeout_s=0.2, max_plies=4,
                             max_attempts=1) as match:
        match.start()
        waiting = await wait_awaiting(match, 0)
        assert (waiting["color"], waiting["seat"], waiting["external"]) == ("white", "@human", True)
        assert match.state()["awaiting"] == waiting
        await asyncio.sleep(0.4)
        assert match.current.game.outcome is None

        gid = waiting["game_id"]
        for _ in range(3):
            rejected = match.submit_move("white", gid, 0, "e2e5")
            assert (rejected["accepted"], rejected["reason"]) == (False, "illegal")
        assert match.submit_move("white", gid, 0, "e9")["reason"] == "malformed"
        assert _code(match.submit_move, "black", gid, 0, "e7e5") == "not_your_turn"
        assert _code(match.submit_move, "white", gid, 1, "e2e4") == "stale"
        assert match.submit_move("white", gid, 0, "e2e4") == {"accepted": True, "san": "e4"}
        assert _code(match.submit_move, "white", gid, 0, "e2e4") == "not_your_turn"

        await wait_awaiting(match, 2)
        assert match.submit_move("white", gid, 2, "d2d4")["accepted"]
        assert await settle(match) == "finished"
        rec = match.current
        assert rec.game.outcome.reason == "max_plies"
        assert rec.game.moves[0::2] == ["e2e4", "d2d4"]
        assert len(rec.rejected) == 4


async def test_stop_and_resume_during_an_external_turn():
    async with running_match(ScriptedBot("w"), "@human", max_plies=4) as match:
        match.start()
        waiting = await wait_awaiting(match, 1)
        assert waiting["color"] == "black"
        await asyncio.wait_for(match.stop(), 2)
        assert (match.phase, match.awaiting) == ("stopped", None)
        assert _code(match.submit_move, "black", waiting["game_id"], 1, "e7e5") == "busy"
        match.start()
        await wait_awaiting(match, 1)
        assert len(match.current.game.moves) == 1


async def test_resign_on_own_turn_continues_the_series():
    async with running_match("@human", ScriptedBot("b"), games=2) as match:
        match.start()
        await wait_awaiting(match, 0)
        assert await asyncio.wait_for(match.resign("white"), 2) == {
            "result": "0-1", "reason": "resignation"}
        second = await wait_awaiting(match, 1)
        assert (second["game_id"], second["color"]) == ("tests-2", "black")
        assert match.score == [0.0, 1.0]


async def test_resign_while_the_bot_thinks():
    async def slow(ws, msg):
        await asyncio.sleep(1.0)
        await legal(ws, msg)

    async with running_match(ScriptedBot("w", slow), "@human") as match:
        match.start()
        await wait_awaiting(match, 0)
        assert (await asyncio.wait_for(match.resign("black"), 0.5))["result"] == "1-0"
        assert await settle(match) == "finished"
        assert match.current.game.moves == []


async def test_resign_while_stopped_and_for_a_bot():
    async with running_match("@human", ScriptedBot("b")) as match:
        match.start()
        await wait_awaiting(match, 0)
        await match.stop()
        with pytest.raises(RpcError) as info:
            await match.resign("black")
        assert info.value.code == "invalid_params"
        assert (await match.resign("white"))["result"] == "0-1"
        assert match.phase == "finished"
