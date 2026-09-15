"""Game master sessions on this host: find, create, call and end detached daemons.

The CLI and long-running clients such as the awm realm service share this module.
"""

from __future__ import annotations

import asyncio
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from coms import rpc
from coms.protocol import ProtocolError, RpcError
from game_master import paths

START_TIMEOUT_S = 15.0
INIT_TIMEOUT_S = 60.0
KILL_GRACE_S = 20.0


class SessionError(Exception):
    """A session did not start. `code` is the RPC error code of a failed init."""

    def __init__(self, message: str, code: str | None = None, log: str | None = None):
        super().__init__(message if log is None else f"{message}\n--- gm.log ---\n{log}")
        self.code = code
        self.log = log


class Unreachable(SessionError):
    """A session did not answer a control request."""


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    # A daemon started by this process stays a zombie until reaped.
    try:
        return os.waitpid(pid, os.WNOHANG) == (0, 0)
    except ChildProcessError:
        return True


def session_pid(sid: str) -> int | None:
    try:
        return int((paths.session_dir(sid) / "gm.pid").read_text().strip())
    except (OSError, ValueError):
        return None


def socket_path(sid: str) -> Path:
    return paths.session_dir(sid) / "gm.sock"


def live_sessions() -> list[str]:
    """Session ids with a running daemon. Removes directories left by dead ones."""
    if not paths.RUNTIME.is_dir():
        return []
    live = []
    for entry in sorted(paths.RUNTIME.iterdir()):
        if not (entry.is_dir() and paths.SID_RE.match(entry.name)):
            continue
        pid = session_pid(entry.name)
        if pid is None:
            # A daemon writes gm.pid right after binding gm.sock. A directory
            # this old without one belongs to a daemon that died starting up.
            if time.time() - entry.stat().st_mtime > START_TIMEOUT_S:
                shutil.rmtree(entry, ignore_errors=True)
            continue
        if pid_alive(pid):
            live.append(entry.name)
        else:
            shutil.rmtree(entry, ignore_errors=True)
    return live


async def call(sid: str, method: str, params: dict[str, Any] | None = None,
               timeout: float = 30.0) -> Any:
    """Send one control request. Raises `RpcError`, or `Unreachable` when nothing answers."""
    try:
        return await rpc.call(socket_path(sid), method, params, timeout=timeout)
    except (OSError, ProtocolError, TimeoutError) as exc:
        raise Unreachable(f"session {sid} did not answer {method}: {exc}") from exc


def watch(sid: str, since_seq: int | None = None):
    """`async with sessions.watch(sid) as (result, frames)`. See `watch` in PROTOCOL.md."""
    params = {} if since_seq is None else {"since_seq": since_seq}
    return rpc.stream(socket_path(sid), "watch", params)


async def create(method: str, params: dict[str, Any],
                 python: str | None = None) -> tuple[str, Any]:
    """Start a detached daemon, send it the init request, and return `(sid, result)`.

    `python` is the daemon's interpreter. It needs websockets and python-chess.
    A failure leaves no process, runtime directory or records behind.
    """
    sid = paths.mint_sid()
    records = paths.records_dir(sid)
    records.mkdir(parents=True)
    log_path = records / "gm.log"
    with log_path.open("ab") as log_file:
        proc = subprocess.Popen(
            [python or sys.executable, "-m", "game_master.daemon", "--session", sid],
            stdin=subprocess.DEVNULL,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            cwd=paths.REPO_ROOT,
            env=paths.child_env(),
            start_new_session=True,
        )

    async def fail(message: str, code: str | None = None) -> SessionError:
        if proc.poll() is None:
            proc.terminate()
            if not await _wait_gone(proc.pid, 15.0):
                proc.kill()
                await _wait_gone(proc.pid, 5.0)
        error = SessionError(message, code, _log_tail(log_path))
        shutil.rmtree(paths.session_dir(sid), ignore_errors=True)
        shutil.rmtree(records, ignore_errors=True)
        return error

    loop = asyncio.get_running_loop()
    deadline = loop.time() + START_TIMEOUT_S
    while session_pid(sid) is None:
        if proc.poll() is not None:
            raise await fail(f"game master exited with code {proc.returncode} during startup")
        if loop.time() > deadline:
            raise await fail("game master did not start in time")
        await asyncio.sleep(0.05)
    try:
        result = await call(sid, method, params, timeout=INIT_TIMEOUT_S)
    except RpcError as exc:
        raise await fail(f"{method} failed: {exc.code}: {exc.message}", exc.code) from exc
    except Unreachable as exc:
        raise await fail(str(exc)) from exc
    return sid, result


async def kill(sid: str) -> None:
    """End a session: `shutdown` first, then SIGTERM, then SIGKILL."""
    pid = session_pid(sid)
    try:
        await call(sid, "shutdown", timeout=5.0)
    except (RpcError, Unreachable):
        _signal(pid, signal.SIGTERM)
    if pid is not None and not await _wait_gone(pid, KILL_GRACE_S):
        _signal(pid, signal.SIGKILL)
        await _wait_gone(pid, 5.0)
    shutil.rmtree(paths.session_dir(sid), ignore_errors=True)


async def _wait_gone(pid: int, timeout: float) -> bool:
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while pid_alive(pid):
        if loop.time() > deadline:
            return False
        await asyncio.sleep(0.05)
    return True


def _signal(pid: int | None, sig: int) -> None:
    if pid is None:
        return
    try:
        os.kill(pid, sig)
    except ProcessLookupError:
        pass


def _log_tail(path: Path, lines: int = 20) -> str:
    try:
        return "\n".join(path.read_text(errors="replace").splitlines()[-lines:])
    except OSError:
        return "(no log)"
