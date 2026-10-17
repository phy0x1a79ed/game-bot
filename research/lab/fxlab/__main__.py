"""fxlab CLI: up, down, ls, lua, advance, save."""
import argparse
import sys

from .lab import Lab, LuaError, labs


def main(argv=None):
    p = argparse.ArgumentParser(prog="fxlab")
    sub = p.add_subparsers(dest="cmd", required=True)
    up = sub.add_parser("up")
    up.add_argument("name")
    src = up.add_mutually_exclusive_group(required=True)
    src.add_argument("--save", help="realm save name, copied read-only")
    src.add_argument("--create", action="store_true", help="new world from fxlab/map-gen-settings.json")
    up.add_argument("--cpus", type=float, default=2.0)
    up.add_argument("--memory", default="4g")
    down = sub.add_parser("down")
    down.add_argument("names", nargs="*")
    down.add_argument("--all", action="store_true")
    sub.add_parser("ls")
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
    a = p.parse_args(argv)

    if a.cmd == "up":
        Lab(a.name).up(save=a.save, create=a.create, cpus=a.cpus, memory=a.memory)
        print(f"fxlab-{a.name} up")
    elif a.cmd == "down":
        names = [n.removeprefix("fxlab-") for n, _ in labs()] if a.all else a.names
        for n in names:
            Lab(n).down()
            print(f"fxlab-{n} down")
    elif a.cmd == "ls":
        for name, status in labs():
            print(f"{name}\t{status}")
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


if __name__ == "__main__":
    main()
