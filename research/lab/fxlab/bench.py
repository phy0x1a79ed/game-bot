"""Module bench: rate a design on a slice, with its inputs supplied and its outputs voided.

`bench` clones a rectangle of a world onto a sandbox (or stamps a blueprint first), closes every port, runs
a warm-up and a measured window, and returns the bench record of CONTRACT.md. The rates are what the module
makes per minute when nothing upstream or downstream binds it. Compare them with what the same module
delivers in the base: the gap is supply.
"""

import json
import subprocess
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
    local r = e.get_recipe() or e.previous_recipe
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
    before = {m["id"]: m["finished"] for m in first["machines"]}
    done, possible = {}, {}
    for m in last["machines"]:
        if m["id"] not in before or not m["energy"]:
            continue
        done[m["recipe"]] = done.get(m["recipe"], 0) + m["finished"] - before[m["id"]]
        possible[m["recipe"]] = possible.get(m["recipe"], 0) + m["speed"] * ticks / (m["energy"] * 60)
    return {r: round(min(1.0, done[r] / possible[r]), 3) for r in sorted(done) if possible[r] > 0}


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


def _measure(lab, area, name, minutes, warmup, mode, speed):
    """Build the slice, run it, and return the measurements of the record. The slice stays for the caller to drop."""
    built = lab.sbx("slice_build", name=name, area=[list(p) for p in area], source="nauvis", research="copy")
    unhandled = _listing(built["unhandled"])
    if unhandled:
        raise SbxError("unhandled_ports", unhandled)
    ports = lab.sbx("slice_ports", name=name)
    feeds = [p for p in _listing(ports["ports"]) if p.get("role") == "feed"]
    probe = dict(surface=f"sbx-{name}", belt_types=BELT_TYPES,
                 feeds=[{"kind": p["kind"], "position": p["position"], "closer": _closer_probe(p)} for p in feeds])
    lab.advance(warmup * TICKS_PER_MIN, speed=speed)
    if mode == "standard":
        lab.sbx("sbx_mode", name=name, mode="standard", research="keep")
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
          speed=1000.0):
    """Rate a module and return its bench record.

    The subject is a rectangle of the lab's world (`area` as ((x0, y0), (x1, y1)); `save` names the world for the
    record) or a blueprint string with its `ports`. A slice with unhandled ports raises
    SbxError("unhandled_ports", list). mode="standard" cuts the supply and the power after the warm-up.
    """
    if mode not in ("god", "standard"):
        raise ValueError(f"mode {mode!r}: god or standard")
    name = name or "bench"
    if blueprint is not None:
        area = stamp(lab, blueprint, ports, name)
        subject = {"blueprint": blueprint}
    elif area is None:
        raise ValueError("bench needs an area or a blueprint")
    else:
        subject = {"area": [list(p) for p in area], "save": save or _save_of(lab)}
    try:
        measured = _measure(lab, area, name, minutes, warmup, mode, speed)
    finally:
        _drop(lab, name)
    return {
        "subject": subject,
        "mode": mode,
        "warmup_min": warmup,
        "minutes": minutes,
        **measured,
        "unhandled": [],
        "fidelity": {"corpus": _corpus_id(area), "f1": None},
        "commit": _commit(),
        "stamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def stamp(lab, blueprint, ports, name):
    """Build a blueprint on empty ground of a created world and return its rectangle, ports made into crossings."""
    raise NotImplementedError


def register(sub):
    p = sub.add_parser("bench", help="rate the module in a rectangle on a slice; prints the bench record as JSON")
    p.add_argument("name")
    for k in ("x0", "y0", "x1", "y1"):
        p.add_argument(k, type=float)
    p.add_argument("--minutes", type=int, default=10)
    p.add_argument("--warmup", type=int, default=3)
    p.add_argument("--mode", choices=("god", "standard"), default="god")

    def run(a):
        from .lab import Lab
        record = bench(Lab(a.name), ((a.x0, a.y0), (a.x1, a.y1)), minutes=a.minutes, warmup=a.warmup, mode=a.mode)
        print(json.dumps(record, indent=1))

    return {"bench": run}
