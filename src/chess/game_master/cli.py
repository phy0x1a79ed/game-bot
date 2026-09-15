"""Stateful CLI for game master sessions. Run through `dev/chess.sh`.

Each command either creates a detached session daemon (`start`, `load`) or
sends one control request to a live session, prints the answer, and exits.
"""

from __future__ import annotations

import argparse
import asyncio
import json
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
from game import GameState
from game_master import paths

EXIT_ERROR = 1
EXIT_USAGE = 2
EXIT_NO_SESSION = 3

SESSION_START_TIMEOUT_S = 15.0
INIT_TIMEOUT_S = 60.0


class CliError(Exception):
    def __init__(self, message: str, code: int = EXIT_ERROR):
        super().__init__(message)
        self.code = code


# --- sessions ---


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _session_pid(sid: str) -> int | None:
    try:
        return int((paths.session_dir(sid) / "gm.pid").read_text().strip())
    except (OSError, ValueError):
        return None


def _live_sessions() -> list[str]:
    """Session ids with a running daemon. Removes directories left by dead ones."""
    if not paths.RUNTIME.is_dir():
        return []
    live = []
    for entry in sorted(paths.RUNTIME.iterdir()):
        if not (entry.is_dir() and paths.SID_RE.match(entry.name)):
            continue
        pid = _session_pid(entry.name)
        if pid is None:
            # A daemon writes gm.pid right after binding gm.sock. A directory
            # this old without one belongs to a daemon that died starting up.
            if time.time() - entry.stat().st_mtime > SESSION_START_TIMEOUT_S:
                shutil.rmtree(entry, ignore_errors=True)
            continue
        if _pid_alive(pid):
            live.append(entry.name)
        else:
            shutil.rmtree(entry, ignore_errors=True)
    return live


def _resolve_sid(sid: str | None) -> str:
    live = _live_sessions()
    if sid is None:
        if len(live) == 1:
            return live[0]
        if not live:
            raise CliError("no live sessions; run `start` or `load`", EXIT_NO_SESSION)
        raise CliError(f"several live sessions ({', '.join(live)}); name one", EXIT_USAGE)
    if not paths.SID_RE.match(sid):
        raise CliError(f"bad session id {sid!r}", EXIT_USAGE)
    if sid not in live:
        raise CliError(f"no live session {sid}", EXIT_NO_SESSION)
    return sid


def _call(sid: str, method: str, params: dict[str, Any] | None = None,
          timeout: float = 30.0) -> Any:
    sock = paths.session_dir(sid) / "gm.sock"
    try:
        return asyncio.run(rpc.call(sock, method, params, timeout=timeout))
    except RpcError as exc:
        raise CliError(f"{method} failed: {exc.code}: {exc.message}") from exc
    except (ConnectionError, ProtocolError, TimeoutError) as exc:
        raise CliError(f"session {sid} did not answer {method}: {exc}", EXIT_NO_SESSION) from exc


def _log_tail(path: Path, lines: int = 20) -> str:
    try:
        return "\n".join(path.read_text(errors="replace").splitlines()[-lines:])
    except OSError:
        return "(no log)"


def _terminate(proc: subprocess.Popen, sid: str) -> None:
    if proc.poll() is None:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    shutil.rmtree(paths.session_dir(sid), ignore_errors=True)


def _create_session(method: str, params: dict[str, Any]) -> tuple[str, Any]:
    sid = paths.mint_sid()
    records = paths.records_dir(sid)
    records.mkdir(parents=True)
    log_path = records / "gm.log"
    env = dict(os.environ, PYTHONPATH=str(paths.SRC))
    with log_path.open("ab") as log_file:
        # Detached with its own output, so the CLI (and `mamba run` around it)
        # exits without waiting on the daemon.
        proc = subprocess.Popen(
            [sys.executable, "-m", "game_master.daemon", "--session", sid],
            stdin=subprocess.DEVNULL,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            cwd=paths.REPO_ROOT,
            env=env,
            start_new_session=True,
        )

    def fail(message: str) -> CliError:
        _terminate(proc, sid)
        tail = _log_tail(log_path)
        shutil.rmtree(records, ignore_errors=True)
        return CliError(f"{message}\n--- gm.log ---\n{tail}")

    deadline = time.monotonic() + SESSION_START_TIMEOUT_S
    while _session_pid(sid) is None:
        if proc.poll() is not None:
            raise fail(f"game master exited with code {proc.returncode} during startup")
        if time.monotonic() > deadline:
            raise fail("game master did not start in time")
        time.sleep(0.05)
    try:
        result = _call(sid, method, params, timeout=INIT_TIMEOUT_S)
    except CliError as exc:
        raise fail(str(exc)) from exc
    return sid, result


# --- commands ---


def cmd_start(args: argparse.Namespace) -> Any:
    params = {
        "white": args.white,
        "black": args.black,
        "games": args.games,
        "alternate": not args.no_alternate,
        "move_timeout_s": args.timeout,
        "max_attempts": args.max_attempts,
        "max_plies": args.max_plies,
    }
    if args.fen is not None:
        params["fen"] = args.fen
    if args.seed is not None:
        params["seed"] = args.seed
    sid, _ = _create_session("start_game", params)
    return {"sid": sid}


def cmd_load(args: argparse.Namespace) -> Any:
    if not paths.SAVE_NAME_RE.match(args.name):
        raise CliError(f"bad save name {args.name!r}", EXIT_USAGE)
    if not (paths.SAVES / f"{args.name}.json").is_file():
        raise CliError(f"no save named {args.name!r}; see `saves`")
    sid, _ = _create_session("load", {"name": args.name, "play": args.play})
    return {"sid": sid}


def cmd_ls(args: argparse.Namespace) -> Any:
    sessions = []
    for sid in _live_sessions():
        try:
            sessions.append(_call(sid, "status", timeout=5.0))
        except CliError as exc:
            sessions.append({"sid": sid, "phase": "unreachable", "note": str(exc)})
    return {"sessions": sessions}


def cmd_saves(args: argparse.Namespace) -> Any:
    saves = sorted(p.stem for p in paths.SAVES.glob("*.json")) if paths.SAVES.is_dir() else []
    return {"saves": saves}


def cmd_status(args: argparse.Namespace) -> Any:
    return _call(_resolve_sid(args.sid), "status")


def cmd_state(args: argparse.Namespace) -> Any:
    return _call(_resolve_sid(args.sid), "state")


def cmd_history(args: argparse.Namespace) -> Any:
    params = {"game_id": args.game} if args.game else {}
    return _call(_resolve_sid(args.sid), "history", params)


def cmd_stop(args: argparse.Namespace) -> Any:
    return _call(_resolve_sid(args.sid), "stop", timeout=120.0)


def cmd_resume(args: argparse.Namespace) -> Any:
    return _call(_resolve_sid(args.sid), "resume")


def cmd_save(args: argparse.Namespace) -> Any:
    sid, name = (None, args.words[0]) if len(args.words) == 1 else args.words
    return _call(_resolve_sid(sid), "save", {"name": name, "overwrite": args.overwrite})


def cmd_kill(args: argparse.Namespace) -> Any:
    sid = _resolve_sid(args.sid)
    pid = _session_pid(sid)
    try:
        _call(sid, "shutdown")
    except CliError:
        if pid is not None:
            os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 20.0
    while pid is not None and _pid_alive(pid) and time.monotonic() < deadline:
        time.sleep(0.1)
    if pid is not None and _pid_alive(pid):
        os.kill(pid, signal.SIGKILL)
    shutil.rmtree(paths.session_dir(sid), ignore_errors=True)
    return {"killed": sid}


# --- output ---


def _score_line(status: dict[str, Any]) -> str:
    bots = status.get("bots") or []
    if not bots:
        return "-"
    return " vs ".join(f"{b['name']}[{b['slot']}] {b['points']:g}" for b in bots)


def show_start(result: dict[str, Any]) -> None:
    print(result["sid"])


def show_ls(result: dict[str, Any]) -> None:
    if not result["sessions"]:
        print("no live sessions")
        return
    for s in result["sessions"]:
        game = f"game {s.get('game_index', 0)}/{s.get('games', '-')}"
        print(f"{s['sid']}  {s['phase']:<11} {game:<11} {_score_line(s)}")


def show_saves(result: dict[str, Any]) -> None:
    print("\n".join(result["saves"]) or "no saves")


def show_status(s: dict[str, Any]) -> None:
    print(f"session  {s['sid']}  pid {s['pid']}  up {s['uptime_s']:g}s")
    print(f"phase    {s['phase']}")
    if s["phase"] == "idle":
        return
    print(f"game     {s.get('game_id')}  ({s.get('game_index')}/{s.get('games')})")
    print(f"score    {_score_line(s)}")
    for b in s["bots"]:
        state = "alive" if b["alive"] else "dead"
        print(f"bot {b['slot']}    {b['name']} as {b['color']}  pid {b['pid']}  {state}")
    if s.get("loaded_from"):
        print(f"loaded   {s['loaded_from']}")
    if s.get("note"):
        print(f"note     {s['note']}")
    print(f"records  {s['records']}")


def show_state(s: dict[str, Any]) -> None:
    print(GameState.from_fen(s["fen"]).ascii())
    print()
    players = s.get("players") or {}
    print(f"game     {s['game_id']}  {players.get('white', '?')} (white) vs "
          f"{players.get('black', '?')} (black)")
    print(f"fen      {s['fen']}")
    print(f"ply      {s['ply']}  {s['turn']} to move  last {s['last_move'] or '-'}")
    if s["outcome"]:
        print(f"outcome  {s['outcome']['result']} ({s['outcome']['reason']})")
    else:
        print(f"legal    {len(s['legal_moves'])} moves")


def show_history(h: dict[str, Any]) -> None:
    players = h["players"]
    print(f"game {h['game_id']}: {players['white']} (white) vs {players['black']} (black)")
    if h["initial_fen"] != GameState.initial().fen:
        print(f"from {h['initial_fen']}")
    for m in h["moves"]:
        think = f"{m['think_s']:.3f}s" if m["think_s"] is not None else "-"
        print(f"{m['ply']:>4} {m['side']:<5} {m['san']:<8} {m['uci']:<6} {think}")
    for r in h["rejected"]:
        print(f"rejected ply {r['ply']} {r['side']}: {r['move']!r} ({r['reason']})")
    if h["outcome"]:
        print(f"outcome {h['outcome']['result']} ({h['outcome']['reason']})")
    else:
        print("in progress")


def show_phase(result: dict[str, Any]) -> None:
    print(result["phase"])


def show_save(result: dict[str, Any]) -> None:
    print(result["path"])


def show_kill(result: dict[str, Any]) -> None:
    print(f"killed {result['killed']}")


COMMANDS = {
    "start": (cmd_start, show_start),
    "load": (cmd_load, show_start),
    "ls": (cmd_ls, show_ls),
    "saves": (cmd_saves, show_saves),
    "status": (cmd_status, show_status),
    "state": (cmd_state, show_state),
    "history": (cmd_history, show_history),
    "stop": (cmd_stop, show_phase),
    "resume": (cmd_resume, show_phase),
    "save": (cmd_save, show_save),
    "kill": (cmd_kill, show_kill),
}


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="print the raw JSON result")
    parser = argparse.ArgumentParser(prog="chess.sh", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("start", parents=[common], help="start a new session and print its id")
    p.add_argument("--white", required=True, help="bot name, as in src/chess/ai_<name>")
    p.add_argument("--black", required=True)
    p.add_argument("--games", type=int, default=1)
    p.add_argument("--no-alternate", action="store_true", help="keep colors fixed across games")
    p.add_argument("--fen", default=None, help="starting position")
    p.add_argument("--timeout", type=float, default=5.0, help="seconds per move")
    p.add_argument("--max-attempts", type=int, default=5)
    p.add_argument("--max-plies", type=int, default=500)
    p.add_argument("--seed", type=int, default=None)

    p = sub.add_parser("load", parents=[common], help="load a save into a new session")
    p.add_argument("name")
    p.add_argument("--play", action="store_true", help="resume play at once")

    sub.add_parser("ls", parents=[common], help="list live sessions")
    sub.add_parser("saves", parents=[common], help="list saved games")

    for name, help_text in [
        ("status", "session status"),
        ("state", "current board"),
        ("stop", "halt play after the move in flight"),
        ("resume", "continue a stopped session"),
        ("kill", "shut a session down"),
    ]:
        p = sub.add_parser(name, parents=[common], help=help_text)
        p.add_argument("sid", nargs="?")

    p = sub.add_parser("history", parents=[common], help="moves of the current or a given game")
    p.add_argument("sid", nargs="?")
    p.add_argument("--game", default=None, help="game id, for example k3x9a-2")

    p = sub.add_parser("save", parents=[common], help="save a session: save [sid] <name>")
    p.add_argument("words", nargs="+", metavar="[sid] name")
    p.add_argument("--overwrite", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "save" and len(args.words) > 2:
        parser.error("save takes [sid] <name>")
    run, show = COMMANDS[args.command]
    try:
        result = run(args)
    except CliError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return exc.code
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        show(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
