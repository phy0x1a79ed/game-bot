"""The browser viewer: static page files plus one WebSocket for verbs and live events.

Contract C in `coms/PROTOCOL.md` defines the frames. The viewer holds an arena
`watch` on a session only while at least one browser follows it, so an unwatched
session still reaches its idle and linger timeouts.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import mimetypes
from http import HTTPStatus
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

from websockets.asyncio.server import Server, ServerConnection, serve
from websockets.datastructures import Headers
from websockets.exceptions import ConnectionClosed
from websockets.http11 import Request, Response

from coms.protocol import RpcError
from game_master import paths, sessions, verbs

log = logging.getLogger(__name__)

DIST = paths.SRC / "web" / "dist"
WS_PATH = "/ws"
MAX_FRAME_BYTES = 1024 * 1024
OUTBOX_LIMIT = 5000

# Events that change what the lobby lists. They go to every browser, not only followers.
LOBBY_KINDS = ("session_started", "session_ended", "saved")

mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("image/svg+xml", ".svg")


class Viewer:
    def __init__(self, dist: Path = DIST) -> None:
        self.dist = dist.resolve()
        self.clients: dict[ServerConnection, asyncio.Queue] = {}
        self.followers: dict[str, set[ServerConnection]] = {}
        self.pumps: dict[str, asyncio.Task] = {}

    # --- HTTP ---

    def process_request(self, connection: ServerConnection, request: Request) -> Response | None:
        path = urlsplit(request.path).path
        if path == WS_PATH:
            origin = request.headers.get("Origin")
            if origin and urlsplit(origin).netloc != request.headers.get("Host"):
                return connection.respond(HTTPStatus.FORBIDDEN, "cross-origin request refused\n")
            return None
        return self._static(path)

    def _static(self, path: str) -> Response:
        index = self.dist / "index.html"
        if not index.is_file():
            return _response(HTTPStatus.SERVICE_UNAVAILABLE, b"The page is not built. Run: dev/chess.sh web-build\n",
                             "text/plain; charset=utf-8")
        file = (self.dist / path.lstrip("/")).resolve()
        if not (file.is_relative_to(self.dist) and file.is_file()):
            file = index
        kind = mimetypes.guess_type(file.name)[0] or "application/octet-stream"
        if kind.startswith("text/") or kind == "application/json":
            kind += "; charset=utf-8"
        return _response(HTTPStatus.OK, file.read_bytes(), kind,
                         cache="no-cache" if file == index else "max-age=3600")

    # --- WebSocket ---

    async def handler(self, ws: ServerConnection) -> None:
        outbox: asyncio.Queue = asyncio.Queue()
        self.clients[ws] = outbox
        tasks: set[asyncio.Task] = {asyncio.create_task(_write(ws, outbox))}
        try:
            async for text in ws:
                task = asyncio.create_task(self._answer(ws, text))
                tasks.add(task)
                task.add_done_callback(tasks.discard)
        except ConnectionClosed:
            pass
        finally:
            del self.clients[ws]
            for task in tasks:
                task.cancel()
            for sid in [sid for sid, conns in self.followers.items() if ws in conns]:
                self._unfollow(sid, ws)

    async def _answer(self, ws: ServerConnection, text: str | bytes) -> None:
        req_id = None
        try:
            req = json.loads(text)
            req_id = req.get("id")
            verb, args = str(req.get("verb", "")), req.get("args") or {}
            if not isinstance(args, dict):
                raise verbs.VerbError("invalid_params", "args must be an object")
            reply = {"id": req_id, "ok": True, "result": await self._dispatch(ws, verb, args)}
        except verbs.VerbError as exc:
            reply = {"id": req_id, "ok": False, "error": {"code": exc.code, "message": exc.message}}
        except (ValueError, AttributeError) as exc:
            reply = {"id": req_id, "ok": False,
                     "error": {"code": "invalid_params", "message": f"bad request: {exc}"}}
        except Exception as exc:  # one failed verb must not drop the socket
            log.exception("verb failed")
            reply = {"id": req_id, "ok": False, "error": {"code": "internal", "message": repr(exc)}}
        self._post(ws, reply)

    async def _dispatch(self, ws: ServerConnection, verb: str, args: dict[str, Any]) -> Any:
        if verb == "follow":
            sid = verbs.session_id(args)
            self._follow(sid, ws)
            try:
                return await verbs.snapshot(args)
            except verbs.VerbError:
                self._unfollow(sid, ws)
                raise
        if verb == "unfollow":
            self._unfollow(verbs.session_id(args), ws)
            return {"following": False}
        result = await verbs.dispatch(verb, args)
        if verb in ("start", "rematch"):
            self._lobby_event(result["session_id"], "session_started", {"mode": result["mode"]})
        elif verb == "kill":
            self._lobby_event(result["session_id"], "session_ended")
        elif verb == "save":
            self._lobby_event(verbs.session_id(args), "saved", {"name": args.get("name")})
        return result

    # --- follows ---

    def _follow(self, sid: str, ws: ServerConnection) -> None:
        self.followers.setdefault(sid, set()).add(ws)
        if sid not in self.pumps:
            self.pumps[sid] = asyncio.create_task(self._pump(sid))

    def _unfollow(self, sid: str, ws: ServerConnection) -> None:
        conns = self.followers.get(sid)
        if conns is None:
            return
        conns.discard(ws)
        if not conns:
            del self.followers[sid]
            pump = self.pumps.pop(sid, None)
            if pump is not None:
                pump.cancel()

    async def _pump(self, sid: str) -> None:
        """Relay one arena watch to the followers of `sid` until the session ends."""
        since: int | None = None
        try:
            while True:
                async with sessions.watch(sid, since) as (result, frames):
                    if since is not None and result["events"] is None:
                        self._fan_out(sid, "resync", result["seq"])
                    for frame in result["events"] or []:
                        self._fan_out(sid, frame["event"], frame["seq"], frame.get("data"))
                    since = result["seq"]
                    async for frame in frames:
                        self._fan_out(sid, frame["event"], frame["seq"], frame.get("data"))
                        # The arena drops a watcher that fell behind. Re-watch for a snapshot.
                        since = None if frame["event"] == "resync" else frame["seq"]
                        if since is None:
                            break
        except (OSError, RpcError):
            pass
        except asyncio.CancelledError:
            raise
        except Exception:
            log.exception("watch of session %s failed", sid)
        self.pumps.pop(sid, None)
        self.followers.pop(sid, None)
        self._lobby_event(sid, "session_ended")

    def _fan_out(self, sid: str, kind: str, seq: int | None = None, data: Any = None) -> None:
        frame = {"event": {"session_id": sid, "kind": kind, "seq": seq, "data": data or {}}}
        for ws in list(self.followers.get(sid, ())):
            self._post(ws, frame)

    def _lobby_event(self, sid: str, kind: str, data: Any = None) -> None:
        frame = {"event": {"session_id": sid, "kind": kind, "seq": None, "data": data or {}}}
        for ws in list(self.clients):
            self._post(ws, frame)

    def _post(self, ws: ServerConnection, frame: dict[str, Any]) -> None:
        """Queue a frame for one browser. A browser that stops reading is dropped."""
        outbox = self.clients.get(ws)
        if outbox is None:
            return
        if outbox.qsize() >= OUTBOX_LIMIT:
            outbox.put_nowait(None)
            return
        outbox.put_nowait(frame)


def _response(status: HTTPStatus, body: bytes, content_type: str, cache: str = "no-cache") -> Response:
    headers = Headers({"Content-Type": content_type, "Content-Length": str(len(body)),
                       "Cache-Control": cache, "X-Content-Type-Options": "nosniff"})
    return Response(status.value, status.phrase, headers, body)


async def _write(ws: ServerConnection, outbox: asyncio.Queue) -> None:
    with contextlib.suppress(ConnectionClosed):
        while (frame := await outbox.get()) is not None:
            await ws.send(json.dumps(frame))
        await ws.close(1008, "too far behind")


async def start(host: str = "127.0.0.1", port: int = 8765, dist: Path = DIST) -> tuple[Server, Viewer]:
    viewer = Viewer(dist)
    server = await serve(viewer.handler, host, port, process_request=viewer.process_request,
                         max_size=MAX_FRAME_BYTES, compression=None)
    return server, viewer
