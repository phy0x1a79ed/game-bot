"""One-request-per-connection control calls (Contract B)."""

from __future__ import annotations

import asyncio
import logging
import os
import secrets
from typing import Any, Awaitable, Callable

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
                resp = Response(req.id, True, result=await dispatch(req.method, req.params))
            except RpcError as exc:
                resp = Response(req.id, False, error=_error(exc.code, exc.message))
            except Exception as exc:  # the control server must keep answering
                log.exception("control method %s failed", req.method)
                resp = Response(req.id, False, error=_error("internal", repr(exc)))
        await _send(ws, resp)

    return await transport.serve(path, handler)


def _error(code: str, message: str) -> dict[str, str]:
    return {"code": code, "message": message}


async def _send(ws: ServerConnection, resp: Response) -> None:
    try:
        await ws.send(encode_response(resp))
        await ws.close()
    except ConnectionClosed:
        pass
