"""Base class for arena bots (the bot side of Contract A)."""

from __future__ import annotations

import argparse
import asyncio
import dataclasses
import inspect
import logging
import random
import sys
from pathlib import Path
from typing import Any

from websockets.asyncio.server import ServerConnection
from websockets.exceptions import ConnectionClosed

from coms import transport
from coms.protocol import (
    TO_BOT,
    Bye,
    GameOver,
    GameStart,
    Hello,
    Move,
    MoveRejected,
    MoveRequest,
    ProtocolError,
    Ready,
    Resign,
    decode,
    encode,
)

log = logging.getLogger("bot")


class Bot:
    """Subclass and override `choose_move`. Return a UCI string, or None to resign.

    Hooks may be plain or async functions. Plain functions run in a worker
    thread, so a long search never blocks the connection.
    """

    name = "bot"
    version = "0"

    def __init__(self, name: str | None = None, seed: int | None = None):
        if name:
            self.name = name
        self.rng = random.Random(seed)
        self.color: str | None = None
        self.game: GameStart | None = None
        self._request: MoveRequest | None = None
        self._thinking: asyncio.Task | None = None

    # --- hooks for bot authors ---

    def choose_move(self, request: MoveRequest) -> str | None:
        raise NotImplementedError

    def on_game_start(self, start: GameStart) -> None:
        pass

    def on_move_rejected(self, rejected: MoveRejected, request: MoveRequest) -> str | None:
        """Called after an invalid move. By default asks `choose_move` again,
        with the legal moves and remaining time the game master offered."""
        return self.choose_move(request)

    def on_game_over(self, over: GameOver) -> None:
        pass

    # --- runtime ---

    async def _run_hook(self, fn, *args) -> Any:
        if inspect.iscoroutinefunction(fn):
            return await fn(*args)
        result = await asyncio.to_thread(fn, *args)
        if inspect.isawaitable(result):
            result = await result
        return result

    def _cancel_thinking(self) -> None:
        if self._thinking and not self._thinking.done():
            self._thinking.cancel()
        self._thinking = None

    def _think(self, ws: ServerConnection, request: MoveRequest, fn, *args) -> None:
        self._cancel_thinking()
        self._request = request
        self._thinking = asyncio.create_task(self._answer(ws, request, fn, *args))

    async def _answer(self, ws: ServerConnection, request: MoveRequest, fn, *args) -> None:
        try:
            move = await self._run_hook(fn, *args)
        except asyncio.CancelledError:
            raise
        except Exception:
            log.exception("%s failed; resigning", getattr(fn, "__name__", fn))
            move = None
        if self._request is not request:
            return  # superseded by a newer request or the end of the game
        if move is None:
            reply = Resign(game_id=request.game_id, ply=request.ply)
        else:
            reply = Move(game_id=request.game_id, ply=request.ply, move=move)
        try:
            await ws.send(encode(reply))
        except ConnectionClosed:
            pass

    async def _handle(self, ws: ServerConnection) -> None:
        async for text in ws:
            try:
                msg = decode(text, expect=TO_BOT)
            except ProtocolError as exc:
                log.error("dropping bad frame from game master: %s", exc)
                continue
            if isinstance(msg, Hello):
                self.color = msg.color
                await ws.send(encode(Ready(name=self.name, version=self.version)))
            elif isinstance(msg, GameStart):
                self._cancel_thinking()
                self.game = msg
                self.color = msg.color
                await self._run_hook(self.on_game_start, msg)
            elif isinstance(msg, MoveRequest):
                self._think(ws, msg, self.choose_move, msg)
            elif isinstance(msg, MoveRejected):
                base = self._request
                if base is None or (base.game_id, base.ply) != (msg.game_id, msg.ply):
                    continue
                retry = dataclasses.replace(
                    base, legal_moves=msg.legal_moves, deadline_s=msg.remaining_s
                )
                self._think(ws, retry, self.on_move_rejected, msg, retry)
            elif isinstance(msg, GameOver):
                self._cancel_thinking()
                self._request = None
                await self._run_hook(self.on_game_over, msg)
            elif isinstance(msg, Bye):
                self._cancel_thinking()
                await ws.close()
                return

    async def serve(self, socket_path: str, connect_timeout: float = 30.0) -> None:
        """Serve one game master connection, then return.

        Returns early when no game master connects within `connect_timeout`, so a
        bot whose game master died before connecting does not linger.
        """
        connected = asyncio.Event()
        done = asyncio.Event()

        async def handler(ws: ServerConnection) -> None:
            if connected.is_set():
                await ws.close(1013, "bot already has a game master")
                return
            connected.set()
            try:
                await self._handle(ws)
            except ConnectionClosed:
                log.info("game master disconnected")
            finally:
                self._cancel_thinking()
                done.set()

        server = await transport.serve(socket_path, handler)
        log.info("%s listening on %s", self.name, socket_path)
        try:
            await asyncio.wait_for(connected.wait(), connect_timeout)
            await done.wait()
        except TimeoutError:
            log.error("no game master connected within %.0f s; exiting", connect_timeout)
        finally:
            Path(socket_path).unlink(missing_ok=True)
            server.close()
            await server.wait_closed()

    @classmethod
    def main(cls, argv: list[str] | None = None) -> None:
        parser = argparse.ArgumentParser(description=f"arena bot {cls.name}")
        parser.add_argument("--socket", required=True, help="Unix socket path to listen on")
        parser.add_argument("--name", default=None, help="name reported in `ready`")
        parser.add_argument("--seed", type=int, default=None, help="random seed")
        args = parser.parse_args(argv)
        logging.basicConfig(
            level=logging.INFO,
            stream=sys.stderr,
            format=f"%(asctime)s {args.name or cls.name} %(levelname)s %(message)s",
        )
        logging.getLogger("websockets").setLevel(logging.WARNING)
        bot = cls(name=args.name, seed=args.seed)
        try:
            asyncio.run(bot.serve(args.socket))
        except KeyboardInterrupt:
            pass
