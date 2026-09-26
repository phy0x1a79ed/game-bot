"""The browser viewer: static files, verbs and follows over one WebSocket."""

import asyncio
import itertools
import json
import urllib.request

import pytest
from websockets.asyncio.client import connect

from game_master import sessions
from viewer import server


@pytest.fixture
async def viewer(tmp_path):
    (tmp_path / "index.html").write_text("<p>chess</p>")
    (tmp_path / "app.js").write_text("export {};")
    ws_server, state = await server.start("127.0.0.1", 0, tmp_path)
    port = ws_server.sockets[0].getsockname()[1]
    yield f"127.0.0.1:{port}", state
    ws_server.close()
    await ws_server.wait_closed()
    await asyncio.gather(*(sessions.kill(sid) for sid in sessions.live_sessions()))


class Browser:
    def __init__(self, ws):
        self.ws = ws
        self.ids = itertools.count()
        self.events = []

    async def call(self, verb, **args):
        req_id = next(self.ids)
        await self.ws.send(json.dumps({"id": req_id, "verb": verb, "args": args}))
        async with asyncio.timeout(30):
            while True:
                frame = json.loads(await self.ws.recv())
                if "event" in frame:
                    self.events.append(frame["event"])
                elif frame["id"] == req_id:
                    return frame

    async def next_event(self, kind, timeout=20):
        async with asyncio.timeout(timeout):
            while True:
                for i, event in enumerate(self.events):
                    if event["kind"] == kind:
                        return self.events.pop(i)
                frame = json.loads(await self.ws.recv())
                if "event" in frame:
                    self.events.append(frame["event"])


def _get(url):
    with urllib.request.urlopen(url, timeout=5) as resp:
        return resp.status, resp.headers["Content-Type"], resp.read()


async def test_static_files_fall_back_to_index(viewer):
    addr, _ = viewer
    status, kind, body = await asyncio.to_thread(_get, f"http://{addr}/app.js")
    assert (status, kind, body) == (200, "text/javascript; charset=utf-8", b"export {};")
    for path in ("/", "/?sid=abcde", "/no/such/file", "/../../etc/passwd"):
        assert (await asyncio.to_thread(_get, f"http://{addr}{path}"))[2] == b"<p>chess</p>"


async def test_cross_origin_socket_is_refused(viewer):
    addr, _ = viewer
    with pytest.raises(Exception):
        async with connect(f"ws://{addr}/ws", origin="http://evil.example"):
            pass


async def test_verbs_and_a_follow_that_ends_its_watch(viewer):
    addr, state = viewer
    async with connect(f"ws://{addr}/ws") as ws:
        browser = Browser(ws)
        assert (await browser.call("fly"))["error"]["code"] == "unknown_method"
        assert "naive" in (await browser.call("bots"))["result"]["bots"]

        started = await browser.call("start", white="naive", black="naive", max_plies=6)
        sid = started["result"]["session_id"]
        assert (await browser.next_event("session_started"))["session_id"] == sid

        followed = await browser.call("follow", session_id=sid)
        assert followed["result"]["snapshot"]["status"]["sid"] == sid
        move = await browser.next_event("move")
        assert move["session_id"] == sid and isinstance(move["seq"], int) and move["data"]["uci"]
        status = (await browser.call("status", session_id=sid))["result"]["sessions"][0]
        assert status["watchers"] == 1

        await browser.call("unfollow", session_id=sid)
        assert sid not in state.pumps
        async with asyncio.timeout(5):
            while (await browser.call("status", session_id=sid))["result"]["sessions"][0]["watchers"]:
                await asyncio.sleep(0.05)

        await browser.call("follow", session_id=sid)
        await browser.call("kill", session_id=sid)
        ended = await browser.next_event("session_ended")
        assert ended["session_id"] == sid
    async with asyncio.timeout(5):
        while state.followers or state.pumps:
            await asyncio.sleep(0.05)
