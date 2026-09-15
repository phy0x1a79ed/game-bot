"""One-request-per-connection control calls (Contract B)."""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import os
import secrets
from dataclasses import dataclass
from typing import Any, AsyncIterator, Awaitable, Callable

from websockets.asyncio.server import Server, ServerConnection
from websockets.exceptions import ConnectionClosed

from coms import transport
from coms.protocol import (
    CONTROL_METHODS,
    ProtocolError,
    Request,
    Response,
    RpcError,
    decode_request,
    decode_response,
    encode_request,
    encode_response,
)

log = logging.getLogger(__name__)

Dispatch = Callable[[str, dict[str, Any]], Awaitable[Any]]


@dataclass
class Stream:
    """A dispatch result that keeps the connection open for `frames` after the response."""

    result: Any
    frames: AsyncIterator[dict[str, Any]]
    close: Callable[[], None]


async def call(
    path: str | os.PathLike,
    method: str,
    params: dict[str, Any] | None = None,
    timeout: float = 30.0,
    connect_timeout: float = 2.0,
) -> Any:
    """Send one request and return its result. Raises `RpcError` on an error response."""
    req = Request(id=secrets.token_hex(4), method=method, params=params or {})
    ws = await transport.connect(
        path, transport.CONTROL_URI, timeout=connect_timeout, retry=False
    )
    async with ws:
        await ws.send(encode_request(req))
        try:
            text = await asyncio.wait_for(ws.recv(), timeout)
        except ConnectionClosed as exc:
            raise ConnectionError(f"session closed the connection during {method}") from exc
    return _result(req, text)


@contextlib.asynccontextmanager
async def stream(
    path: str | os.PathLike,
    method: str,
    params: dict[str, Any] | None = None,
    timeout: float = 30.0,
    connect_timeout: float = 2.0,
):
    """Send a streaming request. Yields `(result, frames)`. `frames` ends when the server closes."""
    req = Request(id=secrets.token_hex(4), method=method, params=params or {})
    ws = await transport.connect(
        path, transport.CONTROL_URI, timeout=connect_timeout, retry=False
    )
    try:
        await ws.send(encode_request(req))
        try:
            text = await asyncio.wait_for(ws.recv(), timeout)
        except ConnectionClosed as exc:
            raise ConnectionError(f"session closed the connection during {method}") from exc
        yield _result(req, text), _frames(ws)
    finally:
        await ws.close()


async def _frames(ws) -> AsyncIterator[dict[str, Any]]:
    try:
        async for text in ws:
            yield json.loads(text)
    except ConnectionClosed:
        return


def _result(req: Request, text: str | bytes) -> Any:
    resp = decode_response(text)
    if resp.id != req.id:
        raise ProtocolError(f"response id {resp.id!r} does not match request {req.id!r}")
    if not resp.ok:
        raise RpcError(resp.error["code"], resp.error.get("message", ""))
    return resp.result


async def serve_control(path: str | os.PathLike, dispatch: Dispatch) -> Server:
    async def handler(ws: ServerConnection) -> None:
        try:
            text = await ws.recv()
        except ConnectionClosed:
            return
        try:
            req = decode_request(text)
        except ProtocolError as exc:
            await _send(ws, Response("?", False, error=_error("invalid_params", str(exc))))
            return
        if req.method not in CONTROL_METHODS:
            resp = Response(req.id, False, error=_error("unknown_method", req.method))
        else:
            try:
                result = await dispatch(req.method, req.params)
                if isinstance(result, Stream):
                    await _stream(ws, req.id, result)
                    return
                resp = Response(req.id, True, result=result)
            except RpcError as exc:
                resp = Response(req.id, False, error=_error(exc.code, exc.message))
            except Exception as exc:  # the control server must keep answering
                log.exception("control method %s failed", req.method)
                resp = Response(req.id, False, error=_error("internal", repr(exc)))
        await _send(ws, resp)

    return await transport.serve(path, handler)


async def _stream(ws: ServerConnection, req_id: str, stream: Stream) -> None:
    async def pump() -> None:
        async for frame in stream.frames:
            await ws.send(json.dumps(frame))

    try:
        await ws.send(encode_response(Response(req_id, True, result=stream.result)))
        pumping = asyncio.create_task(pump())
        closed = asyncio.create_task(ws.wait_closed())
        await asyncio.wait({pumping, closed}, return_when=asyncio.FIRST_COMPLETED)
        for task in (pumping, closed):
            task.cancel()
        for outcome in await asyncio.gather(pumping, closed, return_exceptions=True):
            if isinstance(outcome, Exception) and not isinstance(outcome, ConnectionClosed):
                log.error("stream failed: %r", outcome)
    except ConnectionClosed:
        pass
    finally:
        stream.close()
        await ws.close()


def _error(code: str, message: str) -> dict[str, str]:
    return {"code": code, "message": message}


async def _send(ws: ServerConnection, resp: Response) -> None:
    try:
        await ws.send(encode_response(resp))
        await ws.close()
    except ConnectionClosed:
        pass
