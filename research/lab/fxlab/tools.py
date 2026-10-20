"""The tool library: Lua tools under research/tools/, loaded into a world's game-bot-control registry (mod >= 0.6).

CONTRACT.md § Tools defines the header and the remote verbs. The realm service reads the same files, so a tool
proven here runs unchanged on the realm.
"""

import re
from pathlib import Path

from .lab import SbxError

TOOLS = Path(__file__).resolve().parents[2] / "tools"
KEYS = ("tool", "kind", "effect", "summary", "args", "returns")
KINDS = ("call", "lib")
EFFECTS = ("read", "act", "cheat")
NAME = re.compile(r"^[A-Za-z0-9_-]{1,48}$")
HEADER = re.compile(r"^---\s*([a-z]+):\s*(.*?)\s*$")


def header(code):
    """The `--- key: value` lines at the top of a tool file, as a dict."""
    out = {}
    for line in code.splitlines():
        m = HEADER.match(line)
        if not m:
            break
        out[m[1]] = m[2]
    return out


def problems(path, code):
    h = header(code)
    errs = [f"missing header key {k}" for k in KEYS if k not in h]
    if h.get("tool") != path.stem:
        errs.append(f"tool name {h.get('tool')!r} does not match the file name {path.stem!r}")
    if not NAME.match(path.stem):
        errs.append("name must be 1-48 letters, digits, - or _")
    if h.get("kind") not in KINDS:
        errs.append(f"kind must be one of {KINDS}")
    if h.get("effect") not in EFFECTS:
        errs.append(f"effect must be one of {EFFECTS}")
    return errs


def library(root=TOOLS):
    """Every tool under root as name -> {path, header, code}. Raises ValueError listing every bad file."""
    tools, errs = {}, []
    for path in sorted(Path(root).rglob("*.lua")):
        code = path.read_text()
        bad = problems(path, code)
        if path.stem in tools:
            bad.append(f"duplicate of {tools[path.stem]['path']}")
        if bad:
            errs.append(f"{path}: " + "; ".join(bad))
            continue
        tools[path.stem] = {"path": path, "header": header(code), "code": code}
    if errs:
        raise ValueError("\n".join(errs))
    return tools


def _check(r):
    if isinstance(r, dict) and r.get("ok") is False:
        raise SbxError(r.get("error", "error"), r.get("detail", ""))
    return r


def sync(lab, names=None, root=TOOLS):
    """Define the library's tools in the lab, libs first. Returns the names defined."""
    tools = library(root)
    chosen = [n for n in tools if names is None or n in names]
    chosen.sort(key=lambda n: tools[n]["header"]["kind"] != "lib")
    for n in chosen:
        h = tools[n]["header"]
        _check(lab.call("game_bot", "tool_define",
                        {"name": n, "code": tools[n]["code"], "kind": h["kind"], "effect": h["effect"],
                         "summary": h["summary"]}))
    return chosen


def call(lab, name, **args):
    """Run tool `name` with args in the lab and return what it returned."""
    return _check(lab.call("game_bot", "tool_call", {"name": name, "args": args})).get("r")


def listing(lab):
    return _check(lab.call("game_bot", "tool_list", {}))["tools"]
