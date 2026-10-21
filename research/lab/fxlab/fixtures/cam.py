"""Fixtures for the render camera: a real shot, a hidden-surface shot, its lifecycle rules, and the determinism check behind F8."""

import json
import struct
import subprocess
import threading
import time
import zlib

from .. import camera
from ..lab import SHARED
from .registry import Result, fixture

CAM_DIR = camera.CONFIG.parent
MODULE_AREA = ((111, -40), (153, -14))
SEEDED_FROM = "run4-closeout"
TARGET_STEP = 7200
SLOW_SPEED = 1000
PAUSE_DEADLINE = 900


@fixture(source="run4-closeout", tags={"cam"}, camera=True)
def cam_shot(lab):
    t0 = time.time()
    path = camera.render(lab, area=MODULE_AREA, zoom=1, info=True)
    shot_s = round(time.time() - t0, 2)
    want, got = camera.frame(MODULE_AREA)[1], camera.png_size(path)
    size = path.stat().st_size
    data = {"join_s": camera.JOINS.get(lab.container), "shot_s": shot_s, "bytes": size, "px": got}
    ok = size > 50_000 and got == want
    return Result(ok, f"{path.name} {got} (want {want}) {size // 1000} kB in {shot_s}s", data=data)


@fixture(source="create", tags={"cam"}, camera=True)
def cam_hidden_surface(lab):
    lab.sbx("sandbox_new", name="v")
    lab.lua('''
local s = game.surfaces["sbx-v"]
s.request_to_generate_chunks({0, 0}, 1)
s.force_generate_chunk_requests()
local f = game.forces["sbx-v"]
for i = -4, 4 do s.create_entity{name = "transport-belt", position = {i + 0.5, 0.5}, direction = defines.direction.east, force = f} end
s.create_entity{name = "iron-chest", position = {-5.5, -3.5}, force = f}
s.create_entity{name = "assembling-machine-1", position = {0.5, -3.5}, force = f}
s.create_entity{name = "inserter", position = {-2.5, -3.5}, direction = defines.direction.east, force = f}
''')
    area = ((-8, -8), (8, 8))
    path = camera.render(lab, area=area, surface="sbx-v", info=True)
    size, got, want = path.stat().st_size, camera.png_size(path), camera.frame(area)[1]
    return Result(got == want and size > 5_000, f"{path.name} {got} {size // 1000} kB", data={"bytes": size, "px": got})


@fixture(source="create", tags={"cam"})
def cam_render_needs_camera(lab):
    """render on a lab that never had a camera raises and starts none."""
    try:
        camera.render(lab, position=(0, 0))
    except RuntimeError as exc:
        err = str(exc)
    else:
        return Result(False, "render returned without a camera")
    started = camera.container(lab) in running_names()
    return Result("lab has no camera; start it with camera=True" in err and not started, f"{err!r} started={started}")


def _leftovers(lab):
    cam, net = camera.container(lab), camera.network(lab)
    names = subprocess.run(["docker", "ps", "-a", "--format", "{{.Names}}"], capture_output=True, text=True).stdout.split()
    nets = subprocess.run(["docker", "network", "ls", "--format", "{{.Name}}"], capture_output=True, text=True).stdout.split()
    return [n for n in (cam, net) if n in names + nets] + (["marker"] if camera._marker(lab).exists() else [])


@fixture(source="create", tags={"cam"})
def cam_attach_cleans_up(lab):
    """A failed attach leaves no network, container or marker: a failing docker run, and a client that never joins."""
    real = camera.docker

    def failing_run(*args, **kw):
        if args[0] == "run":
            raise RuntimeError("docker run: injected failure")
        return real(*args, **kw)

    camera.docker = failing_run
    try:
        try:
            camera.attach(lab)
        except RuntimeError as exc:
            run_err = str(exc)
        else:
            return Result(False, "attach survived a failing docker run")
    finally:
        camera.docker = real
    after_run = _leftovers(lab)
    try:
        camera.attach(lab, timeout=3)
    except RuntimeError as exc:
        join_err = str(exc)
    else:
        return Result(False, "attach reached InGame in 3 s")
    after_join = _leftovers(lab)
    ok = "injected" in run_err and "did not reach InGame" in join_err and not after_run and not after_join
    return Result(ok, f"leftovers after failed run {after_run}, after failed join {after_join}")


def _blank_png(w, h):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    rows = (b"\x00" + b"\x00\x00\x00" * w) * h
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


@fixture(source="create", tags={"cam"}, camera=True)
def cam_no_stale_shot(lab):
    """A PNG already at the shot's path is never returned, and two shots never share a path."""
    decoy = _blank_png(320, 180)
    stale = lab.output / "fxlab/shot-111-decoy.png"
    seed_file = lab.dir / "decoy.png"
    seed_file.write_bytes(decoy)
    subprocess.run(["docker", "exec", lab.container, "mkdir", "-p", "/opt/factorio/script-output/fxlab"], check=True)
    subprocess.run(["docker", "cp", str(seed_file), f"{lab.container}:/opt/factorio/script-output/fxlab/shot-111-decoy.png"],
                   check=True)
    assert stale.read_bytes() == decoy
    real, camera._nonce, lab.tick = camera._nonce, lambda: "decoy", lambda: 111
    try:
        path = camera.render(lab, position=(0, 0), resolution=(320, 180))
    finally:
        camera._nonce = real
        del lab.tick
    fresh = path == stale and path.read_bytes() != decoy and camera.png_size(path) == (320, 180)
    a = camera.render(lab, position=(0, 0), resolution=(320, 180))
    b = camera.render(lab, position=(0, 0), resolution=(320, 180))
    return Result(fresh and a != b, f"decoy replaced={fresh}, paths differ={a != b}")


@fixture(source="create", tags={"cam"}, camera=True)
def cam_cache_readonly(lab):
    """The sprite caches are mounted read-only and the join leaves them untouched."""
    cam = camera.container(lab)
    mounts = subprocess.run(["docker", "inspect", "-f", "{{range .Mounts}}{{.Destination}}={{.RW}} {{end}}", cam],
                            capture_output=True, text=True).stdout.split()
    rw = dict(m.split("=") for m in mounts)
    stats = {n: (camera.CACHE / n).stat() for n in ("atlas-cache.dat", "crop-cache.dat")}
    ro = all(rw.get(f"/opt/factorio/{n}") == "false" for n in stats)
    return Result(ro, f"mounts {rw}, join {camera.JOINS.get(lab.container)}s",
                  data={"join_s": camera.JOINS.get(lab.container), "atlas_bytes": stats["atlas-cache.dat"].st_size})


def fingerprint(lab):
    """Run to the next multiple-of-7200 tick past the next one, pause there, and fingerprint the world."""
    target = (lab.tick() // TARGET_STEP + 2) * TARGET_STEP
    lab.lua(f"script.on_nth_tick({target}, function() game.tick_paused = true script.on_nth_tick({target}, nil) end)")
    cpu, done = {}, threading.Event()

    def watch():
        names = [lab.container] + ([camera.container(lab)] if camera.container(lab) in running_names() else [])
        while not done.is_set():
            for name in names:
                out = subprocess.run(["docker", "stats", "--no-stream", "--format", "{{.CPUPerc}}", name],
                                     capture_output=True, text=True).stdout.strip()
                if out:
                    cpu.setdefault(name, []).append(float(out.rstrip("%")))

    thread = threading.Thread(target=watch)
    thread.start()
    t0 = time.time()
    start = lab.tick()
    lab.lua(f"game.speed = {SLOW_SPEED} game.tick_paused = false")
    try:
        while lab.lua("rcon.print(tostring(game.tick_paused))").strip() != "true":
            if time.time() - t0 > PAUSE_DEADLINE:
                raise RuntimeError(f"lab did not pause at tick {target} within {PAUSE_DEADLINE}s (tick {lab.tick()})")
            time.sleep(0.2)
    finally:
        done.set()
        thread.join()
    wall = time.time() - t0
    lab.lua("game.speed = 1")
    fp = json.loads(lab.lua((CAM_DIR / "fpall.lua").read_text()))
    fine = json.loads(lab.lua((CAM_DIR / "fpfine.lua").read_text()))
    fp.update({"fine_" + k: v for k, v in fine.items()})
    return {"target": target, "fp": fp, "ups": round((fp["tick"] - start) / wall),
            "cpu": {n: round(sum(v) / len(v)) for n, v in cpu.items()}}


def running_names():
    return subprocess.run(["docker", "ps", "--format", "{{.Names}}"], capture_output=True, text=True).stdout.split()


@fixture(source=SEEDED_FROM, tags={"cam", "fidelity", "slow"})
def cam_fidelity(lab):
    """F8: the world at an exact tick is identical with and without the camera connected."""
    seeded = f"{SEEDED_FROM}+cam"
    lab.down()
    if not (SHARED / "_saves" / f"{seeded}.zip").exists():
        camera.seed(SEEDED_FROM)
    arms = {}
    for arm, with_camera in (("A", False), ("B", True)):
        lab.up(save=seeded, camera=with_camera)
        try:
            arms[arm] = fingerprint(lab)
            if with_camera:
                arms[arm]["camera_running"] = camera._running(camera.container(lab))
                arms[arm]["camera_connected"] = lab.lua(
                    f'local p = game.players["{camera.PLAYER}"] rcon.print(tostring(p ~= nil and p.connected))').strip() == "true"
                arms[arm]["desyncs"] = camera.desyncs(lab)
        finally:
            lab.down()
    a, b = arms["A"]["fp"], arms["B"]["fp"]
    diff = {k: (a[k], b[k]) for k in a if k != "connected" and a[k] != b.get(k)}
    b_arm = arms["B"]
    ok = (not diff and a["tick"] == b["tick"] == arms["A"]["target"] and b_arm["camera_running"]
          and b_arm["camera_connected"] and not b_arm["desyncs"])
    data = {"cpu": {"A": arms["A"]["cpu"], "B": arms["B"]["cpu"]}, "ups": {"A": arms["A"]["ups"], "B": arms["B"]["ups"]},
            "tick": a["tick"], "diff": diff, "camera_connected": b_arm["camera_connected"], "desyncs": b_arm["desyncs"]}
    cam_cpu = next((v for k, v in arms["B"]["cpu"].items() if k.endswith("-cam")), None)
    note = "" if b_arm["camera_connected"] else "; camera NOT connected at the end"
    note += f"; desync lines: {b_arm['desyncs'][:3]}" if b_arm["desyncs"] else ""
    return Result(ok, f"tick {a['tick']}, " + (f"differs: {diff}" if diff else "identical") +
                  f"; camera {cam_cpu}% cpu" + note, data=data)
