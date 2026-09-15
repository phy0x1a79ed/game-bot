"""Saved series and session records, read and written without a daemon.

A save lives in `paths.SAVES`. A session record is the same document, written to
`record.json` in the session's records directory whenever a game ends or the session stops.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from game_master import paths
from game_master.match import GameRecord

# Reserved for daemons that save an abandoned session before shutting it down.
AUTOSAVE_PREFIX = "autosave-"


def path_of(name: str) -> Path:
    """The JSON path of a save. Raises `ValueError` for a bad name."""
    if not paths.SAVE_NAME_RE.match(name):
        raise ValueError(f"bad save name {name!r}; use [A-Za-z0-9_.-]")
    return paths.SAVES / f"{name}.json"


def names() -> list[str]:
    return sorted(p.stem for p in paths.SAVES.glob("*.json")) if paths.SAVES.is_dir() else []


def read(name: str) -> dict[str, Any]:
    """Raises `FileNotFoundError` for a missing save and `ValueError` for an unreadable one."""
    path = path_of(name)
    if not path.is_file():
        raise FileNotFoundError(f"no save named {name!r}")
    try:
        data = json.loads(path.read_text())
        if not isinstance(data["settings"], dict):
            raise TypeError("settings is not an object")
    except (ValueError, KeyError, TypeError) as exc:
        raise ValueError(f"save {name!r} is unreadable: {exc!r}") from exc
    return data


def write(name: str, data: dict[str, Any], pgn: str, overwrite: bool = False) -> Path:
    """Write `<name>.json` and `<name>.pgn`. Raises `FileExistsError` unless `overwrite`."""
    path = path_of(name)
    if path.exists() and not overwrite:
        raise FileExistsError(f"save {name!r} exists; pass overwrite")
    paths.SAVES.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1) + "\n")
    path.with_suffix(".pgn").write_text(pgn)
    return path


def summary(name: str, data: dict[str, Any]) -> dict[str, Any]:
    settings = data["settings"]
    games = data.get("games", [])
    last = games[-1]["game"] if games else None
    return {
        "name": name,
        "saved_at": data.get("saved_at"),
        "sid": data.get("sid"),
        "players": [settings.get("white"), settings.get("black")],
        "games": settings.get("games", 1),
        "played": len(games),
        "score": data.get("score", [0.0, 0.0]),
        "finished": len(games) >= settings.get("games", 1)
        and (last is None or last.get("outcome") is not None),
        "current": None if last is None else {
            "game_id": games[-1]["game_id"],
            "plies": len(last.get("moves", [])),
            "outcome": last.get("outcome"),
        },
    }


def summaries() -> list[dict[str, Any]]:
    """One summary per save, newest first. An unreadable save carries only `name` and `error`."""
    result = []
    for name in names():
        try:
            result.append(summary(name, read(name)))
        except (OSError, ValueError, KeyError, TypeError, IndexError) as exc:
            result.append({"name": name, "error": str(exc)})
    return sorted(result, key=lambda s: s.get("saved_at") or "", reverse=True)


def read_record(sid: str) -> dict[str, Any]:
    """A session's record. Raises `FileNotFoundError` or `ValueError` like `read`."""
    if not paths.SID_RE.match(sid):
        raise ValueError(f"bad session id {sid!r}")
    path = paths.records_dir(sid) / "record.json"
    if not path.is_file():
        raise FileNotFoundError(f"no record for session {sid!r}")
    try:
        return json.loads(path.read_text())
    except ValueError as exc:
        raise ValueError(f"record of session {sid!r} is unreadable: {exc!r}") from exc


def record_summaries(limit: int = 50) -> list[dict[str, Any]]:
    """Summaries of the newest session records. Unreadable records are skipped."""
    if not paths.SESSION_RECORDS.is_dir():
        return []
    files = [d / "record.json" for d in paths.SESSION_RECORDS.iterdir()
             if paths.SID_RE.match(d.name) and (d / "record.json").is_file()]
    files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
    result = []
    for file in files[:limit]:
        try:
            result.append(summary(file.parent.name, json.loads(file.read_text())))
        except (OSError, ValueError, KeyError, TypeError, IndexError):
            continue
    return result


def replay(data: dict[str, Any], game_id: str | None = None) -> dict[str, Any]:
    """One game of a save or record as `history` with FENs. Raises `LookupError`."""
    records = [GameRecord.from_dict(g) for g in data.get("games", [])]
    if game_id is None:
        chosen = records[-1] if records else None
    else:
        chosen = next((r for r in records if r.game_id == game_id), None)
    if chosen is None:
        raise LookupError(f"no game {game_id!r}" if game_id else "no game was played")
    return {"game_ids": [r.game_id for r in records], "score": data.get("score"),
            "labels": data.get("labels", {}), **chosen.history(fens=True)}
