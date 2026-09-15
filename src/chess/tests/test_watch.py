"""The event stream, pacing and single steps."""

import asyncio

import pytest

from coms import rpc
from coms.protocol import RpcError
from game import STARTING_FEN
from game_master.daemon import Session
from game_master.events import EventBus
from helpers import ScriptedBot, running_match, settle, short_dir


class Recorder:
    def __init__(self):
        self.events = []

    def __call__(self, event, data):
        self.events.append((asyncio.get_running_loop().time(), event, data))

    def kinds(self):
        return [event for _, event, _ in self.events]

    def of(self, kind):
        return [(t, data) for t, event, data in self.events if event == kind]


def test_bus_replays_buffered_events_and_reports_gaps():
    bus = EventBus(buffer_size=3)
    assert bus.subscribe(0)[1] == []
    for n in range(5):
        bus.emit("note", {"n": n})
    assert [f["seq"] for f in bus.subscribe(2)[1]] == [3, 4, 5]
    assert bus.subscribe(5)[1] == []
    for since in (1, 9, None):
        assert bus.subscribe(since)[1] is None
    assert bus.watchers == 6


async def test_a_watcher_that_falls_behind_gets_resync():
    bus = EventBus(queue_limit=2)
    watcher, _ = bus.subscribe(0)
    for n in range(3):
        bus.emit("note", {"n": n})
    assert (await anext(bus.frames(watcher)))["event"] == "resync"
    assert bus.watchers == 0


async def test_match_events_in_order():
    events = Recorder()
    async with running_match(ScriptedBot("w"), ScriptedBot("b"), emit=events, max_plies=2) as match:
        match.start()
        assert await settle(match) == "finished"
    assert events.kinds() == ["phase", "game_start", "turn", "move", "turn", "move",
                              "game_over", "phase"]
    (_, first), _ = events.of("move")
    assert (first["ply"], first["side"]) == (0, "white")
    assert first["san"] and first["fen"] != STARTING_FEN
    assert events.of("turn")[0][1]["legal_moves"]
    assert events.of("game_over")[0][1]["reason"] == "max_plies"
    assert events.of("phase")[-1][1]["phase"] == "finished"


async def test_pace_spaces_bot_plies():
    events = Recorder()
    async with running_match(ScriptedBot("w"), ScriptedBot("b"), emit=events, max_plies=3,
                             min_ply_s=0.15) as match:
        match.start()
        assert await settle(match) == "finished"
    times = [t for t, _ in events.of("move")]
    assert len(times) == 3
    assert all(later - earlier >= 0.14 for earlier, later in zip(times, times[1:]))


async def test_set_pace_and_stop_cut_a_hold_short():
    events = Recorder()
    async with running_match(ScriptedBot("w"), ScriptedBot("b"), emit=events, max_plies=2,
                             min_ply_s=30) as match:
        match.start()
        await asyncio.sleep(0.1)
        assert match.current.game.moves == []
        assert match.set_pace(0) == {"min_ply_s": 0.0}
        assert await settle(match, timeout=2) == "finished"
        assert events.kinds().count("pace") == 1

    async with running_match(ScriptedBot("w"), ScriptedBot("b"), max_plies=10,
                             min_ply_s=30) as match:
        match.start()
        await asyncio.sleep(0.1)
        await asyncio.wait_for(match.stop(), 2)
        assert (match.phase, len(match.current.game.moves)) == ("stopped", 1)


async def test_step_plays_one_ply_from_stopped():
    async with running_match(ScriptedBot("w"), ScriptedBot("b"), max_plies=10,
                             min_ply_s=30) as match:
        await asyncio.wait_for(match.step(), 2)
        assert (match.phase, len(match.current.game.moves)) == ("stopped", 1)
        await asyncio.wait_for(match.step(), 2)
        assert len(match.current.game.moves) == 2
        match.start()
        with pytest.raises(RpcError) as info:
            await match.step()
        assert info.value.code == "busy"

    async with running_match("@human", ScriptedBot("b")) as match:
        with pytest.raises(RpcError) as info:
            await match.step()
        assert info.value.code == "busy"


async def test_watch_over_the_control_socket():
    runtime = short_dir()
    session = Session("tests", runtime, runtime / "records")
    sock = runtime / "gm.sock"
    server = await rpc.serve_control(sock, session.dispatch)
    try:
        await session.dispatch("start_game", {"white": "naive", "black": "naive", "seed": 3,
                                              "max_plies": 10, "min_ply_s": 0.05})
        seqs = []
        async with asyncio.timeout(20):
            async with rpc.stream(sock, "watch") as (result, frames):
                assert result["events"] is None
                assert result["snapshot"]["status"]["sid"] == "tests"
                seqs.append(result["seq"])
                assert session.bus.watchers == 1
                async for frame in frames:
                    seqs.append(frame["seq"])
                    if frame["event"] == "phase" and frame["data"]["phase"] == "finished":
                        break
        assert seqs == list(range(seqs[0], seqs[0] + len(seqs)))

        mid = seqs[len(seqs) // 2]
        async with rpc.stream(sock, "watch", {"since_seq": mid}) as (again, _):
            assert again["snapshot"] is None
            assert [f["seq"] for f in again["events"]] == list(range(mid + 1, session.bus.seq + 1))

        async with asyncio.timeout(2):
            while session.bus.watchers:
                await asyncio.sleep(0.02)
    finally:
        server.close()
        await session.close()
        await server.wait_closed()
