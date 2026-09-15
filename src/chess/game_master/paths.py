from __future__ import annotations

import os
import re
import secrets
import string
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SRC = REPO_ROOT / "src" / "chess"
ENVS = REPO_ROOT / "envs"

DATA = Path(os.environ.get("CHESS_ARENA_DATA", REPO_ROOT / "data" / "chess"))
SAVES = DATA / "saves"
SESSION_RECORDS = DATA / "sessions"

# Kept short: every socket path must fit in 107 bytes.
RUNTIME = Path(os.environ.get("CHESS_ARENA_RUNTIME", f"/tmp/chess-arena-{os.getuid()}"))

SID_RE = re.compile(r"^[a-z0-9]{5}$")
SAVE_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
_SID_ALPHABET = string.ascii_lowercase + string.digits


def session_dir(sid: str) -> Path:
    return RUNTIME / sid


def records_dir(sid: str) -> Path:
    return SESSION_RECORDS / sid


def mint_sid() -> str:
    while True:
        sid = "".join(secrets.choice(_SID_ALPHABET) for _ in range(5))
        if not session_dir(sid).exists() and not records_dir(sid).exists():
            return sid
