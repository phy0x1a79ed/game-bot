"""Scripted bots and an in-process match harness for game master tests."""

from __future__ import annotations

import asyncio
import contextlib
import itertools
import shutil
from pathlib import Path
from typing import Any, Awaitable, Callable

from websockets.exceptions import ConnectionClosed

from coms import transport
from coms.protocol import (
    TO_BOT,
    Bye,
    Hello,
    Move,
    MoveRejected,
    MoveRequest,
    Ready,
    Resign,
    decode,
    encode,
)
from game_master import paths
from game_master.bots import BotProcess, FrameLog
from game_master.match import Match, Settings
from game_master.seats import ExternalSeat

Action = Callable[[Any, MoveRequest | MoveRejected], Awaitable[None]]

_dirs = itertools.count()


def short_dir() -> Path:
    path = paths.RUNTIME / f"t{next(_dirs)}"
    path.mkdir(parents=True)
    return path


# --- actions: how a scripted bot answers one move_request or move_rejected ---


async def legal(ws, msg) -> None:
    await ws.send(encode(Move(msg.game_id, msg.ply, msg.legal_moves[0])))


def send(move: Any) -> Action:
    async def action(ws, msg) -> None:
        await ws.send(encode(Move(msg.game_id, msg.ply, move)))
    return action


async def stale_then_legal(ws, msg) -> None:
    await ws.send(encode(Move("old-game", msg.ply, "e2e5")))
    await ws.send(encode(Move(msg.game_id, msg.ply + 7, "e2e5")))
    await legal(ws, msg)


async def silent(ws, msg) -> None:
    pass


async def disconnect(ws, msg) -> None:
    await ws.close()


async def resign(ws, msg) -> None:
    await ws.send(encode(Resign(msg.game_id, msg.ply)))


def raw(text: str) -> Action:
    async def action(ws, msg) -> None:
        await ws.send(text)
    return action


class ScriptedBot:
    """A bot server that answers each move prompt with its next action, then plays `legal`."""

    def __init__(self, name: str, *actions: Action):
        self.name = name
        self.actions = list(actions)
        self.received: list[Any] = []

    def prompts(self, kind: type) -> list[Any]:
        return [m for m in self.received if isinstance(m, kind)]

    async def serve(self, path: Path) -> None:
        done = asyncio.Event()

        async def handler(ws) -> None:
            try:
                async for text in ws:
                    msg = decode(text, expect=TO_BOT)
                    self.received.append(msg)
                    if isinstance(msg, Hello):
                        await ws.send(encode(Ready(name=self.name)))
                    elif isinstance(msg, (MoveRequest, MoveRejected)):
                        action = self.actions.pop(0) if self.actions else legal
                        await action(ws, msg)
                    elif isinstance(msg, Bye):
                        await ws.close()
            except ConnectionClosed:
                pass
            finally:
                done.set()

        server = await transport.serve(path, handler)
        try:
            await done.wait()
        finally:
            server.close()
            await server.wait_closed()


@contextlib.asynccontextmanager
async def running_match(white, black, emit=None, **settings: Any):
    """Yield a `Match` between two in-process bots (`ScriptedBot` or `coms.bot.Bot`).

    A string such as `"@human"` takes that slot as an external seat.
    """
    runtime = short_dir()
    records = runtime / "records"
    frames = FrameLog(records / "frames.jsonl")
    bots: list[BotProcess] = []
    servers: list[asyncio.Task] = []
    try:
        for slot, bot in enumerate((white, black)):
            if isinstance(bot, str):
                bots.append(ExternalSeat(slot, bot, frames))
                continue
            color = "white" if slot == 0 else "black"
            path = runtime / f"{color}.sock"
            servers.append(asyncio.create_task(bot.serve(path)))
            process = BotProcess(slot, bot.name, path, records / f"bot{slot}.log", frames,
                                 "tests", color)
            await process.handshake(asyncio.shield(servers[-1]))
            bots.append(process)
        params = {"white": getattr(white, "name", white), "black": getattr(black, "name", black),
                  **settings}
        match = Match("tests", Settings.from_params(params), bots, records, emit)
        yield match
        await match.shutdown()
        await asyncio.wait_for(asyncio.gather(*servers), 5)
    finally:
        for task in servers:
            task.cancel()
        await asyncio.gather(*servers, return_exceptions=True)
        frames.close()
        shutil.rmtree(runtime, ignore_errors=True)


async def wait_awaiting(match: Match, ply: int, timeout: float = 5.0) -> dict[str, Any]:
    """Wait until the match has an open move request at `ply` and return it."""
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while not (match.awaiting and match.awaiting["ply"] == ply):
        assert loop.time() < deadline, f"no move request at ply {ply}"
        await asyncio.sleep(0.01)
    return match.awaiting


async def settle(match: Match, timeout: float = 30.0) -> str:
    """Wait until play is no longer running and return the phase."""
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while match.phase == "running":
        assert loop.time() < deadline, "match did not settle in time"
        await asyncio.sleep(0.02)
    return match.phase
