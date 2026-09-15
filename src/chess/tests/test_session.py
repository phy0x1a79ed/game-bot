"""The control API of one session, with real bot processes."""

import asyncio
import json

import pytest

from coms.protocol import RpcError
from game import Game
from game_master import paths
from game_master.daemon import Session
from helpers import short_dir


async def _dispatch_error(session, method, params=None):
    with pytest.raises(RpcError) as info:
        await session.dispatch(method, params or {})
    return info.value.code


async def _settle(session, timeout=60.0):
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while (status := await session.dispatch("status", {}))["phase"] == "running":
        assert loop.time() < deadline, "session did not settle in time"
        await asyncio.sleep(0.05)
    return status


@pytest.fixture
async def new_session():
    sessions = []

    def make():
        runtime = short_dir()
        session = Session("tests", runtime, runtime / "records")
        sessions.append(session)
        return session

    yield make
    for session in sessions:
        await session.close()
    for session in sessions:
        for bot in session.bots:
            assert bot.proc.returncode is not None, f"bot {bot.label} still running"
            assert not bot.socket_path.exists()


async def test_before_init(new_session):
    session = new_session()
    status = await session.dispatch("status", {})
    assert status["phase"] == "idle"
    assert isinstance((await session.dispatch("list_saves", {}))["saves"], list)
    for method in ["state", "history", "stop", "resume", "save"]:
        assert await _dispatch_error(session, method) == "no_game"


async def test_unknown_bot_fails_init_and_blocks_a_second_init(new_session):
    session = new_session()
    params = {"white": "nobody", "black": "naive"}
    assert await _dispatch_error(session, "start_game", params) == "invalid_params"
    assert (await session.dispatch("status", {}))["phase"] == "idle"
    assert await _dispatch_error(session, "start_game", {"white": "naive", "black": "naive"}) \
        == "already_initialized"


async def test_start_save_load_resume(new_session):
    first = new_session()
    params = {"white": "naive", "black": "naive", "games": 3, "max_plies": 200, "seed": 7}
    assert await first.dispatch("start_game", params) == {"sid": "tests"}
    assert await _dispatch_error(first, "start_game", params) == "already_initialized"
    assert await _dispatch_error(first, "load", {"name": "x"}) == "already_initialized"
    assert await _dispatch_error(first, "resume") == "busy"

    while (await first.dispatch("state", {}))["ply"] < 4:
        await asyncio.sleep(0.005)
    await first.dispatch("stop", {})
    status = await first.dispatch("status", {})
    assert status["phase"] == "stopped", status
    assert [b["alive"] for b in status["bots"]] == [True, True]
    state = await first.dispatch("state", {})
    history = await first.dispatch("history", {})
    assert await _dispatch_error(first, "history", {"game_id": "tests-99"}) == "not_found"

    saved = await first.dispatch("save", {"name": "t-session"})
    assert json.loads((paths.SAVES / "t-session.json").read_text())["settings"]["games"] == 3
    assert Game.from_pgn((paths.SAVES / "t-session.pgn").read_text()).moves == [
        m["uci"] for m in history["moves"]]
    assert await _dispatch_error(first, "save", {"name": "t-session"}) == "exists"
    assert await first.dispatch("save", {"name": "t-session", "overwrite": True}) == saved
    assert await _dispatch_error(first, "save", {"name": "../escape"}) == "invalid_params"
    assert "t-session" in (await first.dispatch("list_saves", {}))["saves"]

    second = new_session()
    assert await second.dispatch("load", {"name": "t-session"}) == {"sid": "tests"}
    loaded = await second.dispatch("status", {})
    assert (loaded["phase"], loaded["loaded_from"]) == ("stopped", "t-session")
    assert loaded["score"] == status["score"]
    assert await second.dispatch("state", {}) == state
    assert await second.dispatch("history", {}) == history

    await second.dispatch("resume", {})
    final = await _settle(second)
    assert final["phase"] == "finished", final
    assert sum(final["score"]) == 3
    replayed = await second.dispatch("history", {"game_id": history["game_id"]})
    assert [m["uci"] for m in replayed["moves"]][: len(history["moves"])] == [
        m["uci"] for m in history["moves"]]
    assert await _dispatch_error(second, "resume") == "busy"


async def test_load_missing_save(new_session):
    session = new_session()
    assert await _dispatch_error(session, "load", {"name": "does-not-exist"}) == "not_found"
