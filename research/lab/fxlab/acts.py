"""The safe-act surface: checked actions on a lab's world that never create items. See lua/acts.lua."""

import json
from pathlib import Path

from .bench import lua_value

LUA = Path(__file__).resolve().parent / "lua"
VERBS = ("look", "resources", "network", "rate", "ghost", "ghosts", "blueprint", "remove", "cancel", "recipe", "research")


def act(lab, verb, surface="nauvis", **args):
    """Run one act. Returns {"ok": True, "did": ...} or {"ok": False, "refused": reason}."""
    prelude = f"ACT = {{verb = {json.dumps(verb)}, surface = {json.dumps(surface)}, args = {lua_value(args)}}}\n"
    return json.loads(lab.lua_file(LUA / "acts.lua", prelude=prelude))


def parse_args(pairs):
    """key=value pairs from a command line; values that parse as JSON keep their type."""
    out = {}
    for pair in pairs:
        k, _, v = pair.partition("=")
        try:
            out[k] = json.loads(v)
        except ValueError:
            out[k] = v
    return out


def render(r):
    """Compact text for a model to read: one JSON line, or one line per row when `did` is a list of records."""
    did = r.get("did")
    if not (isinstance(did, list) and did and isinstance(did[0], dict)):
        return json.dumps(r, separators=(",", ":"))
    cols = list(dict.fromkeys(k for row in did for k in row))
    head = {k: v for k, v in r.items() if k != "did"}
    lines = [json.dumps({**head, "columns": cols}, separators=(",", ":"))]
    lines += [json.dumps([row.get(k) for k in cols], separators=(",", ":")) for row in did]
    return "\n".join(lines)
