"""Stateful CLI for game master sessions. Run through `dev/chess.sh`.

Each command either creates a detached session daemon (`start`, `load`) or
sends one control request to a live session, prints the answer, and exits.
`match` is the exception: it waits for its series to end. `new-bot` touches no session.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import string
import sys
import time
from pathlib import Path
from typing import Any

from coms.protocol import RpcError
from game import GameState
from game_master import paths, saves, sessions

EXIT_ERROR = 1
EXIT_USAGE = 2
EXIT_NO_SESSION = 3
EXIT_INTERRUPTED = 130

BOT_TEMPLATE = paths.SRC / "game_master" / "bot_template.py.txt"
VIEWER_URL = "http://127.0.0.1:8765/?sid={sid}"
WATCH_PACE_S = 0.5

# Reasons a game ends because of one bot, with what a bot author should check.
FAULTS = {
    "disconnect": "the bot process exited",
    "resignation": "choose_move returned None or raised",
    "timeout": "no move before the deadline",
    "illegal_move": "too many invalid moves",
    "protocol_error": "the bot sent a malformed message",
}


class CliError(Exception):
    def __init__(self, message: str, code: int = EXIT_ERROR):
        super().__init__(message)
        self.code = code


# --- sessions ---


def _resolve_sid(sid: str | None) -> str:
    live = sessions.live_sessions()
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
    try:
        return asyncio.run(sessions.call(sid, method, params, timeout=timeout))
    except RpcError as exc:
        raise CliError(f"{method} failed: {exc.code}: {exc.message}") from exc
    except sessions.Unreachable as exc:
        raise CliError(str(exc), EXIT_NO_SESSION) from exc


def _create_session(method: str, params: dict[str, Any]) -> tuple[str, Any]:
    try:
        return asyncio.run(sessions.create(method, params))
    except sessions.SessionError as exc:
        raise CliError(str(exc)) from exc


# --- commands ---


def _labels(pairs: list[str]) -> dict[str, str]:
    labels = {}
    for pair in pairs:
        key, sep, value = pair.partition("=")
        if not sep:
            raise CliError(f"bad label {pair!r}; give key=value", EXIT_USAGE)
        labels[key] = value
    return labels


def cmd_start(args: argparse.Namespace) -> Any:
    params = {
        "white": args.white,
        "black": args.black,
        "games": args.games,
        "alternate": not args.no_alternate,
        "move_timeout_s": args.timeout,
        "max_attempts": args.max_attempts,
        "max_plies": args.max_plies,
        "min_ply_s": args.pace,
    }
    optional = {"fen": args.fen, "seed": args.seed, "idle_timeout_s": args.idle_timeout,
                "finished_linger_s": args.finished_linger}
    params |= {k: v for k, v in optional.items() if v is not None}
    if args.label:
        params["labels"] = _labels(args.label)
    sid, _ = _create_session("start_game", params)
    return {"sid": sid}


def cmd_match(args: argparse.Namespace) -> Any:
    """Play a series between two bots, wait for its end, and return every game's result."""
    params = {"white": args.a, "black": args.b, "games": args.games, "alternate": True,
              "move_timeout_s": args.timeout, "min_ply_s": WATCH_PACE_S if args.ui else 0.0,
              "labels": {"owner": "match"}}
    if args.seed is not None:
        params["seed"] = args.seed
    if args.ui:
        params["finished_linger_s"] = 900.0
    sid, _ = _create_session("start_game", params)
    if args.ui:
        print(f"watch: {VIEWER_URL.format(sid=sid)}  (needs `dev/chess.sh ui` running)",
              flush=True)
    try:
        status = _wait_for_series(sid, args.ui)
        games = [_game_result(sid, f"{sid}-{i}") for i in range(1, status["game_index"] + 1)]
    except KeyboardInterrupt:
        asyncio.run(sessions.kill(sid))
        raise CliError(f"interrupted; killed session {sid}", EXIT_INTERRUPTED) from None
    if not args.ui:
        asyncio.run(sessions.kill(sid))
    return {"sid": sid, "games": games, "note": status["note"], "score": _score(status["bots"])}


def _score(bots: list[dict[str, Any]]) -> dict[str, float]:
    """Points per bot, keyed by name, or by name and slot when both bots share a name."""
    same = len({b["name"] for b in bots}) < len(bots)
    return {f"{b['name']}[{b['slot']}]" if same else b["name"]: b["points"] for b in bots}


def _wait_for_series(sid: str, watched: bool) -> dict[str, Any]:
    """Poll until the series finishes. A stop from the browser only pauses the wait."""
    while True:
        status = _call(sid, "status")
        if status["phase"] == "finished":
            return status
        if status["phase"] == "stopped" and not watched:
            raise CliError(f"session {sid} stopped: {status['note'] or 'no reason given'}")
        time.sleep(0.2)


def _game_result(sid: str, game_id: str) -> dict[str, Any]:
    h = _call(sid, "history", {"game_id": game_id})
    outcome = h["outcome"] or {"result": "*", "reason": "unfinished"}
    game = {"game_id": game_id, "white": h["players"]["white"], "black": h["players"]["black"],
            "result": outcome["result"], "reason": outcome["reason"], "plies": len(h["moves"]),
            "rejected": len(h["rejected"])}
    if outcome["reason"] in FAULTS and outcome["result"] != "1/2-1/2":
        loser = h["players"]["black" if outcome["result"] == "1-0" else "white"]
        logs = sorted(paths.records_dir(sid).glob(f"bot*-{loser}.log"))
        game["fault"] = {"bot": loser, "why": FAULTS[outcome["reason"]],
                         "logs": [_shown(p) for p in logs]}
    return game


def _shown(path: Path) -> str:
    return str(path.relative_to(Path.cwd()) if path.is_relative_to(Path.cwd()) else path)


def cmd_new_bot(args: argparse.Namespace) -> Any:
    name = args.name
    if not (name.isidentifier() and name == name.lower()):
        raise CliError(f"bad bot name {name!r}; use lowercase letters, digits and _", EXIT_USAGE)
    folder = paths.SRC / f"ai_{name}"
    if folder.exists():
        raise CliError(f"{folder} already exists", EXIT_USAGE)
    cls = "".join(part.capitalize() for part in name.split("_")) + "Bot"
    source = string.Template(BOT_TEMPLATE.read_text()).substitute(name=name, cls=cls)
    folder.mkdir()
    (folder / "__main__.py").write_text(source)
    return {"bot": name, "path": _shown(folder / "__main__.py")}


def cmd_load(args: argparse.Namespace) -> Any:
    try:
        path = saves.path_of(args.name)
    except ValueError as exc:
        raise CliError(str(exc), EXIT_USAGE) from exc
    if not path.is_file():
        raise CliError(f"no save named {args.name!r}; see `saves`")
    sid, _ = _create_session("load", {"name": args.name, "play": args.play})
    return {"sid": sid}


def cmd_ls(args: argparse.Namespace) -> Any:
    found = []
    for sid in sessions.live_sessions():
        try:
            found.append(_call(sid, "status", timeout=5.0))
        except CliError as exc:
            found.append({"sid": sid, "phase": "unreachable", "note": str(exc)})
    return {"sessions": found}


def cmd_saves(args: argparse.Namespace) -> Any:
    return {"saves": saves.names()}


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


def cmd_move(args: argparse.Namespace) -> Any:
    sid, uci = (None, args.words[0]) if len(args.words) == 1 else args.words
    sid = _resolve_sid(sid)
    waiting = _call(sid, "state").get("awaiting")
    if not (waiting and waiting["external"]):
        raise CliError("no external seat is to move")
    result = _call(sid, "submit_move", {"color": waiting["color"], "game_id": waiting["game_id"],
                                        "ply": waiting["ply"], "move": uci})
    if not result["accepted"]:
        raise CliError(f"move {uci} rejected: {result['reason']}")
    return result


def cmd_step(args: argparse.Namespace) -> Any:
    return _call(_resolve_sid(args.sid), "step", timeout=120.0)


def cmd_pace(args: argparse.Namespace) -> Any:
    sid, value = (None, args.words[0]) if len(args.words) == 1 else args.words
    try:
        seconds = float(value)
    except ValueError as exc:
        raise CliError(f"bad pace {value!r}; give seconds", EXIT_USAGE) from exc
    return _call(_resolve_sid(sid), "set_pace", {"min_ply_s": seconds})


def cmd_resign(args: argparse.Namespace) -> Any:
    sid = _resolve_sid(args.sid)
    color = args.color
    if color is None:
        external = [b["color"] for b in _call(sid, "status")["bots"] if b["external"]]
        if len(external) != 1:
            raise CliError("the session has no single external seat; pass --color", EXIT_USAGE)
        color = external[0]
    return _call(sid, "resign", {"color": color}, timeout=60.0)


def cmd_kill(args: argparse.Namespace) -> Any:
    sid = _resolve_sid(args.sid)
    asyncio.run(sessions.kill(sid))
    return {"killed": sid}


# --- output ---


def _score_line(status: dict[str, Any]) -> str:
    bots = status.get("bots") or []
    if not bots:
        return "-"
    return " vs ".join(f"{b['name']}[{b['slot']}] {b['points']:g}" for b in bots)


def show_start(result: dict[str, Any]) -> None:
    print(result["sid"])


def show_match(result: dict[str, Any]) -> None:
    for g in result["games"]:
        plies = f"{g['plies']} ply" if g["plies"] == 1 else f"{g['plies']} plies"
        line = (f"{g['game_id']}  {g['white']} (white) vs {g['black']} (black)  "
                f"{g['result']:<7} {g['reason']}, {plies}")
        if g["rejected"]:
            line += f", {g['rejected']} invalid moves"
        print(line)
        if "fault" in g:
            fault = g["fault"]
            print(f"    {fault['bot']} lost by {g['reason']}: {fault['why']}. "
                  f"See {' or '.join(fault['logs']) or 'its log'}")
    if result["note"]:
        print(f"note  {result['note']}")
    print("score " + " - ".join(f"{name} {points:g}" for name, points in result["score"].items()))


def show_new_bot(result: dict[str, Any]) -> None:
    print(f"created {result['path']}")
    print(f"play it: dev/chess.sh match {result['bot']} naive")


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
        proc = "external" if b.get("external") else f"pid {b['pid']}"
        print(f"bot {b['slot']}    {b['name']} as {b['color']}  {proc}  {state}")
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
    if s.get("awaiting"):
        print(f"waiting  on {s['awaiting']['seat']} ({s['awaiting']['color']})")


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


def show_move(result: dict[str, Any]) -> None:
    print(result["san"])


def show_resign(result: dict[str, Any]) -> None:
    print(f"{result['result']} ({result['reason']})")


def show_step(result: dict[str, Any]) -> None:
    print(f"{result['phase']} at ply {result['ply']}")


def show_pace(result: dict[str, Any]) -> None:
    print(f"{result['min_ply_s']:g}s")


COMMANDS = {
    "start": (cmd_start, show_start),
    "match": (cmd_match, show_match),
    "new-bot": (cmd_new_bot, show_new_bot),
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
    "move": (cmd_move, show_move),
    "resign": (cmd_resign, show_resign),
    "step": (cmd_step, show_step),
    "pace": (cmd_pace, show_pace),
}


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="print the raw JSON result")
    parser = argparse.ArgumentParser(prog="chess.sh", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("start", parents=[common], help="start a new session and print its id")
    p.add_argument("--white", required=True,
                   help="bot name, as in src/chess/ai_<name>, or @name for an external seat")
    p.add_argument("--black", required=True)
    p.add_argument("--games", type=int, default=1)
    p.add_argument("--no-alternate", action="store_true", help="keep colors fixed across games")
    p.add_argument("--fen", default=None, help="starting position")
    p.add_argument("--timeout", type=float, default=5.0, help="seconds per move")
    p.add_argument("--max-attempts", type=int, default=5)
    p.add_argument("--max-plies", type=int, default=500)
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("--pace", type=float, default=0.0, help="minimum seconds between bot plies")
    p.add_argument("--label", action="append", metavar="KEY=VALUE",
                   help="tag the session; repeat for more labels")
    p.add_argument("--idle-timeout", type=float, default=None,
                   help="save and exit after this many seconds with no control calls")
    p.add_argument("--finished-linger", type=float, default=None,
                   help="exit this many seconds after the series finishes")

    p = sub.add_parser("match", parents=[common],
                       help="play two bots, wait for the series to end, and print the score")
    p.add_argument("a", help="bot name; plays white in odd games")
    p.add_argument("b", help="bot name; plays white in even games")
    p.add_argument("--games", type=int, default=2)
    p.add_argument("--seed", type=int, default=None)
    p.add_argument("--timeout", type=float, default=5.0, help="seconds per move")
    p.add_argument("--ui", action="store_true",
                   help=f"play at {WATCH_PACE_S:g}s per ply and print the viewer URL")

    p = sub.add_parser("new-bot", parents=[common], help="create src/chess/ai_<name> from a template")
    p.add_argument("name")

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
        ("step", "play one ply of a stopped session"),
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

    p = sub.add_parser("move", parents=[common],
                       help="play the waiting external seat's move: move [sid] <uci>")
    p.add_argument("words", nargs="+", metavar="[sid] uci")

    p = sub.add_parser("pace", parents=[common], help="set the pace of a session: pace [sid] <seconds>")
    p.add_argument("words", nargs="+", metavar="[sid] seconds")

    p = sub.add_parser("resign", parents=[common], help="resign the current game for an external seat")
    p.add_argument("sid", nargs="?")
    p.add_argument("--color", choices=["white", "black"],
                   help="needed only when both seats are external")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command in ("save", "move", "pace") and len(args.words) > 2:
        parser.error(f"{args.command} takes [sid] and one value")
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
