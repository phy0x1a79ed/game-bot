"""WebSocket over Unix domain sockets."""

from __future__ import annotations

import asyncio
import os
from pathlib import Path
from typing import Awaitable, Callable

from websockets.asyncio.client import ClientConnection, unix_connect
from websockets.asyncio.server import Server, ServerConnection, unix_serve

BOT_URI = "ws://localhost/bot"
CONTROL_URI = "ws://localhost/control"

# sockaddr_un.sun_path is 108 bytes including the terminating NUL.
MAX_SOCKET_PATH = 107
MAX_FRAME_BYTES = 8 * 1024 * 1024

# Local sockets report a dead peer on their own. Keepalive pings would only
# add a way for a bot that blocks its event loop to be dropped.
_COMMON = {"ping_interval": None, "max_size": MAX_FRAME_BYTES, "compression": None}


def check_socket_path(path: str | os.PathLike) -> Path:
    path = Path(path)
    size = len(os.fsencode(path))
    if size > MAX_SOCKET_PATH:
        raise ValueError(
            f"socket path is {size} bytes, over the {MAX_SOCKET_PATH}-byte limit: {path}"
        )
    return path


async def serve(
    path: str | os.PathLike, handler: Callable[[ServerConnection], Awaitable[None]]
) -> Server:
    path = check_socket_path(path)
    if path.is_socket():
        path.unlink()
    server = await unix_serve(handler, str(path), **_COMMON)
    os.chmod(path, 0o600)
    return server


async def connect(
    path: str | os.PathLike, uri: str, timeout: float = 10.0, retry: bool = True
) -> ClientConnection:
    """Connect to a socket, retrying until it exists and accepts or `timeout` passes."""
    path = check_socket_path(path)
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while True:
        remaining = deadline - loop.time()
        try:
            return await asyncio.wait_for(
                unix_connect(str(path), uri, open_timeout=None, **_COMMON),
                max(remaining, 0.01),
            )
        except (FileNotFoundError, ConnectionRefusedError) as exc:
            if not retry or loop.time() + 0.05 >= deadline:
                raise ConnectionError(f"cannot connect to {path}: {exc}") from exc
            await asyncio.sleep(0.05)
        except (TimeoutError, asyncio.TimeoutError) as exc:
            raise ConnectionError(f"timed out connecting to {path}") from exc
