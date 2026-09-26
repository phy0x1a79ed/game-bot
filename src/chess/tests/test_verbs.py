"""The client verbs over detached sessions."""

import asyncio
import json

import pytest

from game_master import paths, sessions, verbs


async def _error(verb, args=None):
    with pytest.raises(verbs.VerbError) as info:
        await verbs.dispatch(verb, args)
    return info.value.code


async def _status(sid):
    (status,) = (await verbs.dispatch("status", {"session_id": sid}))["sessions"]
    return status


async def _wait_external_turn(sid, ply, timeout=20.0):
    async with asyncio.timeout(timeout):
        while True:
            waiting = (await verbs.dispatch("observe", {"session_id": sid}))["state"]["awaiting"]
            if waiting and waiting["external"] and waiting["ply"] == ply:
                return waiting
            await asyncio.sleep(0.05)


@pytest.fixture
async def cleanup():
    yield
    await asyncio.gather(*(sessions.kill(sid) for sid in sessions.live_sessions()))


async def test_bad_requests():
    assert await _error("fly") == "unknown_method"
    assert await _error("observe", {"session_id": "../x"}) == "invalid_params"
    assert await _error("observe", {"session_id": "zzzzz"}) == "not_running"
    assert await _error("snapshot", {"session_id": "zzzzz"}) == "not_running"
    assert await _error("start", {"white": "naive", "black": "naive", "speed": 3}) \
        == "invalid_params"
    assert await _error("start", {"white": "nobody", "black": "naive"}) == "invalid_params"
    assert await _error("start", {"load": "no-such-save"}) == "not_found"
    assert await _error("replay", {}) == "invalid_params"
    assert await _error("replay", {"name": "a", "session_id": "zzzzz"}) == "invalid_params"
    assert await _error("replay", {"name": "no-such-save"}) == "not_found"
    assert await _error("rematch", {"session_id": "zzzzz"}) == "not_found"
    assert "naive" in (await verbs.dispatch("bots"))["bots"]


async def test_bot_game_gets_the_default_pace_labels_and_a_snapshot(cleanup):
    started = await verbs.dispatch("start", {"white": "naive", "black": "naive", "max_plies": 4})
    sid = started["session_id"]
    assert started["mode"] == "bvb"
    status = await _status(sid)
    assert status["min_ply_s"] == verbs.BOT_PACE_S
    assert status["labels"] == {"owner": "viewer", "mode": "bvb"}
    assert sid in [s["sid"] for s in (await verbs.dispatch("status"))["sessions"]]
    saved = json.loads((paths.records_dir(sid) / verbs.START_FILE).read_text())
    assert saved["start"]["min_ply_s"] == verbs.BOT_PACE_S

    snap = await verbs.dispatch("snapshot", {"session_id": sid})
    assert snap["snapshot"]["status"]["sid"] == sid and isinstance(snap["seq"], int)
    assert await verbs.dispatch("pause", {"session_id": sid}) == {"phase": "stopped"}
    assert (await verbs.dispatch("set_pace", {"session_id": sid, "min_ply_s": 0}))["min_ply_s"] == 0
    assert (await verbs.dispatch("step", {"session_id": sid}))["phase"] == "stopped"
    assert (await _status(sid))["watchers"] == 0
    assert await verbs.dispatch("kill", {"session_id": sid}) == {"killed": True, "session_id": sid}
    assert sid not in sessions.live_sessions()


async def test_external_seat_move_resign_save_replay_rematch(cleanup):
    started = await verbs.dispatch("start", {"white": "@human", "black": "naive", "seed": 1,
                                             "owner": "tests"})
    sid = started["session_id"]
    assert started["mode"] == "pvb"
    assert (await _status(sid))["min_ply_s"] == 0

    await _wait_external_turn(sid, 0)
    assert await _error("move", {"session_id": sid, "move": "e2e4", "ply": 1}) == "stale"
    assert await _error("move", {"session_id": sid, "move": "e2e4", "ply": "0"}) \
        == "invalid_params"
    assert await verbs.dispatch("move", {"session_id": sid, "move": "e2e4", "ply": 0}) == {
        "accepted": True, "san": "e4"}
    await _wait_external_turn(sid, 2)
    assert await verbs.dispatch("resign", {"session_id": sid}) == {
        "result": "0-1", "reason": "resignation"}
    assert await _error("move", {"session_id": sid, "move": "d2d4"}) == "not_your_turn"

    await verbs.dispatch("save", {"session_id": sid, "name": "t-verbs"})
    assert "t-verbs" in [s["name"] for s in (await verbs.dispatch("saves"))["saves"]]
    replay = await verbs.dispatch("replay", {"name": "t-verbs"})
    assert replay["moves"][0]["uci"] == "e2e4" and replay["labels"]["owner"] == "tests"
    assert (await verbs.dispatch("replay", {"session_id": sid}))["moves"][0]["uci"] == "e2e4"

    again = await verbs.dispatch("rematch", {"session_id": sid})
    assert again["previous"] == sid and again["session_id"] != sid
    assert sid not in sessions.live_sessions()
    status = await _status(again["session_id"])
    assert [b["name"] for b in status["bots"]] == ["@human", "naive"]
    assert status["labels"] == {"owner": "tests", "mode": "pvb"}

    loaded = await verbs.dispatch("start", {"load": "t-verbs"})
    assert loaded["mode"] == "pvb"
    assert (await _status(loaded["session_id"]))["loaded_from"] == "t-verbs"
