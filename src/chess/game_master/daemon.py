"""One game master session: `python -m game_master.daemon --session <sid>`.

Serves the control API (Contract B) on the session's gm.sock until `shutdown`
or a signal, then ends its bots and removes the session directory.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import re
import shutil
import signal
import sys
import time
from pathlib import Path
from typing import Any

from coms import rpc
from coms.protocol import INIT_METHODS, RpcError
from game_master import paths, saves
from game_master.bots import BotFailed, BotProcess, FrameLog, bot_exists
from game_master.events import EventBus
from game_master.match import Match, Settings
from game_master.seats import EXTERNAL_NAME_RE, ExternalSeat, is_external

log = logging.getLogger("game_master")

PRE_INIT_METHODS = frozenset({"status", "list_saves", "shutdown", "watch"})
LIFETIME_PARAMS = frozenset({"labels", "idle_timeout_s", "finished_linger_s"})
LABEL_KEY_RE = re.compile(r"^[a-z][a-z0-9_]{0,31}$")
MAX_LABELS = 16


class Session:
    def __init__(self, sid: str, runtime: Path, records: Path):
        self.sid = sid
        self.runtime = runtime
        self.records = records
        self.started = time.time()
        self.match: Match | None = None
        self.frames: FrameLog | None = None
        self.bots: list[BotProcess] = []
        self.bus = EventBus()
        self.shutdown_requested = asyncio.Event()
        self.idle_timeout_s: float | None = None
        self.finished_linger_s: float | None = None
        self.last_activity = time.monotonic()
        self._reaper: asyncio.Task | None = None
        self._init_attempted = False

    async def dispatch(self, method: str, params: dict[str, Any]) -> Any:
        self.last_activity = time.monotonic()
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
        params, labels = self._take_lifetime(params)
        settings = Settings.from_params(params)
        await self._spawn_bots(settings)
        self.match = Match(self.sid, settings, self.bots, self.records, self.bus.emit)
        self.match.labels = labels
        self.match.start()
        self._start_reaper()
        return {"sid": self.sid}

    async def _init_load(self, params: dict[str, Any]) -> dict[str, Any]:
        _only(params, {"name", "play", *LIFETIME_PARAMS})
        params, labels = self._take_lifetime(params)
        name = _param(params, "name", str)
        play = _param(params, "play", bool, False)
        data = _read_save(name)
        settings = Settings.from_params(data["settings"])
        await self._spawn_bots(settings)
        self.match = Match.from_save(self.sid, data, self.bots, self.records, self.bus.emit)
        self.match.labels.update(labels)
        self.match.loaded_from = name
        if play:
            self.match.start()
        self._start_reaper()
        return {"sid": self.sid}

    def _take_lifetime(self, params: dict[str, Any]) -> tuple[dict[str, Any], dict[str, str]]:
        """Remove the session lifetime params, store the timeouts, and return the labels."""
        params = dict(params)
        labels = params.pop("labels", None) or {}
        if not (isinstance(labels, dict) and len(labels) <= MAX_LABELS and all(
            isinstance(k, str) and LABEL_KEY_RE.match(k) and isinstance(v, str) and len(v) <= 200
            for k, v in labels.items()
        )):
            raise RpcError("invalid_params",
                           f"labels must map up to {MAX_LABELS} [a-z0-9_] keys to short strings")
        for key in ("idle_timeout_s", "finished_linger_s"):
            value = params.pop(key, None)
            if value is not None and (
                not isinstance(value, (int, float)) or isinstance(value, bool) or value <= 0
            ):
                raise RpcError("invalid_params", f"{key} must be > 0 or null")
            setattr(self, key, None if value is None else float(value))
        return params, labels

    def _start_reaper(self) -> None:
        limits = [t for t in (self.idle_timeout_s, self.finished_linger_s) if t is not None]
        if limits:
            self._reaper = asyncio.create_task(self._reap(min(1.0, *(t / 4 for t in limits))))

    async def _reap(self, tick_s: float) -> None:
        """Shut the session down once nobody uses it. Runs without any client connected."""
        while True:
            await asyncio.sleep(tick_s)
            if self.bus.watchers:
                self.last_activity = time.monotonic()
            idle_s = time.monotonic() - self.last_activity
            match = self.match
            if match.phase == "finished":
                if self.finished_linger_s is not None and idle_s >= self.finished_linger_s:
                    log.info("session %s finished and unused for %.0fs", self.sid, idle_s)
                    break
            elif self.idle_timeout_s is not None and idle_s >= self.idle_timeout_s and (
                # An unwatched bot series still makes progress, so only waiting play is idle.
                match.phase != "running" or any(bot.external for bot in match.bots)
            ):
                log.info("session %s idle for %.0fs", self.sid, idle_s)
                if match.current is not None:
                    self._autosave()
                break
        self.shutdown_requested.set()

    def _autosave(self) -> None:
        name = f"{saves.AUTOSAVE_PREFIX}{self.sid}"
        try:
            saves.write(name, self.match.to_save(), self.match.current.game.to_pgn(), overwrite=True)
            log.info("saved %s", name)
        except OSError:
            log.exception("autosave %s failed", name)

    async def _spawn_bots(self, settings: Settings) -> None:
        for name in (settings.white, settings.black):
            if is_external(name):
                if not EXTERNAL_NAME_RE.match(name):
                    raise RpcError("invalid_params", f"bad external seat {name!r}; use @[a-z0-9_]")
            elif not bot_exists(name):
                raise RpcError("invalid_params", f"unknown bot {name!r}: no src/chess/ai_{name}")
        self.frames = FrameLog(self.records / "frames.jsonl")
        seeds = (None, None) if settings.seed is None else (settings.seed, settings.seed + 1)
        self.bots = [
            ExternalSeat(slot, name, self.frames) if is_external(name) else
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
        return self.status()

    def status(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "sid": self.sid,
            "pid": os.getpid(),
            "uptime_s": round(time.time() - self.started, 1),
            "phase": "idle",
            "records": str(self.records),
            "watchers": self.bus.watchers,
        }
        if self.match is not None:
            result.update(self.match.status())
            result["loaded_from"] = getattr(self.match, "loaded_from", None)
        return result

    async def _state(self, params: dict[str, Any]) -> dict[str, Any]:
        return self.match.state()

    async def _history(self, params: dict[str, Any]) -> dict[str, Any]:
        _only(params, {"game_id", "fens"})
        return self.match.history(_param(params, "game_id", str, None),
                                  _param(params, "fens", bool, False))

    async def _stop(self, params: dict[str, Any]) -> dict[str, Any]:
        await self.match.stop()
        return {"phase": self.match.phase}

    async def _resume(self, params: dict[str, Any]) -> dict[str, Any]:
        if self.match.phase != "stopped":
            raise RpcError("busy", f"cannot resume while {self.match.phase}")
        self.match.start()
        return {"phase": self.match.phase}

    async def _watch(self, params: dict[str, Any]) -> rpc.Stream:
        _only(params, {"since_seq"})
        since_seq = _param(params, "since_seq", int, None)
        # No await between subscribing and reading seq and the snapshot, so no event is lost.
        watcher, backlog = self.bus.subscribe(since_seq)
        result: dict[str, Any] = {"seq": self.bus.seq, "events": backlog, "snapshot": None}
        if backlog is None:
            current = self.match.current if self.match else None
            result["snapshot"] = {
                "status": self.status(),
                "state": self.match.state() if self.match else None,
                "history": current.history() if current else None,
            }
        return rpc.Stream(result, self.bus.frames(watcher), lambda: self.bus.unsubscribe(watcher))

    async def _set_pace(self, params: dict[str, Any]) -> dict[str, Any]:
        _only(params, {"min_ply_s"})
        return self.match.set_pace(float(_param(params, "min_ply_s", (int, float))))

    async def _step(self, params: dict[str, Any]) -> dict[str, Any]:
        _only(params, set())
        await self.match.step()
        return {"phase": self.match.phase, "ply": len(self.match.current.game.moves)}

    async def _submit_move(self, params: dict[str, Any]) -> dict[str, Any]:
        _only(params, {"color", "game_id", "ply", "move"})
        return self.match.submit_move(_color(params), _param(params, "game_id", str),
                                      _param(params, "ply", int), _param(params, "move", str))

    async def _resign(self, params: dict[str, Any]) -> dict[str, Any]:
        _only(params, {"color"})
        return await self.match.resign(_color(params))

    async def _save(self, params: dict[str, Any]) -> dict[str, Any]:
        _only(params, {"name", "overwrite"})
        name = _param(params, "name", str)
        overwrite = _param(params, "overwrite", bool, False)
        if name.startswith(saves.AUTOSAVE_PREFIX):
            raise RpcError("invalid_params", f"save names starting {saves.AUTOSAVE_PREFIX!r} are reserved")
        if self.match.current is None:
            raise RpcError("no_game", "no game has started")
        try:
            path = saves.write(name, self.match.to_save(), self.match.current.game.to_pgn(),
                               overwrite)
        except ValueError as exc:
            raise RpcError("invalid_params", str(exc)) from exc
        except FileExistsError as exc:
            raise RpcError("exists", str(exc)) from exc
        return {"path": str(path)}

    async def _list_saves(self, params: dict[str, Any]) -> dict[str, Any]:
        return {"saves": saves.names()}

    async def _shutdown(self, params: dict[str, Any]) -> dict[str, Any]:
        # Let the response reach the client before the server closes.
        asyncio.get_running_loop().call_later(0.1, self.shutdown_requested.set)
        return {}

    async def close(self) -> None:
        if self._reaper is not None:
            self._reaper.cancel()
            await asyncio.gather(self._reaper, return_exceptions=True)
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


def _param(params: dict[str, Any], key: str, kind: type | tuple[type, ...],
           default: Any = _REQUIRED) -> Any:
    if key not in params or params[key] is None:
        if default is _REQUIRED:
            raise RpcError("invalid_params", f"missing param {key!r}")
        return default
    value = params[key]
    if not isinstance(value, kind) or (kind is not bool and isinstance(value, bool)):
        raise RpcError("invalid_params", f"{key}: bad value {value!r}")
    return value


def _color(params: dict[str, Any]) -> str:
    color = _param(params, "color", str)
    if color not in ("white", "black"):
        raise RpcError("invalid_params", f"color: bad value {color!r}")
    return color


def _read_save(name: str) -> dict[str, Any]:
    try:
        return saves.read(name)
    except FileNotFoundError as exc:
        raise RpcError("not_found", str(exc)) from exc
    except ValueError as exc:
        raise RpcError("invalid_params", str(exc)) from exc


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
