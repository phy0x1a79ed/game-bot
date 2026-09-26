"""Client verbs over the sessions on this host, with no transport attached.

The browser viewer dispatches its requests through `dispatch`. Each verb returns
JSON-ready data or raises `VerbError`.
"""

from __future__ import annotations

import asyncio
import json
from typing import Any, Awaitable, Callable

from coms.protocol import RpcError
from game_master import paths, saves, sessions
from game_master.seats import is_external

IDLE_TIMEOUT_S = 1800.0
FINISHED_LINGER_S = 900.0
BOT_PACE_S = 0.5

START_KEYS = ("white", "black", "games", "alternate", "fen", "move_timeout_s", "seat_timeout_s",
              "max_attempts", "max_plies", "seed", "min_ply_s")
LIFETIME_KEYS = ("idle_timeout_s", "finished_linger_s")
START_FILE = "start.json"


class VerbError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message


def _sid(args: dict[str, Any]) -> str:
    sid = str(args.get("session_id") or "")
    if not paths.SID_RE.match(sid):
        raise VerbError("invalid_params", f"bad session_id {sid!r}")
    return sid


async def _call(sid: str, method: str, params: dict[str, Any] | None = None,
                timeout: float = 30.0) -> Any:
    try:
        return await sessions.call(sid, method, params, timeout=timeout)
    except RpcError as exc:
        raise VerbError(exc.code, exc.message) from exc
    except sessions.Unreachable as exc:
        raise VerbError("not_running", f"session {sid} is not running") from exc


# ---- lifecycle ----

async def start(args: dict[str, Any]) -> dict[str, Any]:
    """Start a series, or load a save when `load` names one. `owner` becomes a label.

    A loaded series plays on unless it is finished or `play` is false.
    """
    opts = dict(args)
    owner = str(opts.pop("owner", "") or "viewer")
    lifetime = {k: opts.pop(k) for k in LIFETIME_KEYS if opts.get(k) is not None}
    if "load" not in opts:
        unknown = sorted(set(opts) - set(START_KEYS))
        if unknown:
            raise VerbError("invalid_params", f"unknown options {unknown}")
        return await _create("start_game", dict(opts), opts, owner, lifetime)
    name = str(opts["load"])
    try:
        data = saves.read(name)
    except FileNotFoundError as exc:
        raise VerbError("not_found", str(exc)) from exc
    except ValueError as exc:
        raise VerbError("invalid_params", str(exc)) from exc
    settings = data["settings"]
    params = {k: settings[k] for k in START_KEYS if settings.get(k) is not None}
    play = opts.get("play", not saves.summary(name, data)["finished"])
    return await _create("load", {"name": name, "play": bool(play)}, params, owner, lifetime)


async def _create(method: str, params: dict[str, Any], start_params: dict[str, Any],
                  owner: str, lifetime: dict[str, Any]) -> dict[str, Any]:
    seats = (str(start_params.get("white", "")), str(start_params.get("black", "")))
    mode = "pvb" if any(is_external(seat) for seat in seats) else "bvb"
    if method == "start_game" and mode == "bvb" and params.get("min_ply_s") is None:
        params["min_ply_s"] = start_params["min_ply_s"] = BOT_PACE_S
    params |= {"labels": {"owner": owner, "mode": mode},
               "idle_timeout_s": lifetime.get("idle_timeout_s", IDLE_TIMEOUT_S),
               "finished_linger_s": lifetime.get("finished_linger_s", FINISHED_LINGER_S)}
    try:
        sid, _ = await sessions.create(method, params)
    except sessions.SessionError as exc:
        raise VerbError(exc.code or "start_failed", str(exc)) from exc
    (paths.records_dir(sid) / START_FILE).write_text(
        json.dumps({"start": start_params, "owner": owner, "lifetime": lifetime}))
    return {"session_id": sid, "mode": mode}


async def kill(args: dict[str, Any]) -> dict[str, Any]:
    sid = _sid(args)
    await sessions.kill(sid)
    return {"killed": True, "session_id": sid}


async def rematch(args: dict[str, Any]) -> dict[str, Any]:
    """End the session and start a new one with the same players and settings."""
    sid = _sid(args)
    try:
        saved = json.loads((paths.records_dir(sid) / START_FILE).read_text())
    except (OSError, ValueError) as exc:
        raise VerbError("not_found", f"session {sid} has no start settings") from exc
    start_params = {k: v for k, v in saved["start"].items() if k != "seed"}
    await sessions.kill(sid)
    result = await _create("start_game", dict(start_params), start_params,
                           saved.get("owner", "viewer"), saved.get("lifetime", {}))
    return {**result, "previous": sid}


async def status(args: dict[str, Any]) -> dict[str, Any]:
    """Status of one session, or of every live session on this host."""
    if args.get("session_id"):
        return {"sessions": [await _call(_sid(args), "status")]}
    found = await asyncio.gather(*(_status_or_none(sid) for sid in sessions.live_sessions()))
    return {"sessions": [s for s in found if s]}


async def _status_or_none(sid: str) -> dict[str, Any] | None:
    try:
        return await sessions.call(sid, "status", timeout=5.0)
    except (RpcError, sessions.Unreachable):
        return None


# ---- perceive ----

async def observe(args: dict[str, Any]) -> dict[str, Any]:
    sid = _sid(args)
    status_, state = await asyncio.gather(_call(sid, "status"), _call(sid, "state"))
    return {"status": status_, "state": state}


async def history(args: dict[str, Any]) -> dict[str, Any]:
    params = {k: args[k] for k in ("game_id", "fens") if args.get(k) is not None}
    return await _call(_sid(args), "history", params)


async def snapshot(args: dict[str, Any]) -> dict[str, Any]:
    """`{seq, snapshot}` of a session, for a view that starts or resyncs."""
    sid = _sid(args)
    try:
        async with sessions.watch(sid) as (result, _frames):
            return result
    except RpcError as exc:
        raise VerbError(exc.code, exc.message) from exc
    except OSError as exc:
        raise VerbError("not_running", f"session {sid} is not running") from exc


async def bots(args: dict[str, Any]) -> dict[str, Any]:
    return {"bots": bot_names()}


def bot_names() -> list[str]:
    return sorted(p.parent.name.removeprefix("ai_") for p in paths.SRC.glob("ai_*/__main__.py"))


async def saves_(args: dict[str, Any]) -> dict[str, Any]:
    return {"saves": saves.summaries(), "records": saves.record_summaries()}


async def replay(args: dict[str, Any]) -> dict[str, Any]:
    name = args.get("name")
    if bool(name) == bool(args.get("session_id")):
        raise VerbError("invalid_params", "pass exactly one of name and session_id")
    try:
        data = saves.read(str(name)) if name else saves.read_record(_sid(args))
        return saves.replay(data, args.get("game_id"))
    except (FileNotFoundError, LookupError) as exc:
        raise VerbError("not_found", str(exc)) from exc
    except ValueError as exc:
        raise VerbError("invalid_params", str(exc)) from exc


# ---- act ----

async def move(args: dict[str, Any]) -> dict[str, Any]:
    """Play a move for the external seat to move. `ply` guards against a stale view."""
    sid = _sid(args)
    waiting = (await _call(sid, "state"))["awaiting"]
    if not (waiting and waiting["external"]):
        raise VerbError("not_your_turn", "no external seat is to move")
    ply = args.get("ply")
    if ply is not None and not isinstance(ply, int):
        raise VerbError("invalid_params", f"ply must be an integer, not {ply!r}")
    if ply is not None and ply != waiting["ply"]:
        raise VerbError("stale", f"the position is at ply {waiting['ply']}, not {args['ply']}")
    return await _call(sid, "submit_move", {"color": waiting["color"], "ply": waiting["ply"],
                                            "game_id": waiting["game_id"],
                                            "move": str(args.get("move") or "")})


async def resign(args: dict[str, Any]) -> dict[str, Any]:
    sid = _sid(args)
    color = args.get("color")
    if not color:
        external = [b["color"] for b in (await _call(sid, "status"))["bots"] if b["external"]]
        if len(external) != 1:
            raise VerbError("invalid_params", "pass color: the session has no single external seat")
        color = external[0]
    return await _call(sid, "resign", {"color": color}, timeout=60.0)


def _control(method: str, *keys: str, timeout: float = 30.0):
    async def handler(args: dict[str, Any]) -> Any:
        params = {k: args[k] for k in keys if args.get(k) is not None}
        return await _call(_sid(args), method, params, timeout)
    return handler


async def save(args: dict[str, Any]) -> dict[str, Any]:
    params = {"name": args.get("name"), "overwrite": bool(args.get("overwrite", False))}
    return await _call(_sid(args), "save", params)


VERBS: dict[str, Callable[[dict[str, Any]], Awaitable[Any]]] = {
    "bots": bots,
    "start": start,
    "kill": kill,
    "rematch": rematch,
    "status": status,
    "observe": observe,
    "history": history,
    "snapshot": snapshot,
    "saves": saves_,
    "replay": replay,
    "move": move,
    "resign": resign,
    "pause": _control("stop", timeout=60.0),
    "resume": _control("resume"),
    "step": _control("step", timeout=120.0),
    "set_pace": _control("set_pace", "min_ply_s"),
    "save": save,
}


async def dispatch(verb: str, args: dict[str, Any] | None = None) -> Any:
    handler = VERBS.get(verb)
    if handler is None:
        raise VerbError("unknown_method", verb)
    return await handler(dict(args or {}))
