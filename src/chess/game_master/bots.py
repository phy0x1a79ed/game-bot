"""Bot processes: spawn, handshake, frame I/O, and teardown."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from websockets.exceptions import ConnectionClosed

from coms import transport
from coms.protocol import (
    Bye,
    Hello,
    Message,
    Move,
    ProtocolError,
    Ready,
    Resign,
    decode,
    encode,
)
from game_master import paths

log = logging.getLogger(__name__)

READY_TIMEOUT_S = 10.0
EXIT_GRACE_S = 3.0
BOT_NAME_RE = re.compile(r"^[a-z0-9_]+$")

DISCONNECTED = object()


class BotFailed(Exception):
    pass


def bot_exists(name: str) -> bool:
    return bool(BOT_NAME_RE.match(name)) and (paths.SRC / f"ai_{name}" / "__main__.py").is_file()


def bot_command(name: str) -> list[str]:
    if (paths.ENVS / f"chess-{name}.yml").is_file():
        return ["mamba", "run", "--no-capture-output", "-n", f"chess-{name}",
                "python", "-u", "-m", f"ai_{name}"]
    # The game master already runs in the shared `chess` env, so its own
    # interpreter starts the bot without mamba run's startup delay.
    return [sys.executable, "-u", "-m", f"ai_{name}"]


class FrameLog:
    """Appends every Contract A frame to a JSONL file."""

    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self._file = path.open("a", buffering=1)

    def write(self, bot: str, direction: str, text: str | bytes) -> None:
        try:
            frame: Any = json.loads(text)
        except (ValueError, TypeError):
            frame = {"raw": text if isinstance(text, str) else repr(text)}
        record = {"t": round(time.time(), 3), "bot": bot, "dir": direction, "frame": frame}
        self._file.write(json.dumps(record) + "\n")

    def close(self) -> None:
        self._file.close()


class BotProcess:
    """One bot process and its connection. Inbound frames queue up in `inbox`."""

    external = False

    def __init__(
        self,
        slot: int,
        name: str,
        socket_path: Path,
        log_path: Path,
        frames: FrameLog,
        session: str,
        color: str,
        seed: int | None = None,
    ):
        self.slot = slot
        self.name = name
        self.label = f"{slot}:{name}"
        self.socket_path = socket_path
        self.log_path = log_path
        self.frames = frames
        self.session = session
        self.color = color
        self.seed = seed
        self.proc: asyncio.subprocess.Process | None = None
        self.ws = None
        self.ready: Ready | None = None
        self.inbox: asyncio.Queue = asyncio.Queue()
        self.announced_game: str | None = None
        self.alive = False
        self._reader: asyncio.Task | None = None

    @property
    def pid(self) -> int | None:
        return self.proc.pid if self.proc else None

    async def start(self) -> None:
        cmd = bot_command(self.name) + ["--socket", str(self.socket_path), "--name", self.name]
        if self.seed is not None:
            cmd += ["--seed", str(self.seed)]
        env = paths.child_env(PYTHONUNBUFFERED="1")
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        with self.log_path.open("ab") as log_file:
            self.proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdin=subprocess.DEVNULL,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                cwd=paths.REPO_ROOT,
                env=env,
                start_new_session=True,
            )
        await self.handshake(asyncio.ensure_future(self.proc.wait()))

    async def handshake(self, exited: asyncio.Future) -> None:
        """Connect to the bot's socket, send `hello`, and wait for `ready`.

        `exited` resolves when the bot stops, which ends the wait for its socket.
        """
        loop = asyncio.get_running_loop()
        deadline = loop.time() + READY_TIMEOUT_S

        connecting = asyncio.create_task(
            transport.connect(self.socket_path, transport.BOT_URI, timeout=READY_TIMEOUT_S)
        )
        await asyncio.wait({connecting, exited}, return_when=asyncio.FIRST_COMPLETED)
        if not connecting.done():
            connecting.cancel()
            code = self.proc.returncode if self.proc else None
            raise BotFailed(
                f"bot {self.name!r} exited with code {code} before listening; see {self.log_path}"
            )
        exited.cancel()
        try:
            self.ws = connecting.result()
        except ConnectionError as exc:
            raise BotFailed(f"bot {self.name!r} did not open its socket: {exc}") from exc

        await self.send(Hello(session=self.session, color=self.color))
        try:
            text = await asyncio.wait_for(self.ws.recv(), max(deadline - loop.time(), 0.01))
        except TimeoutError as exc:
            raise BotFailed(f"bot {self.name!r} did not send ready in time") from exc
        except ConnectionClosed as exc:
            raise BotFailed(f"bot {self.name!r} closed the connection before ready") from exc
        self.frames.write(self.label, "recv", text)
        try:
            self.ready = decode(text, expect=(Ready,))
        except ProtocolError as exc:
            raise BotFailed(f"bot {self.name!r} sent a bad ready frame: {exc}") from exc
        self.alive = True
        self._reader = asyncio.create_task(self._read())

    async def _read(self) -> None:
        try:
            async for text in self.ws:
                self.frames.write(self.label, "recv", text)
                try:
                    item: Any = decode(text, expect=(Move, Resign))
                except ProtocolError as exc:
                    item = exc
                self.inbox.put_nowait(item)
        except ConnectionClosed:
            pass
        finally:
            self.alive = False
            self.inbox.put_nowait(DISCONNECTED)

    async def next_frame(self, timeout: float) -> Any:
        """The next inbound item: a message, a `ProtocolError`, or `DISCONNECTED`.

        Raises `TimeoutError`.
        """
        if not self.alive and self.inbox.empty():
            return DISCONNECTED
        return await asyncio.wait_for(self.inbox.get(), timeout)

    async def send(self, msg: Message) -> bool:
        if self.ws is None:
            return False
        text = encode(msg)
        self.frames.write(self.label, "send", text)
        try:
            await self.ws.send(text)
            return True
        except ConnectionClosed:
            self.alive = False
            return False

    async def close(self) -> None:
        if self.ws is not None:
            if self.alive:
                await self.send(Bye())
            try:
                await asyncio.wait_for(self.ws.close(), 1.0)
            except (TimeoutError, ConnectionClosed, OSError):
                pass
        if self.proc is not None and self.proc.returncode is None:
            try:
                await asyncio.wait_for(self.proc.wait(), EXIT_GRACE_S)
            except TimeoutError:
                log.warning("bot %s ignored bye; terminating", self.label)
                self._signal(signal.SIGTERM)
                try:
                    await asyncio.wait_for(self.proc.wait(), 2.0)
                except TimeoutError:
                    self._signal(signal.SIGKILL)
                    await self.proc.wait()
        if self._reader is not None:
            self._reader.cancel()
        self.alive = False
        self.socket_path.unlink(missing_ok=True)

    def _signal(self, sig: int) -> None:
        try:
            os.killpg(self.proc.pid, sig)
        except ProcessLookupError:
            pass
