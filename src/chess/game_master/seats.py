"""External seats: a player who moves through control calls instead of a bot process."""

from __future__ import annotations

import asyncio
import re
from typing import Any

from coms.protocol import Message, Move, encode
from game_master.bots import FrameLog

EXTERNAL_NAME_RE = re.compile(r"^@[a-z0-9_]+$")


def is_external(name: str) -> bool:
    return name.startswith("@")


class ExternalSeat:
    """Takes a `BotProcess` place in a match. Moves arrive through `put`, not a socket."""

    external = True

    def __init__(self, slot: int, name: str, frames: FrameLog):
        self.slot = slot
        self.name = name
        self.label = f"{slot}:{name}"
        self.frames = frames
        self.inbox: asyncio.Queue = asyncio.Queue()
        self.announced_game: str | None = None
        self.alive = True
        self.pid = None

    async def start(self) -> None:
        pass

    async def send(self, msg: Message) -> bool:
        self.frames.write(self.label, "send", encode(msg))
        return True

    def put(self, move: Move) -> None:
        self.frames.write(self.label, "recv", encode(move))
        self.inbox.put_nowait(move)

    async def next_frame(self, timeout: float | None) -> Any:
        return await asyncio.wait_for(self.inbox.get(), timeout)

    async def close(self) -> None:
        self.alive = False
