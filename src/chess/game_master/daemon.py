"""One game master session: `python -m game_master.daemon --session <sid>`.

Serves the control API (Contract B) on the session's gm.sock until `shutdown`
or a signal, then ends its bots and removes the session directory.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import shutil
import signal
import sys
import time
from pathlib import Path
from typing import Any

from coms import rpc
from coms.protocol import INIT_METHODS, RpcError
from game_master import paths
from game_master.bots import BotFailed, BotProcess, FrameLog, bot_exists
from game_master.match import Match, Settings

log = logging.getLogger("game_master")

PRE_INIT_METHODS = frozenset({"status", "list_saves", "shutdown"})


class Session:
    def __init__(self, sid: str, runtime: Path, records: Path):
        self.sid = sid
        self.runtime = runtime
        self.records = records
        self.started = time.time()
        self.match: Match | None = None
        self.frames: FrameLog | None = None
        self.bots: list[BotProcess] = []
        self.shutdown_requested = asyncio.Event()
        self._init_attempted = False

    async def dispatch(self, method: str, params: dict[str, Any]) -> Any:
        if method in INIT_METHODS:
            if self._init_attempted:
                raise RpcError("already_initialized", "this session already has a game")
            self._init_attempted = True
            return await getattr(self, f"_init_{method}")(params)
        if self.match is None and method not in PRE_INIT_METHODS:
            raise RpcError("no_game", "the session has no game yet")
        return await getattr(self, f"_{method}")(params)

    # --- init ---

    async def _init_start_game(self, params: dict[str, Any]) -> dict[str, Any]:
        settings = Settings.from_params(params)
        await self._spawn_bots(settings)
        self.match = Match(self.sid, settings, self.bots, self.records)
        self.match.start()
        return {"sid": self.sid}

    async def _init_load(self, params: dict[str, Any]) -> dict[str, Any]:
        _only(params, {"name", "play"})
        name = _param(params, "name", str)
        play = _param(params, "play", bool, False)
        data = _read_save(name)
        settings = Settings.from_params(data["settings"])
        await self._spawn_bots(settings)
        self.match = Match.from_save(self.sid, data, self.bots, self.records)
        self.match.loaded_from = name
        if play:
            self.match.start()
        return {"sid": self.sid}

    async def _spawn_bots(self, settings: Settings) -> None:
        for name in (settings.white, settings.black):
            if not bot_exists(name):
                raise RpcError("invalid_params", f"unknown bot {name!r}: no src/chess/ai_{name}")
        self.frames = FrameLog(self.records / "frames.jsonl")
        seeds = (None, None) if settings.seed is None else (settings.seed, settings.seed + 1)
        self.bots = [
            BotProcess(slot, name, self.runtime / f"{color}.sock",
                       self.records / f"bot{slot}-{name}.log", self.frames, self.sid, color,
                       seeds[slot])
            for slot, (name, color) in enumerate(
                [(settings.white, "white"), (settings.black, "black")]
            )
        ]
        results = await asyncio.gather(*(b.start() for b in self.bots), return_exceptions=True)
        errors = [r for r in results if isinstance(r, BaseException)]
        if errors:
            await asyncio.gather(*(b.close() for b in self.bots), return_exceptions=True)
            self.bots = []
            message = "; ".join(str(e) for e in errors)
            if all(isinstance(e, BotFailed) for e in errors):
                raise RpcError("bot_failed", message)
            raise errors[0]

    # --- methods ---

    async def _status(self, params: dict[str, Any]) -> dict[str, Any]:
        result: dict[str, Any] = {
            "sid": self.sid,
            "pid": os.getpid(),
            "uptime_s": round(time.time() - self.started, 1),
            "phase": "idle",
            "records": str(self.records),
        }
        if self.match is not None:
            result.update(self.match.status())
            result["loaded_from"] = getattr(self.match, "loaded_from", None)
        return result

    async def _state(self, params: dict[str, Any]) -> dict[str, Any]:
        return self.match.state()

    async def _history(self, params: dict[str, Any]) -> dict[str, Any]:
        _only(params, {"game_id"})
        return self.match.history(_param(params, "game_id", str, None))

    async def _stop(self, params: dict[str, Any]) -> dict[str, Any]:
        await self.match.stop()
        return {"phase": self.match.phase}

    async def _resume(self, params: dict[str, Any]) -> dict[str, Any]:
        if self.match.phase != "stopped":
            raise RpcError("busy", f"cannot resume while {self.match.phase}")
        self.match.start()
        return {"phase": self.match.phase}

    async def _save(self, params: dict[str, Any]) -> dict[str, Any]:
        _only(params, {"name", "overwrite"})
        name = _save_name(_param(params, "name", str))
        overwrite = _param(params, "overwrite", bool, False)
        if self.match.current is None:
            raise RpcError("no_game", "no game has started")
        path = paths.SAVES / f"{name}.json"
        if path.exists() and not overwrite:
            raise RpcError("exists", f"save {name!r} exists; pass overwrite")
        paths.SAVES.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.match.to_save(), indent=1) + "\n")
        path.with_suffix(".pgn").write_text(self.match.current.game.to_pgn())
        return {"path": str(path)}

    async def _list_saves(self, params: dict[str, Any]) -> dict[str, Any]:
        saves = sorted(p.stem for p in paths.SAVES.glob("*.json")) if paths.SAVES.is_dir() else []
        return {"saves": saves}

    async def _shutdown(self, params: dict[str, Any]) -> dict[str, Any]:
        # Let the response reach the client before the server closes.
        asyncio.get_running_loop().call_later(0.1, self.shutdown_requested.set)
        return {}

    async def close(self) -> None:
        if self.match is not None:
            await self.match.shutdown()
        elif self.bots:
            await asyncio.gather(*(b.close() for b in self.bots), return_exceptions=True)
        if self.frames is not None:
            self.frames.close()


def _only(params: dict[str, Any], allowed: set[str]) -> None:
    unknown = set(params) - allowed
    if unknown:
        raise RpcError("invalid_params", f"unknown params: {sorted(unknown)}")


_REQUIRED = object()


def _param(params: dict[str, Any], key: str, kind: type, default: Any = _REQUIRED) -> Any:
    if key not in params or params[key] is None:
        if default is _REQUIRED:
            raise RpcError("invalid_params", f"missing param {key!r}")
        return default
    value = params[key]
    if not isinstance(value, kind) or (kind is not bool and isinstance(value, bool)):
        raise RpcError("invalid_params", f"{key}: bad value {value!r}")
    return value


def _save_name(name: str) -> str:
    if not paths.SAVE_NAME_RE.match(name):
        raise RpcError("invalid_params", f"bad save name {name!r}; use [A-Za-z0-9_.-]")
    return name


def _read_save(name: str) -> dict[str, Any]:
    path = paths.SAVES / f"{_save_name(name)}.json"
    if not path.is_file():
        raise RpcError("not_found", f"no save named {name!r}")
    try:
        data = json.loads(path.read_text())
        data["settings"]
    except (ValueError, KeyError, TypeError) as exc:
        raise RpcError("invalid_params", f"save {name!r} is unreadable: {exc!r}") from exc
    return data


async def serve(sid: str, runtime: Path, records: Path) -> None:
    session = Session(sid, runtime, records)
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        loop.add_signal_handler(sig, session.shutdown_requested.set)
    server = await rpc.serve_control(runtime / "gm.sock", session.dispatch)
    (runtime / "gm.pid").write_text(f"{os.getpid()}\n")
    log.info("session %s serving on %s", sid, runtime / "gm.sock")
    try:
        await session.shutdown_requested.wait()
        log.info("session %s shutting down", sid)
    finally:
        server.close()
        await session.close()
        await server.wait_closed()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="chess arena game master session")
    parser.add_argument("--session", required=True, help="5-character session id")
    args = parser.parse_args(argv)
    if not paths.SID_RE.match(args.session):
        parser.error("session id must be 5 characters of [a-z0-9]")
    logging.basicConfig(
        level=logging.INFO,
        stream=sys.stderr,
        format=f"%(asctime)s gm[{args.session}] %(name)s %(levelname)s %(message)s",
    )
    logging.getLogger("websockets").setLevel(logging.WARNING)
    runtime = paths.session_dir(args.session)
    records = paths.records_dir(args.session)
    paths.RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        runtime.mkdir(mode=0o700)
    except FileExistsError:
        log.error("session directory %s already exists", runtime)
        return 2
    records.mkdir(parents=True, exist_ok=True)
    try:
        asyncio.run(serve(args.session, runtime, records))
    finally:
        shutil.rmtree(runtime, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
