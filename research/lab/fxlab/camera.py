"""Render client for labs: a full-game client under Xvfb that joins a lab over a private network and takes screenshots.

The camera player sits in a hidden booth surface with no character, so it changes nothing the lab simulates
once the save already holds it (see `seed`). A first join into an unseeded save spawns a character and
shifts unit numbers. The camera container is not a lab server, so the lease does not count it.
"""

import itertools
import math
import secrets
import shutil
import struct
import subprocess
import time
from pathlib import Path

from .lab import IMAGE, SHARED, Lab, SbxError, docker

PLAYER = "fxcam"
GAME_PORT = 34197
CONFIG = Path(__file__).resolve().parent / "cam" / "config-cam.ini"
CACHE = SHARED / "rc" / "cam-cache"
PX_PER_TILE = 32
MAX_SIDE = 4096
CLIENT_GONE = ("WaitingForUserToSaveOrQuitAfterServerLeft", "Quitting multiplayer connection")
JOINS = {}  # lab container -> seconds the last attach took to reach InGame
DESYNC_MARKS = ("desync", "multiplayermanager failed", "received unexpected", "dropped", "crc mismatch",
                "keep up with the server")
SHOTS = itertools.count(1)


def container(lab):
    return lab.container + "-cam"


def network(lab):
    return lab.container + "-net"


def _logs(name, n=400):
    res = subprocess.run(["docker", "logs", "--tail", str(n), name], capture_output=True, text=True)
    return res.stdout + res.stderr


def _running(name):
    return docker("inspect", "-f", "{{.State.Running}}", name, check=False).strip() == "true"


def _marker(lab):
    return lab.dir / "camera.marker"


def _lab_id(lab):
    return docker("inspect", "-f", "{{.Id}}", lab.container, check=False).strip()


def _cache_mounts():
    """Sprite caches mount read-only, so two cameras never race on a write. Mesa's shader cache is multi-process safe."""
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / "mesa_shader_cache").mkdir(exist_ok=True)
    mounts = ["-v", f"{CACHE / 'mesa_shader_cache'}:/root/.cache/mesa_shader_cache"]
    for name in ("atlas-cache.dat", "crop-cache.dat"):
        if (CACHE / name).exists():
            mounts += ["-v", f"{CACHE / name}:/opt/factorio/{name}:ro"]
    return mounts


def attach(lab, timeout=300):
    """Start the camera for `lab`, wait for it to join, then park its player in the booth.

    Never `docker restart` the camera: after a server restart the client hangs and seat.sh leaves a stale
    X lock. Remove the container and attach again.
    """
    cam, net = container(lab), network(lab)
    docker("rm", "-f", cam, check=False)
    _marker(lab).unlink(missing_ok=True)
    docker("network", "create", "--label", "fxlab=1", net, check=False)
    try:
        docker("network", "connect", net, lab.container, check=False)
        # the camera needs the lab's mods and its script-output (the client writes the PNGs), not its saves
        mods = [m for m in lab.mounts()[1::2]
                if m.split(":")[1].startswith(("/opt/factorio/mods", "/opt/factorio/script-output"))]
        t0 = time.time()
        docker("run", "-d", "--name", cam, "--label", "fxlab=1", "--label", "fxlab.role=camera",
               "--network", net, "--cpus", "2", "--memory", "4g",
               "-e", "FACTORIO_ROLE=seat", "-e", f"SEAT_NAME={PLAYER}", "-e", f"FACTORIO_HOST={lab.container}",
               "-e", f"FACTORIO_PORT={GAME_PORT}", "-e", "SEAT_UNMAP=1",
               *[x for m in mods for x in ("-v", m)],
               "-v", f"{CONFIG}:/opt/factorio/config/config.ini:ro", *_cache_mounts(), IMAGE)
        while "to(InGame)" not in _logs(cam):
            if time.time() - t0 > timeout or not _running(cam):
                raise RuntimeError(f"camera did not reach InGame:\n{_logs(cam, 40)}")
            time.sleep(0.25)
        JOINS[lab.container] = round(time.time() - t0, 1)
        _park(lab, deadline=t0 + timeout)
    except BaseException:
        detach(lab, missing_ok=True)
        raise
    _marker(lab).write_text(_lab_id(lab))
    return JOINS[lab.container]


def _park(lab, deadline):
    """view_booth, retried while the server has not yet created the joined player."""
    while True:
        try:
            return lab.sbx("view_booth", player=PLAYER)
        except SbxError as exc:
            if exc.code != "not_found" or time.time() > deadline:
                raise
            time.sleep(0.5)


def detach(lab, missing_ok=False):
    """Remove the camera container and its network."""
    cam, net = container(lab), network(lab)
    if not missing_ok and not docker("ps", "-aq", "--filter", f"name=^{cam}$").strip():
        raise RuntimeError(f"{cam}: no camera attached")
    docker("rm", "-f", cam, check=False)
    docker("network", "disconnect", "-f", net, lab.container, check=False)
    docker("network", "rm", net, check=False)
    _marker(lab).unlink(missing_ok=True)


def ensure(lab):
    """Recreate the camera when its container is gone or its client left the game, if this lab ever had one."""
    cam = container(lab)
    if _running(cam) and not any(mark in _logs(cam, 60) for mark in CLIENT_GONE):
        return
    marker = _marker(lab)
    if not marker.exists() or marker.read_text() != _lab_id(lab):
        raise RuntimeError("lab has no camera; start it with camera=True")
    attach(lab)


def desyncs(lab):
    """Log lines of the camera client and the server that name a desync or a drop of the camera."""
    seen = []
    for name in (container(lab), lab.container):
        res = subprocess.run(["docker", "logs", name], capture_output=True, text=True)
        for line in (res.stdout + res.stderr).splitlines():
            if any(mark in line.lower() for mark in DESYNC_MARKS):
                seen.append(f"{name}: {line.strip()}")
    return seen


def png_size(path):
    """(width, height) from the PNG header, or None while the file is incomplete or not a PNG."""
    with open(path, "rb") as fh:
        head = fh.read(24)
        if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        fh.seek(-12, 2)
        if fh.read(12)[4:8] != b"IEND":
            return None
    return struct.unpack(">II", head[16:24])


def _wait_png(path, timeout):
    t0, last = time.time(), -1
    while time.time() - t0 < timeout:
        if path.exists():
            size = path.stat().st_size
            if size > 0 and size == last and png_size(path):
                return path
            last = size
        time.sleep(0.05)
    raise RuntimeError(f"no screenshot at {path} after {timeout:.0f}s")


def _nonce():
    return f"{next(SHOTS)}-{secrets.token_hex(3)}"


def frame(area, zoom=1):
    """The centre and pixel resolution that fill the frame with `area` at `zoom`, each side capped at 4096."""
    (x0, y0), (x1, y1) = area if len(area) == 2 else ((area[0], area[1]), (area[2], area[3]))
    side = lambda lo, hi: min(MAX_SIDE, max(1, math.ceil(abs(hi - lo) * PX_PER_TILE * zoom)))
    return ((x0 + x1) / 2, (y0 + y1) / 2), (side(x0, x1), side(y0, y1))


def render(lab, area=None, position=None, zoom=1, surface="nauvis", info=False, resolution=None, timeout=120):
    """Take a screenshot with the camera and return the PNG path under lab.output once the file stops growing.

    Give `area` as ((x0, y0), (x1, y1)) to fill the frame with it, or `position` and optionally `resolution`.
    """
    if area is not None:
        position, resolution = frame(area, zoom)
    elif position is None:
        raise ValueError("render needs area or position")
    ensure(lab)
    path = f"fxlab/shot-{lab.tick()}-{_nonce()}.png"
    # the lab server writes script-output as root, so only it can delete a leftover
    docker("exec", lab.container, "rm", "-f", f"/opt/factorio/script-output/{path}")
    r = lab.sbx("view_shot", surface=surface, position=list(position), zoom=zoom, info=bool(info),
                resolution=list(resolution or (1280, 720)), path=path)
    return _wait_png(lab.output / r["path"], timeout)


def seed(save):
    """Write `<save>+cam` into the shared save cache: `save` with the camera player in it, parked in its booth.

    A save made while paused loads paused at its exact tick. Returns the new save name.
    """
    name = f"{save}+cam"
    lab = Lab("seed")
    try:
        lab.up(save=save, camera=True)
        booth = lab.lua(f'local p = game.players["{PLAYER}"] rcon.print(p.surface.name .. " " .. tostring(p.controller_type))')
        if not booth.startswith("cam-booth"):
            raise RuntimeError(f"camera player is not parked: {booth}")
        path = lab.save(name)
        cached = SHARED / "_saves" / f"{name}.zip"
        cached.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(path, cached)
        cached.chmod(0o666)
    finally:
        lab.down()
    return name


def register(sub):
    """CLI: `seed-camera <save>` and `shot <lab> [--area | --at] ...`."""
    sc = sub.add_parser("seed-camera", help="write <save>+cam: the save with the camera player parked in its booth")
    sc.add_argument("save")
    sh = sub.add_parser("shot", help="screenshot a lab through its camera and print the PNG path")
    sh.add_argument("name")
    where = sh.add_mutually_exclusive_group(required=True)
    where.add_argument("--area", help="x0,y0,x1,y1: fill the frame with this rectangle")
    where.add_argument("--at", help="x,y: centre of the frame")
    sh.add_argument("--zoom", type=float, default=1.0)
    sh.add_argument("--surface", default="nauvis")
    sh.add_argument("--info", action="store_true", help="draw entity info (alt mode)")
    sh.add_argument("--resolution", help="w,h for --at (default 1280,720)")

    def nums(text):
        return [float(v) for v in text.split(",")]

    def do_seed(a):
        print(seed(a.save))

    def do_shot(a):
        lab = Lab(a.name)
        if a.area:
            x0, y0, x1, y1 = nums(a.area)
            path = render(lab, area=((x0, y0), (x1, y1)), zoom=a.zoom, surface=a.surface, info=a.info)
        else:
            res = [int(v) for v in nums(a.resolution)] if a.resolution else None
            path = render(lab, position=nums(a.at), zoom=a.zoom, surface=a.surface, info=a.info, resolution=res)
        print(path)

    return {"seed-camera": do_seed, "shot": do_shot}
