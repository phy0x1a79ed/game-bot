"""Throwaway Factorio worlds for experiments: labs that the realm service acquires.

A lab is a world of kind lab. The realm service boots it on a copy of a save, or on a new world, with the lab mods
and sandbox rules, and its own ports and saves. Every call here is a service verb over the gateway, so a lab has
the realm's lifecycle, seats, pause, saves and exec log. The realm volume is mounted read-only, so a lab can never
touch a real world.

Each worktree gets its own world-name prefix and record root, so parallel scopes never share a lab name or a
ratchet record. The service caps the labs running on the box. `up` waits for a slot.
"""

import hashlib
import json
import os
import re
import time
import urllib.error
import urllib.request
from pathlib import Path

SERVICE = os.environ.get("FXLAB_SERVICE", "http://127.0.0.1:7819/svc/rlm-factorio/fn")
SERVICE_DIR = Path(os.environ.get("FXLAB_SERVICE_DIR", Path.home() / "agentic_workspace/.awm/services/rlm-factorio"))
GAME = "factorio"
HERE = Path(__file__).resolve().parent
WORKTREE = HERE.parents[2].name
SHARED = Path(os.environ.get("FXLAB_SHARED", Path.home() / ".cache/fxlab"))
_TAG = "" if WORKTREE == "factorio" else (WORKTREE.removeprefix("fxlab").strip("-") or "hub")
ROOT = Path(os.environ.get("FXLAB_ROOT", SHARED / "scopes" / _TAG if _TAG else SHARED))
PREFIX = os.environ.get("FXLAB_PREFIX", f"fx-{_TAG}-" if _TAG else "fx-")
CAP_WAIT = float(os.environ.get("FXLAB_CAP_WAIT", "3600"))
CAP_POLL = 5.0
MAX_OUTPUT = 1_048_576
ERR_MARK = "Cannot execute command."
GONE = ("stopped", "error")


class LuaError(RuntimeError):
    pass


class ServiceError(RuntimeError):
    """A realm-service verb that failed. The message is the service's error text."""


class SbxError(RuntimeError):
    """An sbx or tool call that returned ok=false. `.code` is the short error code from CONTRACT.md."""

    def __init__(self, code, detail=""):
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code, self.detail = code, detail


def service(verb, /, timeout=900, **args):
    """Call one realm-service verb through the gateway and return its reply."""
    req = urllib.request.Request(f"{SERVICE}/{verb}", data=json.dumps(args).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read()
    except urllib.error.HTTPError as exc:
        text = exc.read().decode(errors="replace")
        try:
            text = json.loads(text).get("error", text)
        except (ValueError, AttributeError):
            pass
        raise ServiceError(f"{verb}: {text}") from None
    return json.loads(body) if body else {}


def world_name(name):
    """The service's world name for lab `name`: this worktree's prefix, lowercase, at most 40 characters."""
    full = re.sub(r"[^a-z0-9-]+", "-", (PREFIX + name).lower()).strip("-")
    if len(full) > 40:
        full = full[:33].rstrip("-") + "-" + hashlib.sha1(full.encode()).hexdigest()[:6]
    return full


def worlds():
    """Every live lab world on the service, as its status row."""
    return [r for r in service("status").get("sessions", []) if r.get("kind") == "lab" and r.get("status") not in GONE]


def labs(everyone=False):
    """This worktree's live labs as (world name, status); every live lab with everyone=True."""
    return [(r["name"], r["status"]) for r in worlds() if everyone or r["name"].startswith(PREFIX)]


def _save_arg(save):
    """A seeded save lives in the shared cache. Any other name is a realm save the service copies read-only."""
    cached = SHARED / "_saves" / f"{save}.zip"
    return str(cached) if cached.exists() else save


class Lab:
    def __init__(self, name):
        self.name = name
        self.world = world_name(name)
        self.boot = None
        self._sid = None
        self.game_port = None

    # -- lifecycle --

    def _row(self):
        rows = [r for r in worlds() if r["name"] == self.world]
        return rows[0] if rows else None

    @property
    def sid(self):
        if self._sid is None:
            row = self._row()
            if row is None:
                raise RuntimeError(f"lab {self.world} is not up")
            self._sid = row["session_id"]
        return self._sid

    @property
    def container(self):
        row = self._row()
        return row["container_name"] if row else self.world

    @property
    def saves(self):
        """The host directory holding the lab's saves: its boot save and every `save`."""
        return SERVICE_DIR / "worlds" / self.sid / "saves"

    @property
    def output(self):
        """The host directory the lab server writes as its script-output."""
        return SERVICE_DIR / "output" / self.sid

    def up(self, save=None, create=False, live=False, camera=False, headless=True):
        """Start the lab on a copy of save `save`, or on a new world when create is true.

        The game is paused on arrival unless live is true. camera=True joins a camera seat (camera.py).
        headless=False publishes the game port, kept in `game_port`, so a client can join.
        """
        if self.running():
            raise RuntimeError(f"lab {self.world} already running")
        args = {"game": GAME, "kind": "lab", "name": self.world, "live": bool(live),
                "headless": bool(headless)}
        if create:
            args["create"] = True
        else:
            args["save"] = _save_arg(save)
        deadline = time.time() + CAP_WAIT
        while True:
            try:
                reply = service("acquire", timeout=1900, **args)
                break
            except ServiceError as exc:
                if "LAB_CAP" not in str(exc) or time.time() > deadline:
                    raise
                time.sleep(CAP_POLL)
        self._sid = reply["session_id"]
        self.game_port = reply.get("game_port")
        self.boot = None if create else Path(args["save"]).name.removesuffix(".zip")
        if camera:
            from . import camera as cam
            cam.attach(self)
        return self

    def down(self):
        row = self._row()
        if row is not None:
            service("release", session_id=row["session_id"])
        self._sid = None

    def running(self):
        return self._row() is not None

    def reload(self, name=None):
        """Load save `name` (default the boot save) in place, pause it, and bring back the camera if it had one."""
        name = name or self.boot
        if not name:
            raise RuntimeError(f"lab {self.world} booted on a new world; name a save to reload")
        self._call("world_load", timeout=700, name=name)
        self._call("pause", paused=True)
        from . import camera as cam
        seat = cam.seat(self)
        if seat:
            service("rejoin", timeout=3700, seat_id=seat["seat_id"])

    def _call(self, verb, /, timeout=900, **args):
        return service(verb, timeout=timeout, session_id=self.sid, **args)

    # -- Lua --

    def lua(self, code):
        """Run Lua in one tick and return what it printed with rcon.print. Raises LuaError on a script error."""
        out = self._call("exec_lua", timeout=200, code=code, max_output=MAX_OUTPUT)["output"]
        if ERR_MARK in out:
            raise LuaError(out[out.index(ERR_MARK):])
        return out

    def lua_file(self, path, prelude=""):
        return self.lua(prelude + Path(path).read_text())

    def call(self, interface, verb, args=None):
        """remote.call(interface, verb, args) with args and result passed as JSON."""
        src = json.dumps(args if args is not None else {})
        out = self.lua(f'rcon.print(helpers.table_to_json({{r = remote.call("{interface}", "{verb}", '
                       f'helpers.json_to_table([==[{src}]==]))}}))')
        reply = json.loads(out) if out.strip() else {}
        return reply.get("r") if isinstance(reply, dict) else None

    def sbx(self, verb, **args):
        """Call the fxlab-sbx mod. Raises SbxError when the call returns ok=false."""
        r = self._call("sbx", timeout=200, verb=verb, args=args)
        if isinstance(r, dict) and r.get("ok") is False:
            raise SbxError(r.get("error", "error"), r.get("detail", ""))
        return r

    def tool(self, name, args):
        """Run library tool `name` through the service's tool verb. Returns the mod's reply."""
        return self._call("tool", timeout=200, name=name, args=args)

    def tick(self):
        return int(self.lua("rcon.print(game.tick)"))

    def advance(self, ticks, speed=1000.0):
        """Run the game `ticks` ticks at up to `speed`, then pause. Returns the wall seconds taken.

        The service bounds one advance call, so a long advance takes several.
        """
        t0, left = time.time(), ticks
        while left > 0:
            r = self._call("advance", timeout=700, ticks=left, speed=speed)
            left -= r["ticks"]
            if r.get("error") != "TIMEOUT":
                break
        return time.time() - t0

    def save(self, name):
        """Write saves/<name>.zip, replacing a save of that name."""
        self._call("world_save", name=name, overwrite=True)
        return self.saves / f"{name}.zip"

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.down()
