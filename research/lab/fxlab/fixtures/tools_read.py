"""Fixtures for the read tools under research/tools/read/. Owned by scope fxlab-tools-read (T12).

Each fixture loads the tools it needs, calls them in a lab with the camera as a second peer, and compares the
replies with ground truth that plain Lua reads from the game. A call must leave the world as it found it.
"""

import json
import re

from .. import camera, tools
from ..lab import SbxError
from .registry import Result, fixture

TAGS = {"tools", "read"}
RUN4 = "run4-closeout+cam"
MIN_MOD = (0, 6, 1)

STAMP = """
local s = game.surfaces["%s"]
local n, items, decon, ghosts, belt = 0, 0, 0, 0, 0
for _, e in pairs(s.find_entities_filtered{force = "player"}) do
  n = n + 1
  if e.type == "entity-ghost" then ghosts = ghosts + 1
  else
    items = items + e.get_item_count()
    if e.type == "transport-belt" then belt = belt + e.get_transport_line(1).get_item_count() + e.get_transport_line(2).get_item_count() end
  end
  if e.to_be_deconstructed() then decon = decon + 1 end
end
rcon.print(helpers.table_to_json{n = n, items = items, decon = decon, ghosts = ghosts, belt = belt})
"""


def jlua(lab, code):
    return json.loads(lab.lua(code))


def lst(x):
    """An empty Lua list arrives as {}."""
    return list(x) if x else []


def call(lab, tool, /, **args):
    """Run a library tool. Returns (reply, bytes), the bytes being what the game prints for the whole tool_call reply."""
    src = json.dumps({"name": tool, "args": args})
    out = lab.lua('rcon.print(helpers.table_to_json(remote.call("game_bot", "tool_call", '
                  f'helpers.json_to_table([==[{src}]==]))))')
    reply = json.loads(out)
    if not reply.get("ok"):
        raise SbxError(reply.get("error", "error"), reply.get("detail", ""))
    return reply["r"], len(out)


def pages(lab, tool, /, **args):
    """Every page of a paged tool at the largest page size. Returns (replies, total bytes)."""
    replies, size, offset = [], 0, 0
    while True:
        r, n = call(lab, tool, limit=300, offset=offset, **args)
        replies.append(r)
        size += n
        if not r.get("more"):
            return replies, size
        offset = r["next"]


def stamp(lab, surface="nauvis"):
    return jlua(lab, STAMP % surface)


def sync(lab, *names):
    """Define the named tools and the libs they use. Returns None, or the version of a game-bot-control with no tool registry."""
    version = lab.lua('rcon.print(script.active_mods["game-bot-control"])').strip()
    if tuple(int(p) for p in version.split(".")) < MIN_MOD:
        return version
    tools.sync(lab, names=list(names), root=tools.TOOLS)
    return None


def case(tool_names, surface="nauvis", build=None):
    """Wrap a check function: sync the tools, run it, and add the shared checks.

    `build(lab)` sets the world up first. `surface` is the one the world check reads. The check takes (lab, bad, data) and appends a sentence to `bad` for every failed expectation.
    The world must be unchanged afterwards, the camera still connected and no desync logged.
    """
    def wrap(check):
        def run(lab):
            old = sync(lab, *tool_names)
            if old:
                return Result(False, f"game-bot-control {old} has no tool registry; set FXLAB_GBC_MOD")
            if build:
                build(lab)
            before, bad, data = stamp(lab, surface), [], {}
            detail = check(lab, bad, data)
            after = stamp(lab, surface)
            if before != after:
                bad.append(f"the world changed: {before} -> {after}")
            lab.advance(120)
            connected = lab.lua('local p = game.players["fxcam"] rcon.print(tostring(p and p.connected))').strip()
            desyncs = camera.desyncs(lab)
            if connected != "true":
                bad.append("the camera is not connected")
            if desyncs:
                bad.append(f"{len(desyncs)} desync lines")
                data["desyncs"] = desyncs[:5]
            return Result(not bad, "; ".join(bad) if bad else detail, data=data)
        run.__name__ = run.__qualname__ = check.__name__
        run.__doc__ = check.__doc__
        return run
    return wrap


def same(bad, what, got, want):
    if got != want:
        bad.append(f"{what}: got {got}, want {want}")
    return got == want


# -- look --

LOOK_AREA = dict(x0=100, y0=-40, x1=160, y1=10)

LOOK_TRUTH = """
local s = game.surfaces.nauvis
local a = {{%(x0)s, %(y0)s}, {%(x1)s, %(y1)s}}
local names, ghosts, ins, first_ghost = {}, 0, {}, nil
for _, e in pairs(s.find_entities_filtered{area = a, force = "player"}) do
  if e.type == "entity-ghost" then ghosts = ghosts + 1
  else
    names[e.name] = (names[e.name] or 0) + 1
    if e.type == "inserter" then
      ins[#ins + 1] = {e.name, e.position.x, e.position.y, e.pickup_position.x, e.pickup_position.y,
        e.drop_position.x, e.drop_position.y}
    end
  end
end
local g = s.find_entities_filtered{name = "entity-ghost", force = "player", limit = 1}[1]
rcon.print(helpers.table_to_json{names = names, ghosts = ghosts, inserters = ins, ghost = g and {g.position.x, g.position.y}})
"""


@fixture(RUN4, tags=TAGS, camera=True)
@case(["look"])
def tools_read_look(lab, bad, data):
    """look counts, filters, pages and inserter pickup and drop positions match plain Lua on the run4 base."""
    truth = jlua(lab, LOOK_TRUTH % LOOK_AREA)
    total = sum(truth["names"].values())
    counted, size = call(lab, "look", count=True, **LOOK_AREA)
    same(bad, "counts per name", counted["counts"], truth["names"])
    same(bad, "total with ghosts", counted["total"], total + truth["ghosts"])
    full, size_full = pages(lab, "look", **LOOK_AREA)
    ents = [e for r in full for e in lst(r["entities"])]
    same(bad, "full list length", len(ents), total + truth["ghosts"])
    same(bad, "pages", [r["total"] for r in full], [total + truth["ghosts"]] * len(full))
    first, _ = call(lab, "look", limit=7, **LOOK_AREA)
    second, _ = call(lab, "look", limit=7, offset=7, **LOOK_AREA)
    same(bad, "first page cut", (first.get("more"), first.get("next"), first["total"]), (True, 7, total + truth["ghosts"]))
    same(bad, "pages follow the full list", lst(first["entities"]) + lst(second["entities"]), ents[:14])
    only, _ = call(lab, "look", ghosts=False, count=True, **LOOK_AREA)
    same(bad, "ghosts = false", only["total"], total)
    kinds, _ = call(lab, "look", type="inserter", limit=300, **LOOK_AREA)
    kinds_of = sorted({row[0] for row in truth["inserters"]})
    named, _ = call(lab, "look", name=kinds_of, count=True, **LOOK_AREA)
    same(bad, "type = inserter count", kinds["total"], len(truth["inserters"]))
    same(bad, "name list count", named["total"], len(truth["inserters"]))
    got = sorted((e["name"], e["x"], e["y"], *e["pickup"], *e["drop"]) for e in lst(kinds["entities"]))
    want = sorted((n, round(x, 2), round(y, 2), round(px, 2), round(py, 2), round(dx, 2), round(dy, 2))
                  for n, x, y, px, py, dx, dy in truth["inserters"])
    same(bad, "inserter pickup and drop", got, want)
    if "dir" in (kinds["entities"][0] if lst(kinds["entities"]) else {}):
        bad.append("an inserter record carries dir, which means its pickup side")
    gx, gy = truth["ghost"]
    box = dict(x0=gx - 12, y0=gy - 12, x1=gx + 12, y1=gy + 12)
    ghost_truth = jlua(lab, LOOK_TRUTH % box)
    ghosts, _ = call(lab, "look", ghosts=True, limit=300, **box)
    same(bad, "ghosts = true", (ghosts["total"], all(e.get("ghost") for e in lst(ghosts["entities"]))),
         (ghost_truth["ghosts"], True))
    if not ghost_truth["ghosts"]:
        bad.append("the ghost box held no ghost")
    data["bytes_60x50_in_pages"] = size_full
    data["bytes_count"] = size
    return f"{total + truth['ghosts']} entities, {len(truth['inserters'])} inserters; all pages {size_full} B, count {size} B"


# -- inventory --

INV_TRUTH = """
local s = game.surfaces.nauvis
local a = {{%(x0)s, %(y0)s}, {%(x1)s, %(y1)s}}
local totals, rows, belt = {}, 0, {}
for _, e in pairs(s.find_entities_filtered{area = a, force = "player"}) do
  if e.type == "transport-belt" or e.type == "underground-belt" or e.type == "splitter" then
    for i = 1, e.get_max_transport_line_index() do
      for _, c in pairs(e.get_transport_line(i).get_contents()) do belt[c.name] = (belt[c.name] or 0) + c.count end
    end
  elseif e.type ~= "entity-ghost" and e.type ~= "construction-robot" and e.type ~= "logistic-robot" then
    local trash = e.type == "logistic-container" and 2 or 8
    local any = false
    for i = 1, e.get_max_inventory_index() do
      local inv = e.get_inventory(i)
      if inv and i ~= trash then
        for _, c in pairs(inv.get_contents()) do totals[c.name] = (totals[c.name] or 0) + c.count any = true end
      end
    end
    if any then rows = rows + 1 end
  end
end
rcon.print(helpers.table_to_json{totals = totals, rows = rows, belt = belt})
"""

SPOTS = """
local s = game.surfaces.nauvis
local out = {}
for _, t in ipairs{"steel-furnace", "boiler", "storage-chest", "lab", "gun-turret"} do
  local e = s.find_entities_filtered{name = t, force = "player", limit = 1}[1]
  if e then out[#out + 1] = {t, e.position.x, e.position.y} end
end
for _, e in pairs(s.find_entities_filtered{name = "assembling-machine-2", force = "player"}) do
  if not e.get_inventory(defines.inventory.crafter_input).is_empty() then
    out[#out + 1] = {"assembling-machine-2", e.position.x, e.position.y}
    break
  end
end
rcon.print(helpers.table_to_json(out))
"""


def around(x, y, r=8):
    return dict(x0=x - r, y0=y - r, x1=x + r, y1=y + r)


def row_total(rows):
    """Items held by the rows of an inventory reply: every dict field is an item -> count table."""
    return sum(sum(v.values()) for e in lst(rows) for v in e.values() if isinstance(v, dict))


def merged(*tables):
    out = {}
    for t in tables:
        for k, v in t.items():
            out[k] = out.get(k, 0) + v
    return out


@fixture(RUN4, tags=TAGS, camera=True)
@case(["inventory"])
def tools_read_inventory(lab, bad, data):
    """inventory sums, rows, one machine's kinds, the item filter and belt contents match a scan of every inventory."""
    spots = jlua(lab, SPOTS)
    areas = [LOOK_AREA] + [around(x, y) for _, x, y in spots]
    rows_seen = sizes = 0
    for area in areas:
        truth = jlua(lab, INV_TRUTH % area)
        total, size = call(lab, "inventory", sum=True, **area)
        same(bad, f"totals {area}", total["totals"], truth["totals"])
        listed, size_rows = call(lab, "inventory", limit=300, **area)
        same(bad, f"rows {area}", listed["total"], truth["rows"])
        same(bad, f"sum of rows {area}", row_total(listed["entities"]), sum(truth["totals"].values()))
        with_belts, _ = call(lab, "inventory", sum=True, belts=True, **area)
        same(bad, f"totals with belts {area}", with_belts["totals"], merged(truth["totals"], truth["belt"]))
        rows_seen += truth["rows"]
        sizes = max(sizes, size_rows)
    name, x, y = next(s for s in spots if s[0] == "assembling-machine-2")
    one, _ = call(lab, "inventory", x=x, y=y)
    row = lst(one["entities"])[0]
    want = jlua(lab, f"""
local e = game.surfaces.nauvis.find_entities_filtered{{name = "{name}", position = {{{x}, {y}}}, radius = 0.5}}[1]
local function items(i) local t = {{}} local inv = e.get_inventory(i) for _, c in pairs(inv.get_contents()) do t[c.name] = c.count end return t end
rcon.print(helpers.table_to_json{{input = items(defines.inventory.crafter_input), output = items(defines.inventory.crafter_output)}})
""")
    for kind in ("input", "output"):
        same(bad, f"machine {kind}", row.get(kind) or {}, want[kind] or {})
    plate = [k for k in jlua(lab, INV_TRUTH % LOOK_AREA)["totals"] if k.endswith("plate")][:1]
    if plate:
        only, _ = call(lab, "inventory", sum=True, item=plate, **LOOK_AREA)
        same(bad, "item filter", only["totals"], {plate[0]: jlua(lab, INV_TRUTH % LOOK_AREA)["totals"][plate[0]]})
    nothing, _ = call(lab, "inventory", x=-5000, y=-5000)
    if "error" not in nothing:
        bad.append("an empty point returned no error")
    data["bytes_rows_16x16_max"] = sizes
    return f"{len(areas)} areas, {rows_seen} stocked machines; largest row list {sizes} B"


# -- status --

BASE = dict(x0=-500, y0=-400, x1=600, y1=330)
MACHINES = ["assembling-machine", "furnace", "lab", "mining-drill", "boiler", "generator", "reactor",
            "burner-generator", "rocket-silo"]

STATUS_TRUTH = """
local s = game.surfaces.nauvis
local ST = {} for k, v in pairs(defines.entity_status) do ST[v] = k end
local counts = {}
for _, e in pairs(s.find_entities_filtered{area = {{%(x0)s, %(y0)s}, {%(x1)s, %(y1)s}}, force = "player",
    type = helpers.json_to_table([==[%(types)s]==])}) do
  local st = e.status and ST[e.status] or "unknown"
  counts[st] = (counts[st] or 0) + 1
end
rcon.print(helpers.table_to_json(counts))
"""

# Each listed machine is found again. Its recipe must match, every missing item must be short, and no item
# the record leaves out may be short.
MISSING_CHECK = """
local s = game.surfaces.nauvis
local recs = helpers.json_to_table([==[%s]==])
local bad, checked = {}, 0
for _, r in ipairs(recs) do
  local e = s.find_entities_filtered{name = r.name, position = {r.x, r.y}, radius = 0.5, force = "player"}[1]
  if not e then bad[#bad + 1] = r.name .. " is gone"
  else
    local recipe = (e.type == "assembling-machine" or e.type == "furnace") and e.get_recipe()
    if (recipe and recipe.name or nil) ~= r.recipe then bad[#bad + 1] = r.name .. " recipe " .. tostring(recipe and recipe.name) end
    if recipe and r.missing then
      local inv = e.get_inventory(defines.inventory.crafter_input)
      local short = {}
      for _, ing in ipairs(recipe.ingredients) do
        if ing.type == "item" then short[ing.name] = inv.get_item_count(ing.name) < ing.amount end
      end
      for _, m in ipairs(r.missing) do
        if short[m] == false then bad[#bad + 1] = r.name .. " is not short of " .. m end
      end
      local named = {}
      for _, m in ipairs(r.missing) do named[m] = true end
      for item, is_short in pairs(short) do
        if is_short and not named[item] then bad[#bad + 1] = r.name .. " is short of " .. item .. " but not told" end
      end
      checked = checked + 1
    end
  end
end
rcon.print(helpers.table_to_json{bad = bad, checked = checked})
"""


def merged_groups(replies):
    out = {}
    for r in replies:
        for status, records in r["groups"].items():
            out.setdefault(status, []).extend(lst(records))
    return out


@fixture(RUN4, tags=TAGS, camera=True)
@case(["status"])
def tools_read_status(lab, bad, data):
    """status counts every machine by status and names the recipe and the short inputs of each one that is idle."""
    truth = jlua(lab, STATUS_TRUTH % dict(BASE, types=json.dumps(MACHINES)))
    every, size = pages(lab, "status", working=True, **BASE)
    same(bad, "counts per status", every[0]["counts"], truth)
    groups = merged_groups(every)
    listed = sum(len(v) for v in groups.values())
    same(bad, "listed machines", (every[0]["total"], listed), (sum(truth.values()), sum(truth.values())))
    same(bad, "working group", len(groups.get("working", [])), truth.get("working", 0))
    idle_pages, size_idle = pages(lab, "status", **BASE)
    idle = {"total": idle_pages[0]["total"], "groups": merged_groups(idle_pages)}
    same(bad, "idle listing leaves out working", "working" in idle["groups"], False)
    records = [rec for group in idle["groups"].values() for rec in group if "missing" in rec]
    check = jlua(lab, MISSING_CHECK % json.dumps(records))
    for line in lst(check["bad"])[:5]:
        bad.append(line)
    if not records:
        bad.append("no idle machine named a missing input")
    page, _ = call(lab, "status", limit=5, offset=2, **BASE)
    same(bad, "page", (sum(len(v) for v in page["groups"].values()), page.get("more"), page["total"]),
         (5, True, idle["total"]))
    only, _ = call(lab, "status", type="lab", **BASE)
    same(bad, "type filter", only["counts"], jlua(lab, STATUS_TRUTH % dict(BASE, types='["lab"]')))
    data.update(bytes_all=size, bytes_idle=size_idle, idle=idle["total"], names_missing=check["checked"])
    return (f"{sum(truth.values())} machines, {idle['total']} idle, {check['checked']} with missing inputs checked; "
            f"idle list {size_idle} B in {len(idle_pages)} pages")


# -- power --

POWER_TRUTH = """
local s = game.surfaces.nauvis
local a = {{%(x0)s, %(y0)s}, {%(x1)s, %(y1)s}}
local kw, engines, poles, weak = 0, 0, 0, 0
local ST = {} for k, v in pairs(defines.entity_status) do ST[v] = k end
local MACHINES = {}
for _, t in ipairs{"assembling-machine", "furnace", "lab", "mining-drill", "roboport", "radar", "pump",
    "beacon", "electric-turret", "lamp", "rocket-silo", "agricultural-tower"} do MACHINES[t] = true end
for _, e in pairs(s.find_entities_filtered{area = a, force = "player"}) do
  if e.type == "generator" then kw = kw + e.energy_generated_last_tick * 60 / 1000 engines = engines + 1 end
  if e.type == "electric-pole" then poles = poles + 1 end
  local st = e.status and ST[e.status]
  if MACHINES[e.type] and (st == "no_power" or st == "low_power") then weak = weak + 1 end
end
local boilers, fuel, mj, working = 0, {}, 0, 0
for _, e in pairs(s.find_entities_filtered{area = a, force = "player", type = "boiler"}) do
  boilers = boilers + 1
  if e.status == defines.entity_status.working then working = working + 1 end
  local inv = e.get_fuel_inventory()
  for i = 1, #inv do
    local st = inv[i]
    if st.valid_for_read then
      fuel[st.name] = (fuel[st.name] or 0) + st.count
      mj = mj + st.count * st.prototype.fuel_value / 1e6
    end
  end
  mj = mj + e.burner.remaining_burning_fuel / 1e6
end
rcon.print(helpers.table_to_json{kw = kw, engines = engines, poles = poles, weak = weak, boilers = boilers,
  fuel = fuel, mj = mj, working = working})
"""


@fixture(RUN4, tags=TAGS, camera=True)
@case(["power"])
def tools_read_power(lab, bad, data):
    """power matches the steam engines' output, the poles, the boilers' fuel and the weak-power count of the run4 base."""
    truth = jlua(lab, POWER_TRUTH % BASE)
    r, size = call(lab, "power", **BASE)
    nets = lst(r["networks"])
    produced = sum(n["produced_kw"] for n in nets)
    if abs(produced - truth["kw"]) > 0.01 * max(truth["kw"], 1):
        bad.append(f"produced {produced:.0f} kW, the engines made {truth['kw']:.0f} kW")
    same(bad, "poles", sum(n["poles"] for n in nets), truth["poles"])
    same(bad, "steam engines", sum(n.get("generators", {}).get("steam-engine", 0) for n in nets), truth["engines"])
    same(bad, "weak machines", sum(n.get("no_power", 0) + n.get("low_power", 0) for n in nets)
         + r.get("unconnected", {}).get("n", 0), truth["weak"])
    for n in nets:
        if not 0 <= n["satisfaction"] <= 1 or n["capacity_kw"] < n["produced_kw"] - 0.5:
            bad.append(f"network {n['id']}: satisfaction {n['satisfaction']}, {n['produced_kw']} of {n['capacity_kw']} kW")
    b = r.get("boilers") or {}
    same(bad, "boilers", (b.get("n"), b.get("working")), (truth["boilers"], truth["working"]))
    same(bad, "boiler fuel", b.get("fuel"), truth["fuel"])
    if abs(b.get("fuel_mj", 0) - truth["mj"]) > 0.5:
        bad.append(f"fuel {b.get('fuel_mj')} MJ, want {truth['mj']:.1f}")
    if b.get("working") and abs(b["minutes_left"] - b["fuel_mj"] / (1.8 * b["working"] * 60)) > 0.02:
        bad.append(f"minutes_left {b['minutes_left']} does not follow from the fuel and 1.8 MW a boiler")
    none, _ = call(lab, "power", x0=-5000, y0=-5000, x1=-4990, y1=-4990)
    same(bad, "an area without poles", (lst(none["networks"]), none["total"], "boilers" in none), ([], 0, False))
    data.update(bytes_base=size, kw=truth["kw"], boilers=truth["boilers"])
    return f"{len(nets)} network, {produced:.0f} kW; {truth['boilers']} boilers with {truth['mj']:.0f} MJ; {size} B"


# -- fixtures that build their own world, on a flat concrete surface called rk --

ARENA = """
local s = game.surfaces["%(surface)s"] or game.create_surface("%(surface)s", {width = 128, height = 128, peaceful_mode = true, no_enemies_mode = true})
s.request_to_generate_chunks({0, 0}, 2)
s.force_generate_chunk_requests()
local tiles = {}
for x = -40, 39 do for y = -40, 39 do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end end
s.set_tiles(tiles)
for _, e in pairs(s.find_entities_filtered{}) do e.destroy() end
s.always_day = true
local D = defines.direction
local function mk(t)
  t.force = t.force or "player"
  local e = s.create_entity(t)
  assert(e, "create failed: " .. t.name .. " at " .. serpent.line(t.position))
  return e
end
"""


def arena(lab, build="", surface="rk"):
    """Make the flat surface (rk unless named) and run `build` Lua on it, with `s`, `D` and `mk{...}` in scope."""
    lab.lua((ARENA % {"surface": surface}) + build)


# -- belt_trace --

# east along y 0.5, turn south at x -0.5, an underground pair, a splitter, two branches, and a separate ring
BELTS = """
local function put(name, x, y, d) return mk{name = name, position = {x, y}, direction = d} end
for x = -10.5, -1.5 do put("transport-belt", x, 0.5, D.east) end
for y = 0.5, 4.5 do put("transport-belt", -0.5, y, D.south) end
put("underground-belt", -0.5, 5.5, D.south)
mk{name = "underground-belt", position = {-0.5, 9.5}, direction = D.south, type = "output"}
put("transport-belt", -0.5, 10.5, D.south)
mk{name = "splitter", position = {0, 11.5}, direction = D.south}
for y = 12.5, 15.5 do put("transport-belt", -0.5, y, D.south) end
mk{name = "iron-chest", position = {-0.5, 16.5}}
put("transport-belt", 0.5, 12.5, D.south)
put("transport-belt", 0.5, 13.5, D.south)
for x = 0.5, 4.5 do put("transport-belt", x, 14.5, D.east) end
put("transport-belt", 10.5, 0.5, D.east)
put("transport-belt", 11.5, 0.5, D.south)
put("transport-belt", 11.5, 1.5, D.west)
put("transport-belt", 10.5, 1.5, D.north)
mk{name = "iron-chest", position = {-5.5, -1.5}}
mk{name = "inserter", position = {-5.5, -0.5}, direction = D.north}
mk{name = "inserter", position = {-3.5, 1.5}, direction = D.north}
mk{name = "iron-chest", position = {-3.5, 2.5}}
-- three iron plates on the left lane and two copper plates on the right lane of every belt of the first run
local function load(x, y)
  local b = s.find_entities_filtered{name = "transport-belt", position = {x, y}, radius = 0.1}[1]
  for k = 0, 2 do assert(b.get_transport_line(1).insert_at(0.15 + 0.25 * k, {name = "iron-plate"})) end
  for k = 0, 1 do assert(b.get_transport_line(2).insert_at(0.15 + 0.25 * k, {name = "copper-plate"})) end
end
for x = -10.5, -1.5 do load(x, 0.5) end
load(-0.5, 2.5)
local ug = s.find_entities_filtered{name = "underground-belt", position = {-0.5, 5.5}, radius = 0.1}[1]
rcon.print(tostring(ug.get_transport_line(3).insert_at_back{name = "coal"}))
"""

LANES_TRUTH = """
local s = game.surfaces.rk
local left, right = {}, {}
for _, e in pairs(s.find_entities_filtered{area = {{-12, -1}, {5, 17}}, type = {"transport-belt", "underground-belt", "splitter"}}) do
  for i = 1, e.get_max_transport_line_index() do
    local into = i % 2 == 1 and left or right
    for _, c in pairs(e.get_transport_line(i).get_contents()) do into[c.name] = (into[c.name] or 0) + c.count end
  end
end
rcon.print(helpers.table_to_json{left = left, right = right})
"""


def seg_view(seg):
    return (seg["kind"], seg["from"], seg["to"], seg["n"])


@fixture("create", tags=TAGS, camera=True)
@case(["belt_trace"], surface="rk", build=lambda lab: arena(lab, BELTS))
def tools_read_belt_trace(lab, bad, data):
    """belt_trace follows a belt through a turn, an underground and a splitter, finds the ends, loop and cap."""
    truth = jlua(lab, LANES_TRUTH)
    r, size = call(lab, "belt_trace", x=-10.5, y=0.5, surface="rk", taps=True)
    segs = lst(r["segments"])
    want = [("belt", [-10.5, 0.5], [-1.5, 0.5], 10), ("belt", [-0.5, 0.5], [-0.5, 4.5], 5),
            ("underground", [-0.5, 5.5], [-0.5, 9.5], 2), ("belt", [-0.5, 10.5], [-0.5, 10.5], 1),
            ("splitter", [0, 11.5], [0, 11.5], 1), ("belt", [-0.5, 12.5], [-0.5, 15.5], 4),
            ("belt", [0.5, 12.5], [0.5, 13.5], 2), ("belt", [0.5, 14.5], [4.5, 14.5], 5)]
    same(bad, "segments", [seg_view(s) for s in segs], [(k, f, t, n) for k, f, t, n in want])
    same(bad, "tiles", r["tiles"], 30)
    parents = {s["id"]: s.get("parent") for s in segs}
    same(bad, "parents", [parents[s["id"]] for s in segs], [None, 1, 2, 3, 4, 5, 5, 7])
    same(bad, "directions", [s["dir"] for s in segs], ["east", "south", "south", "south", "south", "south", "south", "east"])
    ends = sorted((e["seg"], e["why"], e.get("faces")) for e in lst(r["ends"]))
    same(bad, "ends", ends, [(6, "end", "iron-chest"), (8, "end", None)])
    same(bad, "lanes", (r["lanes"]["left"], r["lanes"]["right"]), (truth["left"], truth["right"]))
    same(bad, "first run lanes", (segs[0]["left"], segs[0]["right"]), ({"iron-plate": 30}, {"copper-plate": 20}))
    taps = sorted((t["role"], t["x"], t["y"], t["seg"], t["other"]["name"]) for t in lst(r.get("taps")))
    same(bad, "taps", taps, [("drop", -5.5, -0.5, 1, "iron-chest"), ("pickup", -3.5, 1.5, 1, "iron-chest")])
    up, _ = call(lab, "belt_trace", x=-0.5, y=12.5, surface="rk", up=True)
    ups = lst(up["up"]["segments"])
    same(bad, "upstream segments", [seg_view(s) for s in ups],
         [("splitter", [0, 11.5], [0, 11.5], 1), ("belt", [-0.5, 10.5], [-0.5, 10.5], 1),
          ("underground", [-0.5, 5.5], [-0.5, 9.5], 2), ("belt", [-0.5, 0.5], [-0.5, 4.5], 5),
          ("belt", [-10.5, 0.5], [-1.5, 0.5], 10)])
    same(bad, "upstream ends", [(e["why"], e["x"], e["y"]) for e in lst(up["up"]["ends"])], [("end", -10.5, 0.5)])
    ring, _ = call(lab, "belt_trace", x=10.5, y=0.5, surface="rk")
    same(bad, "ring", (ring["tiles"], [e["why"] for e in lst(ring["ends"])]), (4, ["loop"]))
    cut, _ = call(lab, "belt_trace", x=-10.5, y=0.5, surface="rk", limit=5)
    same(bad, "cap", (cut["tiles"], [e["why"] for e in lst(cut["ends"])]), (5, ["cap"]))
    off, _ = call(lab, "belt_trace", x=20.5, y=20.5, surface="rk")
    if "error" not in off:
        bad.append("a point with no belt returned no error")
    data["bytes_trace"] = size
    return f"{r['tiles']} belts in {len(segs)} segments, {len(lst(r.get('taps')))} taps, reply {size} B"


# -- rate --

POWER = """
local eei = mk{name = "electric-energy-interface", position = {30, 30}}
eei.power_production = 1e8
eei.electric_buffer_size = 1e9
eei.energy = 1e9
s.create_global_electric_network()
"""

GEARS = POWER + """
mk{name = "iron-chest", position = {-6.5, 0.5}}.insert{name = "iron-plate", count = 2000}
mk{name = "inserter", position = {-5.5, 0.5}, direction = D.west}
mk{name = "assembling-machine-2", position = {-3.5, 0.5}}.set_recipe("iron-gear-wheel")
mk{name = "inserter", position = {-1.5, 0.5}, direction = D.west}
mk{name = "iron-chest", position = {-0.5, 0.5}}
"""

FINISHED = """
local a = game.surfaces.rk.find_entities_filtered{name = "assembling-machine-2"}[1]
rcon.print(a.products_finished)
"""


def gear_line(lab):
    arena(lab, GEARS)
    lab.advance(3600)


@fixture("create", tags=TAGS, camera=True)
@case(["rate"], surface="rk", build=gear_line)
def tools_read_rate(lab, bad, data):
    """rate reports the gears one assembler made in a minute, and the plates it used, over 1, 10 and 60 minutes."""
    made = int(lab.lua(FINISHED))
    r, size = call(lab, "rate", items=["iron-gear-wheel", "iron-plate", "water"], surface="rk")
    gears, plates = r["rates"]["iron-gear-wheel"], r["rates"]["iron-plate"]
    if made < 15:
        bad.append(f"the assembler finished only {made} gears in a minute")
    if abs(gears["made"][0] - made) > 3:
        bad.append(f"gears made per minute {gears['made'][0]}, the assembler finished {made}")
    if abs(plates["used"][0] - 2 * made) > 6:
        bad.append(f"plates used per minute {plates['used'][0]}, want about {2 * made}")
    for window, span in ((1, 10), (2, 60)):
        want = made / span
        if abs(gears["made"][window] - want) > max(1.0, 0.15 * want):
            bad.append(f"gears over {span} minutes: {gears['made'][window]}, want about {want:.1f}")
    same(bad, "windows", r["windows"], [1, 10, 60])
    same(bad, "a fluid with no flow", r["rates"]["water"], {"made": [0, 0, 0], "used": [0, 0, 0]})
    single, _ = call(lab, "rate", items="iron-gear-wheel", surface="rk")
    same(bad, "one name as a string", single["rates"]["iron-gear-wheel"], gears)
    data["bytes_3_items"] = size
    return f"{made} gears in a minute: made {gears['made']}, plates used {plates['used']} per minute; reply {size} B"


# -- resources --

ORE = """
local function patch(name, x0, y0, w, h, amount)
  for x = x0, x0 + w - 1 do
    for y = y0, y0 + h - 1 do mk{name = name, position = {x + 0.5, y + 0.5}, amount = amount, force = "neutral"} end
  end
end
patch("iron-ore", 2, 2, 6, 4, 1000)
patch("iron-ore", -38, 6, 4, 4, 300)
patch("coal", -10, -12, 3, 3, 500)
mk{name = "crude-oil", position = {30.5, -30.5}, amount = 300000, force = "neutral"}
mk{name = "electric-mining-drill", position = {3.5, 3.5}, direction = D.north}
mk{name = "electric-mining-drill", position = {6.5, 3.5}, direction = D.north}
mk{name = "electric-mining-drill", position = {-8.5, -10.5}, direction = D.north}
mk{name = "electric-mining-drill", position = {20.5, 20.5}, direction = D.north}
"""


def patch_view(p):
    return (p["name"], p["tiles"], p["amount"], p["x0"], p["y0"], p["x1"], p["y1"], p["drills"], p.get("infinite"))


@fixture("create", tags=TAGS, camera=True)
@case(["resources"], surface="rk", build=lambda lab: arena(lab, ORE))
def tools_read_resources(lab, bad, data):
    """resources groups ore tiles into patches, with amounts, tile boxes and the drills that mine each."""
    area = dict(x0=-40, y0=-40, x1=39, y1=39)
    r, size = call(lab, "resources", surface="rk", **area)
    got = [patch_view(p) for p in lst(r["patches"])]
    want = [("crude-oil", 1, 300000, 30, -31, 31, -30, 0, True), ("iron-ore", 24, 24000, 2, 2, 8, 6, 2, None),
            ("iron-ore", 16, 4800, -38, 6, -34, 10, 0, None), ("coal", 9, 4500, -10, -12, -7, -9, 1, None)]
    same(bad, "patches", got, want)
    same(bad, "total", r["total"], 4)
    coal, _ = call(lab, "resources", surface="rk", name="coal", **area)
    same(bad, "name filter", [patch_view(p) for p in lst(coal["patches"])], [want[3]])
    part, _ = call(lab, "resources", surface="rk", x0=0, y0=0, x1=10, y1=10)
    same(bad, "area filter", [patch_view(p) for p in lst(part["patches"])], [want[1]])
    page, _ = call(lab, "resources", surface="rk", limit=1, offset=1, **area)
    same(bad, "page", ([patch_view(p) for p in lst(page["patches"])], page.get("more"), page.get("next")), ([want[1]], True, 2))
    wrong, _ = call(lab, "resources", surface="rk", name="iron-chest", **area)
    if "error" not in wrong:
        bad.append("a name that is not an ore returned no error")
    data["bytes_4_patches"] = size
    return f"{r['total']} patches, reply {size} B"


# -- fluid --

PIPES = """
for x = 0, 9 do mk{name = "pipe", position = {x + 0.5, 0.5}} end
s.find_entities_filtered{name = "pipe", position = {4.5, 0.5}, radius = 0.1}[1].insert_fluid{name = "water", amount = 500}
for x = 0, 2 do mk{name = "pipe", position = {x + 0.5, 10.5}} end
s.find_entities_filtered{name = "pipe", position = {0.5, 10.5}, radius = 0.1}[1].insert_fluid{name = "crude-oil", amount = 150}
for x = 0, 1 do mk{name = "pipe", position = {x + 0.5, 20.5}} end
mk{name = "storage-tank", position = {20.5, 20.5}}.insert_fluid{name = "lubricant", amount = 5000}
"""


def segment_view(seg):
    return (seg.get("fluid"), seg["amount"], seg["capacity"], seg["n"], seg.get("partial"))


@fixture("create", tags=TAGS, camera=True)
@case(["fluid"], surface="rk", build=lambda lab: arena(lab, PIPES))
def tools_read_fluid(lab, bad, data):
    """fluid finds each connected pipe system with its fluid, amount, capacity, members and whether it leaves the area."""
    area = dict(x0=-5, y0=-5, x1=30, y1=30)
    r, size = call(lab, "fluid", surface="rk", **area)
    got = [segment_view(s) for s in lst(r["segments"])]
    want = [("lubricant", 5000, 25000, 1, None), ("water", 500, 1000, 10, None), ("crude-oil", 150, 300, 3, None),
            (None, 0, 200, 2, None)]
    same(bad, "segments", got, want)
    segs = lst(r["segments"])
    same(bad, "members", [s["entities"] for s in segs],
         [{"storage-tank": 1}, {"pipe": 10}, {"pipe": 3}, {"pipe": 2}])
    same(bad, "ends", [[e["name"] for e in lst(s["ends"])] for s in segs], [["storage-tank"], [], [], []])
    same(bad, "fill", [s["fill"] for s in segs], [0.2, 0.5, 0.5, 0])
    half, _ = call(lab, "fluid", surface="rk", x0=-5, y0=-5, x1=5, y1=5)
    same(bad, "an area cutting a segment", [segment_view(s) for s in lst(half["segments"])], [("water", 500, 1000, 5, True)])
    box = lst(half["segments"])[0]
    same(bad, "segment box", (box["x0"], box["y0"], box["x1"], box["y1"]), (0, 0, 10, 1))
    oil, _ = call(lab, "fluid", surface="rk", fluid="crude-oil", **area)
    same(bad, "fluid filter", [segment_view(s) for s in lst(oil["segments"])], [want[2]])
    wrong, _ = call(lab, "fluid", surface="rk", fluid="iron-plate", **area)
    if "error" not in wrong:
        bad.append("an item given as a fluid returned no error")
    data["bytes_4_segments"] = size
    return f"{r['total']} segments, reply {size} B"


# -- network --

PORT = POWER + """
local rp = mk{name = "roboport", position = {0, 0}}
rp.get_inventory(defines.inventory.roboport_robot).insert{name = "construction-robot", count = 4}
local chest = mk{name = "storage-chest", position = {6.5, 6.5}}
chest.insert{name = "iron-plate", count = 100}
chest.insert{name = "copper-plate", count = 50}
"""

NETWORK_TRUTH = """
local s = game.surfaces.rk
local rp = s.find_entities_filtered{name = "roboport"}[1]
local net = rp.logistic_network
rcon.print(helpers.table_to_json{id = net.network_id, robots = net.all_construction_robots,
  idle = net.available_construction_robots, cells = #net.cells, iron = net.get_item_count("iron-plate"),
  copper = net.get_item_count("copper-plate")})
"""


def port_up(lab):
    arena(lab, PORT)
    lab.advance(120)


@fixture("create", tags=TAGS, camera=True)
@case(["network"], surface="rk", build=port_up)
def tools_read_network(lab, bad, data):
    """network describes the robots, roboports and stock that cover a point, and names the nearest roboport when none does."""
    truth = jlua(lab, NETWORK_TRUTH)
    r, size = call(lab, "network", x=3, y=3, surface="rk")
    same(bad, "covered by the logistic area", (r["covered"], r["covers"]), (True, "logistic"))
    same(bad, "network", (r["id"], r["roboports"], r["construction_robots"], r["construction_idle"]),
         (truth["id"], truth["cells"], truth["robots"], truth["idle"]))
    same(bad, "robot counts", (r["construction_robots"], r["logistic_robots"]), (4, 0))
    same(bad, "storage", (r["storages"], r["requesters"]), (1, 0))
    same(bad, "items", r["items"], {"iron-plate": truth["iron"], "copper-plate": truth["copper"]})
    same(bad, "stock", (truth["iron"], truth["copper"]), (100, 50))
    far, _ = call(lab, "network", x=40, y=0, surface="rk")
    same(bad, "covered by the construction area only", (far["covered"], far.get("covers"), far.get("id")),
         (True, "construction", truth["id"]))
    none, _ = call(lab, "network", x=60.5, y=0, surface="rk")
    near = none.get("nearest") or {}
    same(bad, "nothing covers 60.5 tiles out", (none["covered"], near.get("x"), near.get("y"), near.get("distance")),
         (False, 0, 0, 60.5))
    top, _ = call(lab, "network", x=3, y=3, surface="rk", limit=1)
    same(bad, "item cap", (len(top["items"]), top["total"], top.get("more")), (1, 2, True))
    data["bytes_network"] = size
    return f"network {r['id']}: {r['roboports']} roboport, {r['construction_robots']} robots, reply {size} B"


# -- ascii_map --

# (entity, x, y, direction or None, expected character); a 3x3 or 2x1 entity fills the tiles it covers
LAYOUT = [
    ("transport-belt", 0, 1, "east", ">"), ("transport-belt", 1, 1, "east", ">"), ("transport-belt", 2, 1, "east", ">"),
    ("transport-belt", 3, 1, "north", "^"), ("transport-belt", 4, 1, "south", "v"), ("transport-belt", 5, 1, "west", "<"),
    ("inserter", 0, 3, "south", "N"), ("inserter", 1, 3, "north", "S"), ("inserter", 2, 3, "west", "E"),
    ("inserter", 3, 3, "east", "W"), ("iron-chest", 9, 3, None, "C"), ("small-electric-pole", 10, 3, None, "P"),
    ("pipe", 0, 6, None, "="), ("pipe", 1, 6, None, "="), ("pipe-to-ground", 2, 6, "east", "p"),
    ("underground-belt", 4, 6, "east", "U"), ("underground-belt-out", 6, 6, "east", "u"),
]
BIG = [(6, 3, 3, 3, "A"), (8, 6, 1, 2, "Y")]
ORES = [("iron-ore", 0, 7, "i"), ("copper-ore", 1, 7, "c"), ("coal", 2, 7, "k"), ("stone", 3, 7, "s"), ("iron-ore", 9, 3, None)]
GHOST, WATER, ROCK = (11, 1), [(10, 7), (11, 7)], (12, 4)


def asciimap_build():
    lines = []
    for name, x, y, d, _ in LAYOUT:
        base = name.replace("-out", "")
        extra = ", type = 'output'" if name.endswith("-out") else ""
        direction = f", direction = D.{d}" if d else ""
        lines.append(f'mk{{name = "{base}", position = {{{x + 0.5}, {y + 0.5}}}{direction}{extra}}}')
    lines.append('mk{name = "assembling-machine-1", position = {7.5, 4.5}}')
    lines.append('mk{name = "splitter", position = {8.5, 7}, direction = D.east}')
    for name, x, y, _ in ORES:
        lines.append(f'mk{{name = "{name}", position = {{{x + 0.5}, {y + 0.5}}}, amount = 100, force = "neutral"}}')
    lines.append(f'mk{{name = "entity-ghost", inner_name = "transport-belt", position = {{{GHOST[0] + 0.5}, {GHOST[1] + 0.5}}}}}')
    lines.append("s.set_tiles{" + ", ".join(f'{{name = "water", position = {{{x}, {y}}}}}' for x, y in WATER) + "}")
    lines.append('local rock for n, p in pairs(prototypes.entity) do if p.type == "simple-entity" and n:find("rock") then rock = n break end end')
    lines.append(f'mk{{name = rock, position = {{{ROCK[0] + 0.5}, {ROCK[1] + 0.5}}}, force = "neutral"}}')
    return "\n".join(lines)


def asciimap_rows():
    """The map the layout should give, without the rock, whose size depends on the prototype."""
    grid = [["."] * 14 for _ in range(9)]
    for x0, y0, w, h, ch in BIG:
        for x in range(x0, x0 + w):
            for y in range(y0, y0 + h):
                grid[y][x] = ch
    for _, x, y, ch in ORES:
        if ch:
            grid[y][x] = ch
    for x, y in WATER:
        grid[y][x] = "~"
    grid[GHOST[1]][GHOST[0]] = "+"
    for _, x, y, _, ch in LAYOUT:
        grid[y][x] = ch
    return ["".join(row) for row in grid]


@fixture("create", tags=TAGS, camera=True)
@case(["ascii_map"], surface="rk", build=lambda lab: arena(lab, asciimap_build()))
def tools_read_ascii_map(lab, bad, data):
    """ascii_map draws belts, inserters, machines, ore, water, a ghost and a rock where they are, and keeps within 64 x 64."""
    r, size = call(lab, "ascii_map", surface="rk", x0=0, y0=0, x1=14, y1=9)
    want = asciimap_rows()
    rows = lst(r["rows"])
    same(bad, "rows", [row.replace("X", ".") for row in rows], want)
    if not any("X" in row for row in rows):
        bad.append("the rock is not drawn")
    same(bad, "origin and size", (r["x0"], r["y0"], r["w"], r["h"]), (0, 0, 14, 9))
    same(bad, "legend keys", set(r["legend"]), set("".join(want)) | {"X"})
    for ch, word in (("^", "north"), ("N", "north"), ("S", "south"), ("E", "east"), ("W", "west"), ("U", "input"), ("u", "output")):
        if word not in r["legend"].get(ch, ""):
            bad.append(f"legend for {ch!r} is {r['legend'].get(ch)!r}, which lacks {word}")
    bare, _ = call(lab, "ascii_map", surface="rk", x0=0, y0=0, x1=14, y1=9, scenery=False)
    same(bad, "scenery = false", lst(bare["rows"]), want)
    inner, _ = call(lab, "ascii_map", surface="rk", x0=2, y0=1, x1=6, y1=4)
    same(bad, "a window", lst(inner["rows"]), [row[2:6] for row in rows[1:4]])
    wide, _ = call(lab, "ascii_map", surface="rk", x0=0, y0=0, x1=65, y1=10)
    if "error" not in wide:
        bad.append("an area wider than 64 returned no error")
    big, size_big = call(lab, "ascii_map", surface="rk", x0=-32, y0=-32, x1=32, y1=32)
    same(bad, "a 64 x 64 area", (len(lst(big["rows"])), {len(row) for row in lst(big["rows"])}), (64, {64}))
    data.update(bytes_14x9=size, bytes_64x64=size_big)
    return f"14 x 9 map matches, reply {size} B; 64 x 64 reply {size_big} B"


# -- the shared rules --

ALL = ["look", "inventory", "status", "belt_trace", "rate", "resources", "power", "fluid", "network", "ascii_map"]
AREA_TOOLS = ["look", "inventory", "status", "resources", "power", "fluid", "ascii_map"]

CROWD = """
for row = 0, 3 do
  for x = 0, 74 do mk{name = "pipe", position = {x - 37.5, row * 2 - 30.5}} end
end
for row = 0, 2 do
  for x = 0, 82 do
    if x < 80 then mk{name = "iron-chest", position = {x - 39.5, row * 2 + 10.5}}.insert{name = "iron-plate", count = 1} end
  end
end
"""


FIELD = """
for x = -40, 39 do for y = -40, 23 do mk{name = "transport-belt", position = {x + 0.5, y + 0.5}, direction = D.east} end end
mk{name = "heat-exchanger", position = {0.5, 30}, direction = D.north}
"""

FORK = """
mk{name = "splitter", position = {0.5, 36}, direction = D.east}
for x = 1, 2 do for y = 35, 36 do mk{name = "transport-belt", position = {x + 0.5, y + 0.5}, direction = D.east} end end
"""


def crowd(lab):
    arena(lab, CROWD + FORK)
    arena(lab, FIELD, surface="rk2")


@fixture("create", tags=TAGS, camera=True)
@case(ALL, surface="rk", build=crowd)
def tools_read_rules(lab, bad, data):
    """Every tool caps its list, rejects an unknown name, a bad area and a stray argument with an error, never a Lua error."""
    pipes = dict(x0=-40, y0=-32, x1=40, y1=-22, surface="rk")
    first, _ = call(lab, "look", **pipes)
    same(bad, "default cap", (len(lst(first["entities"])), first["total"], first.get("more"), first.get("next")), (200, 300, True, 200))
    rest, _ = call(lab, "look", offset=200, **pipes)
    same(bad, "second page", (len(lst(rest["entities"])), rest["total"], rest.get("more")), (100, 300, None))
    everything, _ = call(lab, "look", limit=300, **pipes)
    same(bad, "limit 300", (len(lst(everything["entities"])), everything.get("more")), (300, None))
    big, _ = call(lab, "look", limit=301, **pipes)
    if not (big.get("error") and big.get("hint")):
        bad.append("a limit over 300 returned no error and a hint")
    counted, _ = call(lab, "look", count=True, **pipes)
    same(bad, "count ignores the cap", counted["counts"], {"pipe": 300})
    chests, _ = call(lab, "inventory", x0=-40, y0=9, x1=40, y1=17, surface="rk")
    same(bad, "inventory cap", (len(lst(chests["entities"])), chests["total"], chests.get("more")), (200, 240, True))
    summed, _ = call(lab, "inventory", sum=True, x0=-40, y0=9, x1=40, y1=17, surface="rk")
    same(bad, "sum ignores the cap", summed, {"totals": {"iron-plate": 240}, "entities": 240})
    fits = dict(x0=0, y0=0, x1=4, y1=4, surface="rk")
    for tool in AREA_TOOLS:
        for label, area in (("backwards", dict(fits, x0=9)), ("text", dict(fits, y1="far")), ("missing", {"x0": 0, "surface": "rk"}),
                            ("stray", dict(fits, radius=3))):
            r, _ = call(lab, tool, **area)
            if not (isinstance(r, dict) and r.get("error") and r.get("hint")):
                bad.append(f"{tool} with a {label} area did not return an error and a hint: {str(r)[:80]}")
    for tool in ("belt_trace", "network"):
        for label, args in (("no y", {"x": 1}), ("text", {"x": "a", "y": 0}), ("stray", {"x": 1, "y": 1, "radius": 3})):
            r, _ = call(lab, tool, surface="rk", **args)
            if not (isinstance(r, dict) and r.get("error") and r.get("hint")):
                bad.append(f"{tool} with {label} did not return an error and a hint: {str(r)[:80]}")
    for tool, args in (("look", {"name": "ironchest"}), ("look", {"type": "chest"}), ("inventory", {"item": "iron-platee"}),
                       ("status", {"name": ["assembling-machine-9"]}), ("rate", {"items": ["iron-platee"]}),
                       ("rate", {"items": []}), ("resources", {"name": "iron-platee"}), ("fluid", {"fluid": "waterr"})):
        r, _ = call(lab, tool, **dict(fits, **args) if tool not in ("rate",) else dict(args, surface="rk"))
        if not (isinstance(r, dict) and r.get("error") and r.get("hint")):
            bad.append(f"{tool} {args} did not return an error and a hint: {str(r)[:80]}")
    hint = call(lab, "rate", items=["iron-platee"], surface="rk")[0].get("hint", "")
    if "iron-plate" not in hint:
        bad.append(f"the hint for a near-miss item name does not suggest it: {hint!r}")
    for key in ("surface", "force"):
        r, _ = call(lab, "look", x0=0, y0=0, x1=1, y1=1, **{key: {"a": 1}})
        if not (r.get("error") and r.get("hint")):
            bad.append(f"a table as {key} did not return an error and a hint: {str(r)[:80]}")
    field = dict(x0=-40, y0=-40, x1=40, y1=24, surface="rk2")
    over, _ = call(lab, "look", **field)
    if not (over.get("error") and "count" in over.get("hint", "")):
        bad.append(f"an area over the read cap did not point to count: {str(over)[:100]}")
    counted, _ = call(lab, "look", count=True, **field)
    same(bad, "count over the read cap", counted["counts"], {"transport-belt": 5120})
    over_inv, _ = call(lab, "inventory", belts=True, **field)
    if not over_inv.get("error"):
        bad.append("inventory with belts over the read cap returned no error")
    heat, _ = call(lab, "power", x0=-5, y0=26, x1=5, y1=34, surface="rk2")
    same(bad, "a heat exchanger is not a fuelled boiler", (lst(heat.get("networks")), "boilers" in heat, "error" in heat), ([], False, False))
    fork, _ = call(lab, "belt_trace", x=0.5, y=35.5, limit=1, surface="rk")
    same(bad, "cap at a splitter", (fork["tiles"], [len(lst(fork["segments"])), [e["why"] for e in lst(fork["ends"])]]),
         (1, [1, ["cap", "cap"]]))
    mars, _ = call(lab, "look", x0=0, y0=0, x1=1, y1=1, surface="mars")
    if "nauvis" not in mars.get("hint", ""):
        bad.append(f"an unknown surface does not list the surfaces: {mars}")
    return "caps, names, areas and arguments all answer with an error and a hint"


# -- engine time --

BUDGET_MS = 20.0
_DURATION = {"s": 1000.0, "ms": 1.0, "us": 1e-3, "µs": 1e-3, "ns": 1e-6}


def timed(lab, tool, /, **args):
    """Run a tool once in one Lua call under a profiler. Returns (reply, engine milliseconds, reply bytes).

    A LuaProfiler cannot be read as a number, so it is printed as a localised string and parsed.
    """
    src = json.dumps({"name": tool, "args": args})
    out = lab.lua(f'local a = helpers.json_to_table([==[{src}]==]) local p = helpers.create_profiler() '
                  'local rep = remote.call("game_bot", "tool_call", a) p.stop() '
                  'rcon.print(helpers.table_to_json(rep)) rcon.print({"", "T\\t", p})')
    first, _, rest = out.partition("\n")
    reply = json.loads(first)
    if not reply.get("ok"):
        raise SbxError(reply.get("error", "error"), reply.get("detail", ""))
    value, unit = re.search(r"Duration: ([\d.]+)\s*(\w+)?", rest).groups()
    return reply["r"], float(value) * _DURATION.get(unit, 1.0), len(first)


@fixture(RUN4, tags=TAGS, camera=True)
@case(["look", "status", "inventory", "power", "fluid", "resources", "belt_trace", "rate", "network", "ascii_map"])
def tools_read_budget(lab, bad, data):
    """Every tool, called over the whole run4 base at its caps, answers or refuses with a hint within 20 ms of engine time (best of three)."""
    area = lab.sbx("slice_area_of_base", pad=0)["area"]
    base = dict(x0=area[0][0], y0=area[0][1], x1=area[1][0], y1=area[1][1])
    belt = dict(x=108.5, y=-21.5)
    runs = [
        ("look", dict(base)), ("look count", dict(base, count=True)), ("look inserters", dict(base, type="inserter", limit=300)),
        ("look belts", dict(base, type="transport-belt", limit=300)),
        ("status", dict(base)), ("status all", dict(base, working=True, limit=300)),
        ("inventory", dict(base)), ("inventory sum", dict(base, sum=True)), ("inventory belts", dict(base, belts=True, sum=True)),
        ("power", dict(base)), ("fluid", dict(base)), ("fluid all", dict(base, limit=300)),
        ("resources", dict(base)), ("resources all", dict(base, limit=300)),
        ("belt_trace", dict(belt, limit=500, up=True, taps=True)), ("belt_trace default", dict(belt)),
        ("rate", dict(items=["iron-plate", "copper-plate", "coal", "crude-oil", "petroleum-gas"])),
        ("network", dict(x=100, y=0)), ("ascii_map", dict(x0=100, y0=-40, x1=164, y1=24)),
        # windows that hold the most, where the call is answered and not refused
        ("resources window", dict(x0=256, y0=-160, x1=512, y1=96)), ("inventory window", dict(x0=448, y0=-224, x1=640, y1=-32)),
        ("look window", dict(x0=-128, y0=-160, x1=0, y1=-32, limit=300)), ("status window", dict(x0=0, y0=-160, x1=256, y1=96)),
        ("fluid window", dict(x0=0, y0=-160, x1=256, y1=96)), ("power window", dict(x0=0, y0=-160, x1=256, y1=96)),
    ]
    times, worst = {}, 0.0
    for label, args in runs:
        tool = label.split()[0]
        if tool == "look" and "count" in label:
            args = dict(args, count=True)
        runs3 = [timed(lab, tool, **args) for _ in range(3)]
        reply, _, size = runs3[0]
        ms = min(t for _, t, _ in runs3)
        times[label] = {"ms": round(ms, 2), "max_ms": round(max(t for _, t, _ in runs3), 2), "bytes": size,
                        "refused": bool(reply.get("error"))}
        worst = max(worst, ms)
        if ms > BUDGET_MS:
            bad.append(f"{label} took {ms:.1f} ms of engine time at best of 3, over {BUDGET_MS:.0f}")
        if reply.get("error") and not reply.get("hint"):
            bad.append(f"{label} refused without a hint: {reply['error']}")
    data["times"] = times
    shown = "; ".join(f"{k} {v['ms']} ms{' (refused)' if v['refused'] else ''}" for k, v in times.items())
    return f"worst {worst:.1f} ms. {shown}"
