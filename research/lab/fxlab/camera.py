"""Render camera for labs: a seat of role camera, a full-game client that takes screenshots for the lab.

The realm service starts the camera, parks its player in the lab mod's hidden booth with no character, and
writes its screenshots to the seat's output directory. Parked, it changes nothing the lab simulates once the save
already holds it (see `seed`). A first join into an unseeded save spawns a character and shifts unit numbers.
"""

import itertools
import math
import secrets
import shutil
import struct
import subprocess
import time

from .lab import SERVICE_DIR, SHARED, Lab, service

PLAYER = "fxcam"
CACHE = SERVICE_DIR / "output" / "camera-cache"
PX_PER_TILE = 32
MAX_SIDE = 4096
JOINS = {}  # lab world -> seconds the last attach took to reach InGame
DESYNC_MARKS = ("desync", "multiplayermanager failed", "received unexpected", "dropped", "crc mismatch",
                "keep up with the server")
SHOTS = itertools.count(1)


def seat(lab):
    """The lab's live camera seat as the service lists it, or None."""
    seats = service("seats", session_id=lab.sid).get("seats", [])
    return next((s for s in seats if s.get("role") == "camera" and s.get("status") not in ("stopped", "error")), None)


def container(lab):
    s = seat(lab)
    return s["container_name"] if s else None


def output(lab):
    """The host directory the camera writes its screenshots to."""
    s = seat(lab)
    if s is None:
        raise RuntimeError("lab has no camera; start it with camera=True")
    return SERVICE_DIR / "output" / "seats" / s["seat_id"]


def attach(lab):
    """Join the camera seat and wait until it is parked in the booth. Returns the seconds the join took."""
    t0 = time.time()
    service("join", timeout=400, session_id=lab.sid, role="camera")
    JOINS[lab.world] = round(time.time() - t0, 1)
    return JOINS[lab.world]


def detach(lab, missing_ok=False):
    """Leave the camera seat."""
    s = seat(lab)
    if s is None:
        if not missing_ok:
            raise RuntimeError(f"{lab.world}: no camera attached")
        return
    service("leave", seat_id=s["seat_id"])


def ensure(lab):
    """Rejoin the camera when its client left the game. Raises when the lab never had one."""
    s = seat(lab)
    if s is None:
        raise RuntimeError("lab has no camera; start it with camera=True")
    if not (s.get("container_running") and s.get("connected")):
        service("rejoin", timeout=3700, seat_id=s["seat_id"])


def desyncs(lab):
    """Log lines of the camera client and the server that name a desync or a drop of the camera."""
    seen = []
    for name in filter(None, (container(lab), lab.container)):
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
    """Take a screenshot with the camera and return the PNG path in the camera's output once the file stops growing.

    Give `area` as ((x0, y0), (x1, y1)) to fill the frame with it, or `position` and optionally `resolution`.
    """
    if area is not None:
        position, resolution = frame(area, zoom)
    elif position is None:
        raise ValueError("render needs area or position")
    ensure(lab)
    path = f"fxlab/shot-{lab.tick()}-{_nonce()}.png"
    r = lab.sbx("view_shot", surface=surface, position=list(position), zoom=zoom, info=bool(info),
                resolution=list(resolution or (1280, 720)), path=path)
    return _wait_png(output(lab) / r["path"], timeout)


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
