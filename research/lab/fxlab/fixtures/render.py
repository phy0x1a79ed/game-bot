"""Fixtures for slice and blueprint renders. Owned by scope fxlab-render (T16)."""

import json
import struct
import time
import zlib
from pathlib import Path

from .. import camera, render
from ..lab import SbxError
from .registry import Result, fixture
from .slice import RED_GREEN

SEEDED = "run4-closeout+cam"
SAMPLE = (900, 600)
MIN_COLOURS = 200

CAPTURE = """
local s = game.surfaces[{surface}]
local inv = game.create_inventory(1)
inv[1].set_stack{{name = "blueprint"}}
inv[1].create_blueprint{{surface = s, force = "player", area = {area}, include_trains = true}}
rcon.print(helpers.table_to_json({{bp = inv[1].export_stack(), n = inv[1].get_blueprint_entity_count()}}))
inv.destroy()
"""

BUILD_SAMPLE = """
local s = game.surfaces.nauvis
local f = game.forces.player
local function put(name, x, y, dir, extra)
  local t = {name = name, position = {x, y}, direction = dir, force = f}
  for k, v in pairs(extra or {}) do t[k] = v end
  assert(s.create_entity(t), name)
end
local E, S = defines.direction.east, defines.direction.south
for i = 0, 7 do put("transport-belt", 20.5 + i, 20.5, E) end
put("underground-belt", 28.5, 20.5, E, {type = "input"})
put("underground-belt", 31.5, 20.5, E, {type = "output"})
put("splitter", 32.5, 21, E)
put("iron-chest", 18.5, 20.5)
put("inserter", 19.5, 20.5, E)
put("assembling-machine-1", 24.5, 24.5, nil, {recipe = "iron-gear-wheel"})
put("inserter", 24.5, 22.5, S)
for i = 0, 3 do put("pipe", 30.5 + i, 26.5) end
put("small-electric-pole", 27.5, 22.5)
put("steel-furnace", 34.0, 25.0)
"""
SAMPLE_AREA = [[16, 16], [40, 32]]


def png_colours(path, rows=SAMPLE[1], cols=SAMPLE[0]):
    """Distinct pixels in the top-left rows x cols window of an 8-bit RGB or RGBA PNG.

    Unfiltering needs only the row above and the pixel to the left, so the window decodes without the rest.
    """
    data = Path(path).read_bytes()
    pos, idat = 8, b""
    while pos < len(data):
        size, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + size]
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or ctype not in (2, 6) or interlace:
                raise ValueError(f"unsupported PNG: depth {depth} type {ctype} interlace {interlace}")
        elif kind == b"IDAT":
            idat += body
        pos += 12 + size
    bpp = 3 if ctype == 2 else 4
    stride = w * bpp
    raw = zlib.decompress(idat)
    rows, width = min(rows, h), min(cols, w) * bpp
    seen, prev = set(), bytearray(width)
    for y in range(rows):
        start = y * (stride + 1)
        ftype, line = raw[start], raw[start + 1:start + 1 + width]
        out = bytearray(width)
        for x in range(width):
            a = out[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            v = line[x]
            if ftype == 1:
                v += a
            elif ftype == 2:
                v += b
            elif ftype == 3:
                v += (a + b) >> 1
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                v += a if pa <= pb and pa <= pc else b if pb <= pc else c
            out[x] = v & 255
        prev = out
        seen.update(bytes(out[i:i + bpp]) for i in range(0, width, bpp))
    return len(seen)


def _capture(lab, surface, area):
    """A blueprint string of a rectangle and its entity count."""
    out = lab.lua(CAPTURE.format(surface=json.dumps(surface), area=json.dumps(area).replace("[", "{").replace("]", "}")))
    got = json.loads(out)
    return got["bp"], got["n"]


def _camera_state(lab):
    connected = lab.lua(f'local p = game.players["{camera.PLAYER}"] rcon.print(tostring(p ~= nil and p.connected))').strip()
    return connected == "true", camera.desyncs(lab)


def _check_png(res):
    path = Path(res["path"])
    size = camera.png_size(path)
    colours = png_colours(path)
    return {"exists": path.exists(), "px": size, "colours": colours,
            "bytes": path.stat().st_size, "resolution_ok": size == tuple(res["resolution"])}


def _shot_ok(check):
    return check["exists"] and check["resolution_ok"] and check["colours"] >= MIN_COLOURS


@fixture(source=SEEDED, tags={"render"}, camera=True)
def render_slice_redgreen(lab):
    """A slice of the red/green module renders at its auto zoom: right size, not blank, camera still a peer."""
    lab.sbx("slice_build", name="rg", area=RED_GREEN)
    t0 = time.time()
    res = render.render_slice(lab, "rg", info=True)
    shot_s = round(time.time() - t0, 2)
    check = _check_png(res)
    connected, bad = _camera_state(lab)
    data = {"shot_s": shot_s, "zoom": res["zoom"], "resolution": res["resolution"], "path": res["path"],
            "desyncs": bad[:5], **check}
    ok = _shot_ok(check) and res["surface"] == "sbx-rg" and connected and not bad
    return Result(ok, f"{Path(res['path']).name} {check['px']} zoom {res['zoom']} {check['bytes'] // 1000} kB, "
                      f"{check['colours']} colours in {shot_s}s; connected {connected}, desync lines {len(bad)}", data=data)


@fixture(source=SEEDED, tags={"render"}, camera=True)
def render_blueprint_redgreen(lab):
    """The red/green rect captured as a blueprint string stamps with nothing left over and renders."""
    bp, n = _capture(lab, "nauvis", RED_GREEN)
    t0 = time.time()
    res = render.render_blueprint(lab, bp)
    shot_s = round(time.time() - t0, 2)
    check = _check_png(res)
    connected, bad = _camera_state(lab)
    data = {"shot_s": shot_s, "blueprint_entities": n, "built": res["built"], "tiles": res["tiles"],
            "left": res["left"][:5], "zoom": res["zoom"], "resolution": res["resolution"], "path": res["path"],
            "desyncs": bad[:5], **check}
    ok = not res["left"] and res["built"] == n and _shot_ok(check) and connected and not bad
    return Result(ok, f"built {res['built']}/{n}, left {len(res['left'])}; {Path(res['path']).name} {check['px']} "
                      f"zoom {res['zoom']} {check['bytes'] // 1000} kB, {check['colours']} colours in {shot_s}s",
                  data=data)


def _stamp_surface_exists(lab):
    return lab.lua(f'rcon.print(tostring(game.surfaces["{render.STAMP_SURFACE}"] ~= nil))').strip() == "true"


@fixture(source="create", tags={"render"}, camera=True)
def render_blueprint_bad(lab):
    """A bad string fails with bad_args and leaves no bp-view surface behind."""
    good, n = _sample(lab)
    book = lab.lua('local inv = game.create_inventory(1) inv[1].set_stack{name = "blueprint-book"} '
                   'rcon.print(inv[1].export_stack()) inv.destroy()').strip()
    cases = {"empty": "", "garbage": "not a blueprint", "truncated": good[: len(good) // 2],
             "book": book, "padded": "0" + good[:40]}
    codes = {}
    for label, bp in cases.items():
        try:
            lab.sbx("view_stamp", blueprint=bp)
        except SbxError as exc:
            codes[label] = exc.code
        else:
            codes[label] = "accepted"
    try:
        lab.sbx("view_stamp", blueprint=good, surface="nauvis")
    except SbxError as exc:
        codes["nauvis"] = exc.code
    else:
        codes["nauvis"] = "accepted"
    left_behind = _stamp_surface_exists(lab)
    after = lab.sbx("view_stamp", blueprint=good)
    lab.sbx("sandbox_new", name="adopt", inplace={"surface": render.STAMP_SURFACE, "force": "player"})
    try:
        lab.sbx("view_stamp", blueprint=good)
    except SbxError as exc:
        codes["adopted"] = exc.code
    else:
        codes["adopted"] = "accepted"
    ok = all(c == "bad_args" for c in codes.values()) and not left_behind and after["built"] == n
    return Result(ok, f"codes {codes}; surface left behind {left_behind}; good stamp after: {after['built']}/{n}",
                  data={"codes": codes})


def _sample(lab):
    lab.lua(BUILD_SAMPLE)
    return _capture(lab, "nauvis", SAMPLE_AREA)


def _surface_records(lab, surface):
    out = lab.lua(
        f'local s = game.surfaces["{surface}"] local r = {{}} '
        'for _, e in pairs(s.find_entities()) do r[#r + 1] = e.name .. "@" .. e.position.x .. "," .. e.position.y '
        '.. ":" .. e.direction end table.sort(r) rcon.print(helpers.table_to_json(r))')
    return json.loads(out)


TILE_BP = """
local inv = game.create_inventory(1)
inv[1].set_stack{name = "blueprint"}
local tiles = {}
for x = 0, 3 do for y = 0, 3 do tiles[#tiles + 1] = {name = "concrete", position = {x, y}} end end
inv[1].set_blueprint_tiles(tiles)
rcon.print(inv[1].export_stack())
inv.destroy()
"""
CONCRETE = ('rcon.print(#game.surfaces["bp-view"].find_tiles_filtered{{name = "concrete"}})')


def _concrete_is_reset(lab, bp):
    """A tile stamp lays concrete, and the next clearing stamp puts the lab tiles back without killing a character."""
    tile_bp = lab.lua(TILE_BP).strip()
    lab.sbx("view_stamp", blueprint=tile_bp, clear=True)
    laid = int(lab.lua(CONCRETE.format()))
    lab.lua('game.surfaces["bp-view"].create_entity{name = "character", position = {40, 40}, force = "player"}')
    lab.sbx("view_stamp", blueprint=bp, clear=True)
    left = int(lab.lua(CONCRETE.format()))
    kept = lab.lua('rcon.print(tostring(#game.surfaces["bp-view"].find_entities_filtered{type = "character"} == 1))')
    return laid, left, kept.strip() == "true"


@fixture(source="create", tags={"render"}, camera=True)
def render_stamp_deterministic(lab):
    """Two stamps with clear leave the same entities at the same positions, and the camera peer sees no desync."""
    bp, n = _sample(lab)
    first = lab.sbx("view_stamp", blueprint=bp, clear=True)
    records_a = _surface_records(lab, render.STAMP_SURFACE)
    second = lab.sbx("view_stamp", blueprint=bp, clear=True)
    records_b = _surface_records(lab, render.STAMP_SURFACE)
    res = render.render_blueprint(lab, bp)
    lab.advance(120)
    records_c = _surface_records(lab, render.STAMP_SURFACE)
    clean = _concrete_is_reset(lab, bp)
    connected, bad = _camera_state(lab)
    check = _check_png(res)
    same = records_a == records_b and first["area"] == second["area"] and len(records_a) == n
    ok = same and len(records_c) == n and not first["left"] and not second["left"] and connected and not bad \
        and _shot_ok(check) and clean == (16, 0, True)
    return Result(ok, f"{len(records_a)}/{len(records_b)} entities of {n}, identical {records_a == records_b}, "
                      f"area {first['area']}; concrete/after clear/character kept {clean}; "
                      f"connected {connected}, desync lines {len(bad)}; shot {check['colours']} colours",
                  data={"area": first["area"], "desyncs": bad[:5], **check})
