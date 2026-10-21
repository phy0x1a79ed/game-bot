"""Module bench: rate a design on a slice, with its inputs supplied and its outputs voided.

`bench` clones a rectangle of a world onto a sandbox (or stamps a blueprint first), closes every port, runs
a warm-up and a measured window, and returns the bench record of CONTRACT.md. The rates are what the module
makes per minute when nothing upstream or downstream binds it. Compare them with what the same module
delivers in the base: the gap is supply.
"""

import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from .lab import SbxError

HERE = Path(__file__).resolve().parent
CORPUS = HERE.parent / "fidelity" / "modules.json"
TICKS_PER_MIN = 3600
BELT_TYPES = ["transport-belt", "underground-belt", "splitter", "loader", "loader-1x1", "linked-belt"]

SNAPSHOT = """
local B = helpers.json_to_table([==[%s]==])
local s = game.surfaces[B.surface]
local st = game.forces[B.force].get_item_production_statistics(s)
local machines, drills = {}, {}
local function products(list)
  local out = {}
  for _, p in ipairs(list) do
    if p.type ~= "fluid" then
      out[#out + 1] = {name = p.name, amount = p.amount, amount_min = p.amount_min, amount_max = p.amount_max,
                       probability = p.probability}
    end
  end
  return out
end
for _, e in pairs(s.find_entities_filtered{type = {"assembling-machine", "furnace", "mining-drill"}}) do
  if e.type == "mining-drill" then
    local t = e.mining_target
    if t then
      local m = t.prototype.mineable_properties
      drills[#drills + 1] = {speed = e.prototype.mining_speed * (1 + e.speed_bonus), bonus = e.productivity_bonus,
                             time = m.mining_time, products = products(m.products or {})}
    end
  else
    local r = e.get_recipe() or (e.previous_recipe and prototypes.recipe[e.previous_recipe.name])
    if r then
      machines[#machines + 1] = {id = e.unit_number, recipe = r.name, finished = e.products_finished,
                                 speed = e.crafting_speed, bonus = e.productivity_bonus, energy = r.energy,
                                 products = products(r.products)}
    end
  end
end
rcon.print(helpers.table_to_json{tick = game.tick, made = st.input_counts, used = st.output_counts,
                                 machines = machines, drills = drills})
"""

FEEDS = """
local B = helpers.json_to_table([==[%s]==])
local s = game.surfaces[B.surface]
local out = {}
for i, p in ipairs(B.feeds) do
  local why
  local c = p.closer
  if c and s.count_entities_filtered{name = c.name, position = c.at, radius = c.radius} == 0 then
    why = "closer gone"
  elseif p.kind == "belt" then
    local n = 0
    for _, e in pairs(s.find_entities_filtered{position = p.position, type = B.belt_types}) do
      for l = 1, e.get_max_transport_line_index() do n = n + #e.get_transport_line(l) end
    end
    if n == 0 then why = "empty" end
  end
  if why then out[#out + 1] = {i = i, why = why} end
end
rcon.print(helpers.table_to_json(out))
"""

STAMP = """
local B = helpers.json_to_table([==[%s]==])
local inv = game.create_inventory(1)
local stack = inv[1]
if stack.import_stack(B.blueprint) == 1 then inv.destroy() error("the blueprint string did not import") end
local planned = stack.get_blueprint_entities()
if not planned then inv.destroy() error("the blueprint holds no entities") end
local lo, hi = {1e9, 1e9}, {-1e9, -1e9}
for _, e in ipairs(planned) do
  lo = {math.min(lo[1], e.position.x), math.min(lo[2], e.position.y)}
  hi = {math.max(hi[1], e.position.x), math.max(hi[2], e.position.y)}
end
local s = game.create_surface(B.surface, {width = 2000, height = 2000})
s.generate_with_lab_tiles = true
s.always_day = true
s.request_to_generate_chunks({0, 0}, math.ceil(math.max(hi[1] - lo[1], hi[2] - lo[2]) / 64) + 3)
s.force_generate_chunk_requests()
local ghosts = stack.build_blueprint{surface = s, force = "player", position = {0, 0}, build_mode = defines.build_mode.forced}
local glo = {1e9, 1e9}
for _, g in pairs(ghosts) do
  if g.type == "entity-ghost" then glo = {math.min(glo[1], g.position.x), math.min(glo[2], g.position.y)} end
end
for _, g in pairs(ghosts) do if g.valid then g.revive() end end
local box = {1e9, 1e9, -1e9, -1e9}
local n = 0
for _, e in pairs(s.find_entities_filtered{force = "player"}) do
  if e.type ~= "entity-ghost" then
    n = n + 1
    local b = e.bounding_box
    box = {math.min(box[1], b.left_top.x), math.min(box[2], b.left_top.y),
           math.max(box[3], b.right_bottom.x), math.max(box[4], b.right_bottom.y)}
  end
end
local left = #s.find_entities_filtered{type = "entity-ghost"}
inv.destroy()
local function half(v) return math.floor(v * 2 + 0.5) / 2 end
rcon.print(helpers.table_to_json{dx = half(glo[1] - lo[1]), dy = half(glo[2] - lo[2]), entities = n, ghosts_left = left,
  box = {math.floor(box[1]), math.floor(box[2]), math.ceil(box[3]), math.ceil(box[4])}})
"""

CROSSINGS = """
local B = helpers.json_to_table([==[%s]==])
local s = game.surfaces[B.surface]
local R = B.rect
local V = {[0] = {0, -1}, [4] = {1, 0}, [8] = {0, 1}, [12] = {-1, 0}}
local BELTS = {"transport-belt", "underground-belt"}
local problems = {}
local function inside(x, y) return x >= R[1] and x <= R[3] and y >= R[2] and y <= R[4] end
local function tile(x, y) return {math.floor(x) + 0.5, math.floor(y) + 0.5} end
local function fail(p, why) problems[#problems + 1] = string.format("%%s port at (%%s, %%s): %%s", p.kind, p.position[1], p.position[2], why) end
local function fluid_entity(pos)
  for _, e in pairs(s.find_entities_filtered{position = pos}) do if e.fluids_count > 0 then return e end end
end
for _, p in ipairs(B.ports) do
  if p.kind == "belt" then
    local e = s.find_entities_filtered{position = p.position, type = BELTS}[1]
    if not e then fail(p, "no belt there")
    else
      local v, sign = V[e.direction], p.role == "feed" and -1 or 1
      local out = {p.position[1] + sign * v[1], p.position[2] + sign * v[2]}
      if inside(out[1], out[2]) then fail(p, "not on the edge of the rectangle")
      else
        local b = s.find_entities_filtered{position = out, type = BELTS}[1]
        if not b then
          b = s.create_entity{name = e.type == "transport-belt" and e.name or "transport-belt", position = out,
                              direction = e.direction, force = "player"}
        end
        if not b then fail(p, "no room for the crossing belt")
        elseif p.role == "feed" then
          local items = p.items or {}
          for lane = 1, 2 do
            local item = items[math.min(lane, #items)]
            if item then b.get_transport_line(lane).insert_at_back{name = item, count = 1} end
          end
        end
      end
    end
  elseif p.kind == "pipe" or p.kind == "tank" then
    local e = fluid_entity(p.position)
    if not e then fail(p, "no fluid entity there")
    else
      local out = {}
      for i = 1, e.fluids_count do
        for _, pc in pairs(e.get_fluid_box_pipe_connections(i)) do
          local t = pc.target_position
          if not inside(t.x, t.y) then out[#out + 1] = {t.x, t.y} end
        end
      end
      if #out ~= 1 then fail(p, #out .. " connections lead out of the rectangle")
      else
        local c = fluid_entity(out[1]) or s.create_entity{name = "pipe", position = out[1], force = "player"}
        if not c then fail(p, "no room for the crossing pipe")
        elseif p.role == "feed" then c.set_fluid(1, {name = p.fluid, amount = 100}) end
      end
    end
  elseif p.kind == "inserter" then
    local e = s.find_entities_filtered{position = p.position, type = "inserter"}[1]
    if not e then fail(p, "no inserter there")
    else
      local at = p.role == "feed" and e.pickup_position or e.drop_position
      if inside(at.x, at.y) then fail(p, "the inserter does not reach out of the rectangle")
      else
        local c = s.find_entities_filtered{position = at, type = "container"}[1]
          or s.create_entity{name = "iron-chest", position = tile(at.x, at.y), force = "player"}
        if not c then fail(p, "no room for the crossing chest")
        elseif p.role == "feed" then
          for _, item in ipairs(p.items or {}) do c.insert{name = item, count = 200} end
        end
      end
    end
  elseif p.kind ~= "power" then
    fail(p, "unsupported kind")
  end
end
rcon.print(helpers.table_to_json(problems))
"""


def lua_value(v):
    """Python value as a Lua literal."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ", ".join(lua_value(x) for x in v) + "}"
    return "{" + ", ".join(f"[{json.dumps(k)}] = {lua_value(x)}" for k, x in v.items()) + "}"


def _listing(x):
    return list(x) if x else []


def _lua_json(lab, template, **args):
    return json.loads(lab.lua(template % json.dumps(args)))


def _snapshot(lab, name):
    return _lua_json(lab, SNAPSHOT, surface=f"sbx-{name}", force=f"sbx-{name}")


def _expected(product):
    amount = product.get("amount")
    if amount is None:
        amount = (product["amount_min"] + product["amount_max"]) / 2
    return amount * (product.get("probability") or 1)


def _feed_items(port):
    if port.get("fluid"):
        return [port["fluid"]]
    items = list(port.get("items") or [])
    for lane in _listing(port.get("lanes")):
        items += _listing(lane)
    return sorted(set(items))


def _closer_probe(port):
    """The entity whose absence means the port has lost its supply: a name, a place and a search radius."""
    if port["kind"] == "power":
        return {"name": "electric-energy-interface", "at": port["position"], "radius": 1.5}
    if port.get("pipe"):
        return {"name": "infinity-pipe", "at": port["pipe"], "radius": 0.6}
    if port.get("chest"):
        return {"name": "infinity-chest", "at": port["chest"], "radius": 0.6}
    near = port.get("tee") or port.get("load")
    if near and not port.get("scripted"):
        return {"name": "infinity-chest", "at": near, "radius": 3.5}
    return None


def _starved(feeds, probes):
    """Feed ports flagged starved at the slice, plus any whose closer is gone or whose belt tile was empty at the last sample."""
    why = {i: "no supply at the source" for i, p in enumerate(feeds) if p.get("starved")}
    for hit in probes[-1] if probes else []:
        why.setdefault(hit["i"] - 1, hit["why"])
    return [{"position": feeds[i]["position"], "kind": feeds[i]["kind"], "items": _feed_items(feeds[i]), "why": w}
            for i, w in sorted(why.items())]


def _rates(first, last, minutes):
    names = set(last["made"]) | set(last["used"])
    net = {n: ((last["made"].get(n, 0) - first["made"].get(n, 0))
               - (last["used"].get(n, 0) - first["used"].get(n, 0))) / minutes for n in names}
    return {n: round(v, 2) for n, v in sorted(net.items()) if abs(v) >= 0.005}


def _utilisation(first, last, ticks):
    """Per recipe, products finished over products possible. `products_finished` counts productivity bonus crafts."""
    before = {m["id"]: m["finished"] for m in first["machines"]}
    done, possible = {}, {}
    for m in last["machines"]:
        if m["id"] not in before or not m["energy"]:
            continue
        done[m["recipe"]] = done.get(m["recipe"], 0) + m["finished"] - before[m["id"]]
        possible[m["recipe"]] = possible.get(m["recipe"], 0) + m["speed"] * (1 + m["bonus"]) * ticks / (m["energy"] * 60)
    return {r: round(done[r] / possible[r], 3) for r in sorted(done) if possible[r] > 0}


def _ceiling(last):
    """Per item, per minute: every machine making it flat out, productivity included."""
    out = {}
    for m in last["machines"]:
        if not m["energy"]:
            continue
        per_min = m["speed"] * (1 + m["bonus"]) / m["energy"] * TICKS_PER_MIN / 60
        for p in _listing(m["products"]):
            out[p["name"]] = out.get(p["name"], 0) + per_min * _expected(p)
    for d in last["drills"]:
        per_min = d["speed"] * (1 + d["bonus"]) / d["time"] * 60
        for p in _listing(d["products"]):
            out[p["name"]] = out.get(p["name"], 0) + per_min * _expected(p)
    return {n: round(v, 2) for n, v in sorted(out.items())}


def _corpus_id(area):
    if not CORPUS.exists():
        return None
    for entry in json.loads(CORPUS.read_text()):
        if entry["area"] == [list(p) for p in area]:
            return entry["id"]
    return None


def _save_of(lab):
    saves = sorted(p.stem for p in lab.saves.glob("*.zip"))
    return ("create" if saves[0] == "world" else saves[0]) if len(saves) == 1 else None


def _commit():
    out = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=HERE, capture_output=True, text=True)
    return out.stdout.strip() or None


def _drop(lab, name):
    try:
        lab.sbx("slice_drop", name=name)
    except SbxError as exc:
        if exc.code != "not_found":
            raise


def _xy(position):
    return (position["x"], position["y"]) if isinstance(position, dict) else tuple(position)


def _cleanup(lab, name, surface, quiet=False):
    """Drop the slice and delete the stamp surface. With quiet, a failure here never hides the error being raised."""
    try:
        _drop(lab, name)
    except Exception:
        if not quiet:
            raise
    finally:
        if surface:
            try:
                lab.lua(f'game.delete_surface("{surface}")')
            except Exception:
                if not quiet:
                    raise


def _expect_ports(found, given):
    """Every given port must have a slice port of its role within a tile of it."""
    for g in given:
        if g["kind"] == "power":
            continue
        gx, gy = g["position"]
        if not any(p.get("role") == g["role"] and abs(p["position"]["x"] - gx) <= 1.5 and abs(p["position"]["y"] - gy) <= 1.5
                   for p in found):
            raise SbxError("bad_args", f"the slice found no {g['role']} port near {g['position']}: "
                           f"found {[(p.get('role'), p['position']['x'], p['position']['y']) for p in found]}")


def _measure(lab, area, name, minutes, warmup, mode, power, speed, source="nauvis", expect=()):
    """Build the slice, run it, and return the measurements of the record. The slice stays for the caller to drop."""
    built = lab.sbx("slice_build", name=name, area=[list(p) for p in area], source=source, research="copy")
    unhandled = _listing(built["unhandled"])
    if unhandled:
        raise SbxError("unhandled_ports", unhandled)
    ports = lab.sbx("slice_ports", name=name)
    _expect_ports(_listing(ports["ports"]), expect)
    feeds = [p for p in _listing(ports["ports"]) if p.get("role") == "feed"]
    probe = dict(surface=f"sbx-{name}", belt_types=BELT_TYPES,
                 feeds=[{"kind": p["kind"], "position": p["position"], "closer": _closer_probe(p)} for p in feeds])
    lab.advance(warmup * TICKS_PER_MIN, speed=speed)
    if mode == "standard":
        lab.sbx("sbx_mode", name=name, mode="standard", research="keep", power=power)
    first = _snapshot(lab, name)
    probes = []
    for _ in range(minutes):
        lab.advance(TICKS_PER_MIN, speed=speed)
        probes.append(_lua_json(lab, FEEDS, **probe))
    last = _snapshot(lab, name)
    ticks = last["tick"] - first["tick"]
    return {
        "ticks": ticks,
        "rates": _rates(first, last, ticks / TICKS_PER_MIN),
        "utilisation": _utilisation(first, last, ticks),
        "ceiling": _ceiling(last),
        "starved": _starved(feeds, [_listing(p) for p in probes]),
    }


def bench(lab, area=None, save=None, blueprint=None, ports=None, minutes=10, warmup=3, mode="god", name=None,
          speed=1000.0, power="keep"):
    """Rate a module and return its bench record.

    The subject is a rectangle of the lab's world (`area` as ((x0, y0), (x1, y1)); `save` names the world for the
    record) or a blueprint string with its `ports`. A slice with unhandled ports raises
    SbxError("unhandled_ports", list). mode="standard" cuts the item and fluid supply after the
    warm-up; `power` ("keep" or "cut") says whether the slice's energy interface stays.
    A blueprint is stamped on a fresh surface of the lab, see `stamp` for `area` and `ports`. It starts with empty
    belts and buffers, so give it a longer warm-up than a slice of a running base: about 8 minutes for red/green.
    """
    if mode not in ("god", "standard"):
        raise ValueError(f"mode {mode!r}: god or standard")
    if power not in ("keep", "cut"):
        raise ValueError(f"power {power!r}: keep or cut")
    name = name or "bench"
    surface, source, expect = None, "nauvis", ()
    try:
        if blueprint is not None:
            surface, area, expect = stamp(lab, blueprint, ports or [], area, name)
            source = surface
            subject = {"blueprint": blueprint}
        elif area is None:
            raise ValueError("bench needs an area or a blueprint")
        else:
            subject = {"area": [list(p) for p in area], "save": save or _save_of(lab)}
        measured = _measure(lab, area, name, minutes, warmup, mode, power, speed, source, expect)
    except BaseException:
        _cleanup(lab, name, surface, quiet=True)
        raise
    _cleanup(lab, name, surface)
    return {
        "subject": subject,
        "mode": mode,
        "power": power,
        "warmup_min": warmup,
        "minutes": minutes,
        **measured,
        "unhandled": [],
        "fidelity": {"corpus": None if blueprint is not None else _corpus_id(area), "f1": None},
        "commit": _commit(),
        "stamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def stamp(lab, blueprint, ports, area, name):
    """Build a blueprint on a fresh lab-tile surface and give each port a crossing the slice can see.

    `ports` are `{position, kind, role, items | fluid}` in the frame of the blueprint's entities, which is the
    frame of the world it was captured from, so `slice_ports` entries of the source work as they are. A belt or
    pipe port gets one belt or pipe just outside the rectangle (a feed carries its items, one item per lane or
    one item on both lanes, or its fluid; a drain stays empty); an inserter port gets a chest. `area` is the
    rectangle to rate in the same frame; without it the rectangle is the bounding box of the stamped entities.
    Returns the surface, the rectangle on it and the ports in the frame of the surface.
    """
    surface = f"bench-{name}-{time.monotonic_ns() % 10**9}"
    try:
        placed = _lua_json(lab, STAMP, surface=surface, blueprint=blueprint)
    except Exception:
        lab.lua(f'if game.surfaces["{surface}"] then game.delete_surface("{surface}") end')
        raise
    try:
        dx, dy = placed["dx"], placed["dy"]
        if placed["ghosts_left"]:
            raise SbxError("bad_args", f"{placed['ghosts_left']} blueprint entities could not be built")
        if area is None:
            rect = placed["box"]
        else:
            (x0, y0), (x1, y1) = area
            rect = [x0 + dx, y0 + dy, x1 + dx, y1 + dy]
        moved = [{**p, "position": [_xy(p["position"])[0] + dx, _xy(p["position"])[1] + dy]} for p in ports]
        problems = _listing(_lua_json(lab, CROSSINGS, surface=surface, rect=rect, ports=moved))
        if problems:
            raise SbxError("bad_args", "; ".join(problems))
    except Exception:
        lab.lua(f'game.delete_surface("{surface}")')
        raise
    return surface, [[rect[0], rect[1]], [rect[2], rect[3]]], moved


def register(sub):
    p = sub.add_parser("bench", help="rate the module in a rectangle on a slice; prints the bench record as JSON")
    p.add_argument("name")
    for k in ("x0", "y0", "x1", "y1"):
        p.add_argument(k, type=float)
    p.add_argument("--minutes", type=int, default=10)
    p.add_argument("--warmup", type=int, default=3)
    p.add_argument("--mode", choices=("god", "standard"), default="god")
    p.add_argument("--power", choices=("keep", "cut"), default="keep")

    def run(a):
        from .lab import Lab
        record = bench(Lab(a.name), ((a.x0, a.y0), (a.x1, a.y1)), minutes=a.minutes, warmup=a.warmup, mode=a.mode,
                       power=a.power)
        print(json.dumps(record, indent=1))

    return {"bench": run}
