"""Numbered session events: a replay buffer plus a bounded queue per watcher."""

from __future__ import annotations

import asyncio
from collections import deque
from typing import Any, AsyncIterator

BUFFER_SIZE = 2000
QUEUE_LIMIT = 1000


class Watcher:
    def __init__(self, limit: int):
        self.pending: deque[dict[str, Any]] = deque()
        self.limit = limit
        self.overflowed = False
        self.ready = asyncio.Event()

    def push(self, frame: dict[str, Any]) -> None:
        # Once one frame is dropped, later frames would hide the gap.
        if self.overflowed or len(self.pending) >= self.limit:
            self.overflowed = True
        else:
            self.pending.append(frame)
        self.ready.set()


class EventBus:
    def __init__(self, buffer_size: int = BUFFER_SIZE, queue_limit: int = QUEUE_LIMIT):
        self.seq = 0
        self._buffer: deque[dict[str, Any]] = deque(maxlen=buffer_size)
        self._watchers: set[Watcher] = set()
        self._limit = queue_limit

    @property
    def watchers(self) -> int:
        return len(self._watchers)

    def emit(self, event: str, data: dict[str, Any]) -> None:
        self.seq += 1
        frame = {"event": event, "seq": self.seq, "data": data}
        self._buffer.append(frame)
        for watcher in self._watchers:
            watcher.push(frame)

    def subscribe(self, since_seq: int | None = None) -> tuple[Watcher, list[dict[str, Any]] | None]:
        """Register a watcher. Also returns the events after `since_seq`, or None if any is gone."""
        watcher = Watcher(self._limit)
        self._watchers.add(watcher)
        if since_seq is None or since_seq > self.seq:
            return watcher, None
        oldest = self._buffer[0]["seq"] if self._buffer else self.seq + 1
        if since_seq + 1 < oldest:
            return watcher, None
        return watcher, [f for f in self._buffer if f["seq"] > since_seq]

    def unsubscribe(self, watcher: Watcher) -> None:
        self._watchers.discard(watcher)

    async def frames(self, watcher: Watcher) -> AsyncIterator[dict[str, Any]]:
        """The watcher's frames in order. Ends with a `resync` frame if the watcher fell behind."""
        while True:
            await watcher.ready.wait()
            watcher.ready.clear()
            while watcher.pending and not watcher.overflowed:
                yield watcher.pending.popleft()
            if watcher.overflowed:
                self.unsubscribe(watcher)
                yield {"event": "resync", "seq": self.seq, "data": {}}
                return
