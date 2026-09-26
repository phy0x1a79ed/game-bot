from __future__ import annotations

import os
import re
import secrets
import string
from pathlib import Path

REPO_ROOT = Path(os.environ.get("CHESS_ARENA_ROOT", Path(__file__).resolve().parents[3])).resolve()
SRC = REPO_ROOT / "src" / "chess"
ENVS = REPO_ROOT / "envs"

# Daemons and bots start from the source tree, so a non-editable install cannot work.
if not (SRC / "game_master" / "daemon.py").is_file():
    raise RuntimeError(
        f"chess arena source tree not found at {SRC}; "
        "install the arena editable or set CHESS_ARENA_ROOT to its checkout"
    )

DATA = Path(os.environ.get("CHESS_ARENA_DATA", REPO_ROOT / "data" / "chess"))
SAVES = DATA / "saves"
SESSION_RECORDS = DATA / "sessions"

# Kept short: every socket path must fit in transport.MAX_SOCKET_PATH bytes.
RUNTIME = Path(os.environ.get("CHESS_ARENA_RUNTIME", f"/tmp/chess-arena-{os.getuid()}"))

SID_RE = re.compile(r"^[a-z0-9]{5}$")
SAVE_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
_SID_ALPHABET = string.ascii_lowercase + string.digits


def session_dir(sid: str) -> Path:
    return RUNTIME / sid


def records_dir(sid: str) -> Path:
    return SESSION_RECORDS / sid


def child_env(**extra: str) -> dict[str, str]:
    """Environment for a daemon or bot, pinned to this process's source tree and data."""
    return dict(
        os.environ,
        PYTHONPATH=str(SRC),
        CHESS_ARENA_ROOT=str(REPO_ROOT),
        CHESS_ARENA_DATA=str(DATA),
        CHESS_ARENA_RUNTIME=str(RUNTIME),
        **extra,
    )


def mint_sid() -> str:
    while True:
        sid = "".join(secrets.choice(_SID_ALPHABET) for _ in range(5))
        if not session_dir(sid).exists() and not records_dir(sid).exists():
            return sid
