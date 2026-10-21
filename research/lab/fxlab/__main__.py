"""fxlab CLI: up, down, ls, lua, advance, save, waits, sbx, tool, tools, plus the commands each extension registers."""
import argparse
import importlib
import json
import sys

from .lab import Lab, LuaError, SbxError, ServiceError, labs

# Each extension module may define register(sub) -> {command: handler(args)}. A missing module is skipped.
EXTENSIONS = ("camera", "render", "bench", "assault", "fidelity", "designs")


def extensions(sub):
    handlers = {}
    for name in EXTENSIONS:
        try:
            mod = importlib.import_module(f".{name}", __package__)
        except ModuleNotFoundError as exc:
            if exc.name != f"{__package__}.{name}":
                print(f"fxlab: extension {name}: {exc!r}", file=sys.stderr)
            continue
        except Exception as exc:
            print(f"fxlab: extension {name}: {exc!r}", file=sys.stderr)
            continue
        if hasattr(mod, "register"):
            handlers.update(mod.register(sub))
    return handlers


def main(argv=None):
    p = argparse.ArgumentParser(prog="fxlab")
    sub = p.add_subparsers(dest="cmd", required=True)
    up = sub.add_parser("up")
    up.add_argument("name")
    src = up.add_mutually_exclusive_group(required=True)
    src.add_argument("--save", help="realm save name, copied read-only")
    src.add_argument("--create", action="store_true", help="new world from the service's lab map-gen settings")
    up.add_argument("--live", action="store_true", help="leave the game running instead of pausing it")
    up.add_argument("--camera", action="store_true", help="join a camera seat")
    down = sub.add_parser("down")
    down.add_argument("names", nargs="*")
    down.add_argument("--all", action="store_true", help="every lab of this worktree")
    ls = sub.add_parser("ls")
    ls.add_argument("--everyone", action="store_true", help="labs of every worktree")
    lua = sub.add_parser("lua", help="run Lua from a file, or from stdin with -")
    lua.add_argument("name")
    lua.add_argument("file")
    adv = sub.add_parser("advance")
    adv.add_argument("name")
    adv.add_argument("ticks", type=int)
    adv.add_argument("--speed", type=float, default=1000.0)
    sv = sub.add_parser("save")
    sv.add_argument("name")
    sv.add_argument("save")
    wt = sub.add_parser("waits", help="wait census: what the factory waits for, largest first")
    wt.add_argument("name")
    wt.add_argument("--surface", default="nauvis")
    wt.add_argument("--area", type=float, nargs=4, metavar=("X0", "Y0", "X1", "Y1"))
    wt.add_argument("-n", type=int, default=15)
    sb = sub.add_parser("sbx", help="call the fxlab-sbx mod: verb key=value ... (values parsed as JSON when they parse)")
    sb.add_argument("name")
    sb.add_argument("verb")
    sb.add_argument("args", nargs="*")
    ts = sub.add_parser("tool-sync", help="load research/tools into a lab")
    ts.add_argument("name")
    ts.add_argument("tools", nargs="*")
    tc = sub.add_parser("tool", help="run a library tool: tool key=value ...")
    tc.add_argument("name")
    tc.add_argument("tool")
    tc.add_argument("args", nargs="*")
    tl = sub.add_parser("tools", help="list the library tools defined in a lab, with their args")
    tl.add_argument("name")
    handlers = extensions(sub)
    a = p.parse_args(argv)

    if a.cmd in handlers:
        sys.exit(handlers[a.cmd](a) or 0)
    elif a.cmd == "up":
        lab = Lab(a.name).up(save=a.save, create=a.create, live=a.live, camera=a.camera)
        print(f"{lab.world} up ({lab.sid})")
    elif a.cmd == "down":
        from .lab import PREFIX, service, worlds
        for r in worlds() if a.all else []:
            if r["name"].startswith(PREFIX):
                service("release", session_id=r["session_id"])
                print(f"{r['name']} down")
        for n in a.names:
            lab = Lab(n)
            lab.down()
            print(f"{lab.world} down")
    elif a.cmd == "ls":
        for name, status in labs(everyone=a.everyone):
            print(f"{name}\t{status}")
    elif a.cmd in ("sbx", "tool"):
        from . import tools
        kv = json_args(a.args)
        try:
            r = Lab(a.name).sbx(a.verb, **kv) if a.cmd == "sbx" else tools.call(Lab(a.name), a.tool, **kv)
        except (SbxError, LuaError, ServiceError) as exc:
            sys.exit(str(exc))
        print(json.dumps(r, indent=1))
    elif a.cmd == "tools":
        from . import tools
        defined = {t["name"] for t in tools.listing(Lab(a.name))}
        for n, t in tools.library().items():
            if n in defined and t["header"]["kind"] == "call":
                print(f"{n}: {t['header']['summary']}\n    args: {t['header']['args']}")
    elif a.cmd == "tool-sync":
        from . import tools
        print(" ".join(tools.sync(Lab(a.name), a.tools or None)))
    elif a.cmd == "lua":
        code = sys.stdin.read() if a.file == "-" else open(a.file).read()
        try:
            print(Lab(a.name).lua(code))
        except LuaError as exc:
            sys.exit(str(exc))
    elif a.cmd == "advance":
        print(f"{Lab(a.name).advance(a.ticks, a.speed):.1f}s")
    elif a.cmd == "save":
        print(Lab(a.name).save(a.save))
    elif a.cmd == "waits":
        from . import waits
        area = ((a.area[0], a.area[1]), (a.area[2], a.area[3])) if a.area else None
        r = waits.census(Lab(a.name), a.surface, area)
        print("\n".join(waits.top(r, a.n)) or "no waits")
        print("blocked: " + ", ".join(f"{b['item']} {b['machines']}" for b in r["blocked"][:a.n]))
        if r["other"]:
            print("other: " + ", ".join(f"{k} {v}" for k, v in sorted(r["other"].items())))


def json_args(pairs):
    out = {}
    for pair in pairs:
        k, _, v = pair.partition("=")
        try:
            out[k] = json.loads(v)
        except json.JSONDecodeError:
            out[k] = v
    return out


if __name__ == "__main__":
    main()
