"""Fixtures for the read tools under research/tools/read/. Owned by scope fxlab-tools-read (T12).

Each fixture loads the tools it needs, calls them in a lab with the camera as a second peer, and compares the
replies with ground truth that plain Lua reads from the game. A call must leave the world as it found it.
"""

import json

from .. import camera, tools
from ..lab import SbxError
from .registry import Result, fixture

TAGS = {"tools", "read"}
RUN4 = "run4-closeout+cam"
MIN_MOD = (0, 6, 1)

STAMP = """
local s = game.surfaces.nauvis
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


def stamp(lab):
    return jlua(lab, STAMP)


def sync(lab, *names):
    """Define the named tools and the libs they use. False when the lab's game-bot-control has no tool registry."""
    version = lab.lua('rcon.print(script.active_mods["game-bot-control"])').strip()
    if tuple(int(p) for p in version.split(".")) < MIN_MOD:
        return False
    tools.sync(lab, names=list(names), root=tools.TOOLS)
    return True


def case(tool_names):
    """Wrap a check function: sync the tools, run it, and add the shared checks.

    The check takes (lab, bad, data) and appends a sentence to `bad` for every failed expectation.
    The world must be unchanged afterwards, the camera still connected and no desync logged.
    """
    def wrap(check):
        def run(lab):
            if not sync(lab, *tool_names):
                return Result(True, "skipped: game-bot-control has no tool registry; set FXLAB_GBC_MOD")
            before, bad, data = stamp(lab), [], {}
            detail = check(lab, bad, data)
            after = stamp(lab)
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


def near(a, b, tol=0.011):
    return abs(a - b) <= tol


@fixture(RUN4, tags=TAGS, camera=True)
@case(["look"])
def tools_read_look(lab, bad, data):
    """look counts, filters, pages and inserter pickup and drop positions match plain Lua on the run4 base."""
    truth = jlua(lab, LOOK_TRUTH % LOOK_AREA)
    total = sum(truth["names"].values())
    counted, size = call(lab, "look", count=True, **LOOK_AREA)
    same(bad, "counts per name", counted["counts"], truth["names"])
    same(bad, "total with ghosts", counted["total"], total + truth["ghosts"])
    full, size_full = call(lab, "look", limit=1000, **LOOK_AREA)
    ents = lst(full["entities"])
    same(bad, "full list length", len(ents), total + truth["ghosts"])
    same(bad, "full list has no cut", full.get("more"), None)
    first, _ = call(lab, "look", limit=7, **LOOK_AREA)
    second, _ = call(lab, "look", limit=7, offset=7, **LOOK_AREA)
    same(bad, "first page cut", (first.get("more"), first.get("next"), first["total"]), (True, 7, total + truth["ghosts"]))
    same(bad, "pages follow the full list", lst(first["entities"]) + lst(second["entities"]), ents[:14])
    only, _ = call(lab, "look", ghosts=False, count=True, **LOOK_AREA)
    same(bad, "ghosts = false", only["total"], total)
    kinds, _ = call(lab, "look", type="inserter", limit=1000, **LOOK_AREA)
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
    ghosts, _ = call(lab, "look", ghosts=True, limit=1000, **box)
    same(bad, "ghosts = true", (ghosts["total"], all(e.get("ghost") for e in lst(ghosts["entities"]))),
         (ghost_truth["ghosts"], True))
    if not ghost_truth["ghosts"]:
        bad.append("the ghost box held no ghost")
    data["bytes_full_60x50"] = size_full
    data["bytes_count"] = size
    return f"{total + truth['ghosts']} entities, {len(truth['inserters'])} inserters; full list {size_full} B, count {size} B"


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
        listed, size_rows = call(lab, "inventory", limit=1000, **area)
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


@fixture(RUN4, tags=TAGS, camera=True)
@case(["status"])
def tools_read_status(lab, bad, data):
    """status counts every machine by status and names the recipe and the short inputs of each one that is idle."""
    truth = jlua(lab, STATUS_TRUTH % dict(BASE, types=json.dumps(MACHINES)))
    r, size = call(lab, "status", limit=1000, working=True, **BASE)
    same(bad, "counts per status", r["counts"], truth)
    groups = r["groups"]
    listed = sum(len(v) for v in groups.values())
    same(bad, "listed machines", (r["total"], listed), (sum(truth.values()), sum(truth.values())))
    same(bad, "working group", len(groups.get("working", [])), truth.get("working", 0))
    idle, size_idle = call(lab, "status", limit=1000, **BASE)
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
    return f"{sum(truth.values())} machines, {idle['total']} idle, {check['checked']} with missing inputs checked; idle list {size_idle} B"


# -- power --

POWER_TRUTH = """
local s = game.surfaces.nauvis
local a = {{%(x0)s, %(y0)s}, {%(x1)s, %(y1)s}}
local kw, engines, poles, weak = 0, 0, 0, 0
local ST = {} for k, v in pairs(defines.entity_status) do ST[v] = k end
for _, e in pairs(s.find_entities_filtered{area = a, force = "player"}) do
  if e.type == "generator" then kw = kw + e.energy_generated_last_tick * 60 / 1000 engines = engines + 1 end
  if e.type == "electric-pole" then poles = poles + 1 end
  local st = e.status and ST[e.status]
  if st == "no_power" or st == "low_power" then weak = weak + 1 end
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
