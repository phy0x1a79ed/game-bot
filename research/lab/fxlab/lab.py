"""Throwaway headless Factorio servers for experiments, each capped in CPU and memory.

A lab runs the realm's appliance image with the engine as its entrypoint, on a
copy of a save, with no published ports. Lua reaches it through `docker exec`
into a pipe that holds one RCON socket. Saves are copied out of the realm's
volume read-only, so a lab can never touch a real world.

Each worktree gets its own container prefix and lab root, so parallel scopes never
share a lab name or a ratchet record. A lease caps the labs running on the box.
"""

import fcntl
import json
import os
import shutil
import subprocess
import time
from contextlib import contextmanager
from pathlib import Path

IMAGE = os.environ.get("FXLAB_IMAGE", "rlm-factorio/appliance:2.1.20")
REALM_APPLIANCE = Path(os.environ.get(
    "FXLAB_REALM", Path.home() / "agentic_workspace/awm/services/rlm-factorio/appliance"))
REALM_VOLUME = os.environ.get("FXLAB_REALM_VOLUME", "rlm-factorio_factorio-saves")
GBC_MOD = Path(os.environ.get("FXLAB_GBC_MOD", REALM_APPLIANCE / "mods/game-bot-control"))
HERE = Path(__file__).resolve().parent
WORKTREE = HERE.parents[2].name
SHARED = Path(os.environ.get("FXLAB_SHARED", Path.home() / ".cache/fxlab"))
_TAG = "" if WORKTREE == "factorio" else (WORKTREE.removeprefix("fxlab").strip("-") or "hub")
ROOT = Path(os.environ.get("FXLAB_ROOT", SHARED / "scopes" / _TAG if _TAG else SHARED))
PREFIX = os.environ.get("FXLAB_PREFIX", f"fxlab-{_TAG}-" if _TAG else "fxlab-")
MAX_LABS = int(os.environ.get("FXLAB_MAX_LABS", "3"))
LEASE_WAIT = float(os.environ.get("FXLAB_LEASE_WAIT", "3600"))
RCON_PORT, RCON_PASSWORD = 27015, "fxlab"
FACTORIO = "/opt/factorio/bin/x64/factorio"
ERR_MARK = "Cannot execute command."


class LuaError(RuntimeError):
    pass


class SbxError(RuntimeError):
    """An sbx or tool call that returned ok=false. `.code` is the short error code from CONTRACT.md."""

    def __init__(self, code, detail=""):
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code, self.detail = code, detail


def docker(*args, check=True, capture=True):
    res = subprocess.run(["docker", *args], capture_output=capture, text=True)
    if check and res.returncode != 0:
        raise RuntimeError(f"docker {' '.join(args[:2])}: {res.stderr.strip()}")
    return res.stdout


def realm_save(name, dest_dir):
    """Copy a named save out of the realm volume into dest_dir (volume mounted read-only)."""
    dest_dir = Path(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)
    cache = SHARED / "_saves" / f"{name}.zip"
    if not cache.exists():
        cache.parent.mkdir(parents=True, exist_ok=True)
        docker("run", "--rm", "-v", f"{REALM_VOLUME}:/s:ro", "-v", f"{cache.parent}:/o",
               "alpine:3", "sh", "-c", f"cp '/s/{name}.zip' /o/ && chmod 666 '/o/{name}.zip'")
    shutil.copy(cache, dest_dir / f"{name}.zip")
    return dest_dir / f"{name}.zip"


def labs(everyone=False):
    """This worktree's lab containers as (name, status); every fxlab container with everyone=True."""
    out = docker("ps", "-a", "--filter", "label=fxlab", "--format", "{{.Names}}\t{{.Status}}")
    rows = [line.split("\t") for line in out.splitlines() if line]
    return rows if everyone else [r for r in rows if r[0].startswith(PREFIX)]


@contextmanager
def lease(wait=LEASE_WAIT, poll=5.0):
    """Hold the box-wide lock while fewer than MAX_LABS lab servers run; the caller starts its server inside."""
    SHARED.mkdir(parents=True, exist_ok=True)
    deadline = time.time() + wait
    with open(SHARED / "lease.lock", "w") as fh:
        while True:
            fcntl.flock(fh, fcntl.LOCK_EX)
            running = docker("ps", "-q", "--filter", "label=fxlab.role=server").split()
            if len(running) < MAX_LABS:
                try:
                    yield len(running)
                finally:
                    fcntl.flock(fh, fcntl.LOCK_UN)
                return
            fcntl.flock(fh, fcntl.LOCK_UN)
            if time.time() > deadline:
                raise RuntimeError(f"lab lease: {len(running)} lab servers running, cap {MAX_LABS}, "
                                   f"waited {wait:.0f}s")
            time.sleep(poll)


class Lab:
    def __init__(self, name):
        self.name = name
        self.container = PREFIX + name
        self.dir = ROOT / name
        self.saves = self.dir / "saves"
        self.output = self.dir / "script-output"
        self._pipe = None

    # -- lifecycle --

    def mounts(self):
        """Volume flags shared by the server and any client that must load the same mods."""
        return [
            "-v", f"{self.saves}:/opt/factorio/saves",
            "-v", f"{self.output}:/opt/factorio/script-output",
            "-v", f"{HERE / 'rcon_pipe.py'}:/fxlab/rcon_pipe.py:ro",
            "-v", f"{GBC_MOD}:/opt/factorio/mods/game-bot-control:ro",
            "-v", f"{HERE / 'mods/fxlab-census'}:/opt/factorio/mods/fxlab-census:ro",
            "-v", f"{HERE / 'mods/fxlab-sbx'}:/opt/factorio/mods/fxlab-sbx:ro",
            "-v", f"{HERE / 'server-settings.json'}:/fxlab/server-settings.json:ro",
            "-v", f"{HERE / 'map-gen-settings.json'}:/fxlab/map-gen-settings.json:ro",
        ]

    def up(self, save=None, create=False, cpus=2.0, memory="4g", map_gen=None, live=False, camera=False):
        """Start the server on a copy of realm save `save`, or on a new world when create is true.

        The game is paused on arrival unless live is true. camera=True attaches a render client (camera.py).
        """
        if self.running():
            raise RuntimeError(f"{self.container} already running")
        docker("rm", "-f", self.container, check=False)
        self.saves.mkdir(parents=True, exist_ok=True)
        self.output.mkdir(parents=True, exist_ok=True)
        mounts = self.mounts()
        if create:
            world = "/opt/factorio/saves/world.zip"
            gen = ["--map-gen-settings", "/fxlab/map-gen-settings.json"] if map_gen is None else map_gen
            docker("run", "--rm", "--label", "fxlab=1", *mounts, "--entrypoint", FACTORIO, IMAGE,
                   "--create", world, *gen, "--mod-directory", "/opt/factorio/mods")
        else:
            world = f"/opt/factorio/saves/{realm_save(save, self.saves).name}"
        with lease():
            docker("run", "-d", "--name", self.container, "--label", "fxlab=1", "--label", "fxlab.role=server",
                   "--label", f"fxlab.prefix={PREFIX}",
                   "--cpus", str(cpus), "--memory", memory, *mounts, "--entrypoint", FACTORIO, IMAGE,
                   "--start-server", world, "--server-settings", "/fxlab/server-settings.json",
                   "--rcon-port", str(RCON_PORT), "--rcon-password", RCON_PASSWORD,
                   "--mod-directory", "/opt/factorio/mods")
        deadline = time.time() + 180
        while "to(InGame)" not in self.logs(200):
            if time.time() > deadline or not self.running():
                raise RuntimeError(f"{self.container} did not reach InGame:\n{self.logs(20)}")
            time.sleep(0.5)
        if not live:
            self.lua("game.tick_paused = true")
        if camera:
            from . import camera as cam
            cam.attach(self)
        return self

    def down(self):
        self.close()
        from . import camera as cam
        cam.detach(self, missing_ok=True)
        docker("rm", "-f", self.container, check=False)

    def running(self):
        out = docker("inspect", "-f", "{{.State.Running}}", self.container, check=False)
        return out.strip() == "true"

    def logs(self, n=50):
        res = subprocess.run(["docker", "logs", "--tail", str(n), self.container], capture_output=True, text=True)
        return res.stdout + res.stderr

    def close(self):
        if self._pipe:
            self._pipe.stdin.close()
            self._pipe.wait(timeout=10)
            self._pipe = None

    # -- Lua --

    def _open(self):
        self._pipe = subprocess.Popen(
            ["docker", "exec", "-i", self.container, "python3", "-u", "/fxlab/rcon_pipe.py",
             str(RCON_PORT), RCON_PASSWORD],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        hello = json.loads(self._pipe.stdout.readline() or '{"ok": false, "error": "pipe died"}')
        if not hello.get("ok"):
            raise RuntimeError(f"rcon pipe: {hello}")

    def lua(self, code):
        """Run Lua in one tick and return what it printed with rcon.print. Raises LuaError on a script error."""
        if self._pipe is None or self._pipe.poll() is not None:
            self._open()
        self._pipe.stdin.write(json.dumps({"code": code}) + "\n")
        reply = json.loads(self._pipe.stdout.readline() or '{"ok": false, "error": "pipe died"}')
        if not reply["ok"]:
            raise RuntimeError(reply["error"])
        out = reply["out"]
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
        r = self.call("sbx", verb, args)
        if isinstance(r, dict) and r.get("ok") is False:
            raise SbxError(r.get("error", "error"), r.get("detail", ""))
        return r

    def tick(self):
        return int(self.lua("rcon.print(game.tick)"))

    def advance(self, ticks, speed=1000.0, poll=0.25):
        """Run the game `ticks` ticks at up to `speed`, then pause. Returns the wall seconds taken."""
        start = self.tick()
        target = start + ticks
        t0 = time.time()
        self.lua(f"game.speed = {speed} game.tick_paused = false")
        while True:
            now = self.tick()
            left = target - now
            if left <= 0:
                break
            if left < 600:
                # land close to the target: slow down for the last few seconds of game time
                self.lua(f"game.speed = {max(1.0, min(speed, left / 30))}")
            time.sleep(poll)
        self.lua("game.tick_paused = true game.speed = 1")
        return time.time() - t0

    def save(self, name):
        """Write saves/<name>.zip inside the lab directory."""
        self.lua(f'game.server_save("{name}")')
        path = self.saves / f"{name}.zip"
        deadline = time.time() + 60
        while "Saving finished" not in self.logs(5):
            if time.time() > deadline:
                raise RuntimeError("save did not finish")
            time.sleep(0.2)
        return path

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.down()
