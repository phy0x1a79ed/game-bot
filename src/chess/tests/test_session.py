"""The control API of one session, with real bot processes."""

import asyncio
import json

import pytest

from coms.protocol import RpcError
from game import Game
from game_master import paths, saves
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
            if bot.external:
                continue
            assert bot.proc.returncode is not None, f"bot {bot.label} still running"
            assert not bot.socket_path.exists()


async def test_before_init(new_session):
    session = new_session()
    status = await session.dispatch("status", {})
    assert status["phase"] == "idle"
    assert isinstance((await session.dispatch("list_saves", {}))["saves"], list)
    for method in ["state", "history", "stop", "resume", "save", "step", "set_pace",
                   "submit_move", "resign"]:
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
    (summary,) = [s for s in saves.summaries() if s["name"] == "t-session"]
    assert summary["players"] == ["naive", "naive"]
    assert (summary["played"], summary["games"], summary["finished"]) == (1, 3, False)
    assert summary["current"]["plies"] == len(history["moves"])

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


async def _wait_awaiting(session, ply, timeout=10.0):
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while not ((state := await session.dispatch("state", {}))["awaiting"]
               and state["awaiting"]["ply"] == ply):
        assert loop.time() < deadline, f"no move request at ply {ply}"
        await asyncio.sleep(0.02)
    return state


async def test_external_seat_through_the_control_api(new_session):
    assert await _dispatch_error(new_session(), "start_game",
                                 {"white": "@bad name", "black": "naive"}) == "invalid_params"
    session = new_session()
    await session.dispatch("start_game", {"white": "@human", "black": "naive", "seed": 1})
    status = await session.dispatch("status", {})
    assert [(b["name"], b["external"], b["pid"] is None) for b in status["bots"]] == [
        ("@human", True, True), ("naive", False, False)]

    waiting = (await _wait_awaiting(session, 0))["awaiting"]
    params = {"color": "white", "game_id": waiting["game_id"], "ply": 0, "move": "e2e4"}
    assert await session.dispatch("submit_move", params) == {"accepted": True, "san": "e4"}
    state = await _wait_awaiting(session, 2)
    assert state["awaiting"]["color"] == "white"
    assert await _dispatch_error(session, "submit_move", {**params, "ply": 1}) == "stale"
    assert await _dispatch_error(session, "submit_move", {**params, "color": "red"}) \
        == "invalid_params"
    assert await _dispatch_error(session, "resign", {"color": "black"}) == "invalid_params"
    assert await session.dispatch("resign", {"color": "white"}) == {
        "result": "0-1", "reason": "resignation"}
    assert (await _settle(session))["phase"] == "finished"


async def test_labels_are_echoed_saved_and_merged_on_load(new_session):
    assert await _dispatch_error(new_session(), "start_game", {
        "white": "naive", "black": "naive", "labels": {"owner": 3}}) == "invalid_params"
    labels = {"owner": "rlm-chess", "mode": "pvb"}
    first = new_session()
    await first.dispatch("start_game", {"white": "@human", "black": "naive", "labels": labels})
    assert (await first.dispatch("status", {}))["labels"] == labels
    await _wait_awaiting(first, 0)
    await first.dispatch("save", {"name": "t-labels"})
    assert saves.read("t-labels")["labels"] == labels
    assert await _dispatch_error(first, "save", {"name": "autosave-mine"}) == "invalid_params"

    second = new_session()
    await second.dispatch("load", {"name": "t-labels", "labels": {"mode": "resumed"}})
    assert (await second.dispatch("status", {}))["labels"] == {"owner": "rlm-chess", "mode": "resumed"}


async def test_idle_session_autosaves_and_shuts_down_unless_watched(new_session):
    session = new_session()
    await session.dispatch("start_game", {"white": "@human", "black": "naive",
                                          "idle_timeout_s": 0.4, "labels": {"owner": "t"}})
    async with asyncio.timeout(5):
        while not session.match.awaiting:
            await asyncio.sleep(0.01)
    watcher, _ = session.bus.subscribe()
    await asyncio.sleep(0.8)
    assert not session.shutdown_requested.is_set()
    session.bus.unsubscribe(watcher)
    async with asyncio.timeout(3):
        await session.shutdown_requested.wait()
    data = saves.read("autosave-tests")
    assert data["labels"] == {"owner": "t"} and len(data["games"]) == 1
    assert "autosave-tests" in [s["name"] for s in saves.summaries()]


async def test_finished_session_lingers_then_shuts_down_and_leaves_a_replayable_record(new_session):
    session = new_session()
    await session.dispatch("start_game", {"white": "naive", "black": "naive", "max_plies": 6,
                                          "seed": 2, "finished_linger_s": 0.3})
    async with asyncio.timeout(15):
        await session.shutdown_requested.wait()
    assert session.match.phase == "finished"
    final_fen = session.match.state()["fen"]
    history = await session.dispatch("history", {"fens": True})
    assert history["moves"][-1]["fen"] == final_fen

    replay = saves.replay(json.loads((session.records / "record.json").read_text()))
    assert replay["game_ids"] == ["tests-1"]
    assert [m["fen"] for m in replay["moves"]] == [m["fen"] for m in history["moves"]]
    with pytest.raises(LookupError):
        saves.replay({"games": []})


async def test_load_missing_save(new_session):
    session = new_session()
    assert await _dispatch_error(session, "load", {"name": "does-not-exist"}) == "not_found"
