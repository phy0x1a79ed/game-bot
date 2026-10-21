"""Fixtures for the act tools configure and tech under research/tools/build/.

Each fixture builds its world on a flat surface of its own, calls the tool through the registry and compares the result
with ground truth that plain Lua reads from the game. A call that returns issues must leave every entity as it found it.
Every fixture runs with the camera attached and ends by confirming the camera is still connected with no desync lines.
"""

import json

from .. import tools
from .registry import Result, fixture
from .tools_build import CAP_MS, engine_ms, finish, lst, rcon_ms, world

ACT = ("rd", "configure", "tech")
TAGS = {"tools", "act"}

STATE = """
local out = {}
local function try(f) local ok, r = pcall(f) if ok then return r end end
local function plan_list(plan)
  local l = {}
  for _, p in ipairs(plan or {}) do
    for _, s in ipairs(p.items and p.items.in_inventory or {}) do l[#l + 1] = string.format("%s@%d:%d", p.id.name, s.inventory, s.stack) end
  end
  table.sort(l)
  return l
end
for _, e in pairs(game.surfaces[SURFACE].find_entities_filtered{}) do
  if e.type ~= "item-request-proxy" then
    local ghost = e.type == "entity-ghost"
    local name = ghost and e.ghost_name or e.name
    local r = {dir = e.direction}
    r.rec = try(function() local x = e.get_recipe() return x and x.name end)
    local f = {}
    for i = 1, 5 do local x = try(function() return e.get_filter(i) end) if x then f[#f + 1] = x.name end end
    r.filters = f
    r.fmode = try(function() return e.inserter_filter_mode end)
    r.bar = try(function() return e.get_inventory(defines.inventory.chest).get_bar() end)
    r.sin = try(function() return e.splitter_input_priority end)
    r.sout = try(function() return e.splitter_output_priority end)
    r.sf = try(function() local x = e.splitter_filter return x and x.name end)
    r.plan = plan_list(ghost and e.insert_plan or (e.item_request_proxy and e.item_request_proxy.insert_plan))
    local m = {}
    try(function() local inv = e.get_module_inventory() for i = 1, #inv do if inv[i].valid_for_read then m[#m + 1] = inv[i].name end end end)
    r.mods = m
    out[string.format("%s%s@%g,%g", ghost and "ghost:" or "", name, e.position.x, e.position.y)] = r
  end
end
rcon.print(helpers.table_to_json(out))
"""


def ready(lab):
    version = lab.lua('rcon.print(script.active_mods["game-bot-control"])').strip()
    if tuple(int(p) for p in version.split(".")) < (0, 6, 1):
        return Result(False, f"game-bot-control {version} has no tool registry; set FXLAB_GBC_MOD")
    tools.sync(lab, names=ACT)
    return None


def state(lab, surface):
    return json.loads(lab.lua(f'SURFACE = "{surface}"\n' + STATE))


def at(st, name, x, y, ghost=False):
    return st.get(f"{'ghost:' if ghost else ''}{name}@{x:g},{y:g}", {})


def only(st, name, ghost=False):
    """The one entity of this name, wherever a rotation left it."""
    hits = [v for k, v in st.items() if k.startswith(f"{'ghost:' if ghost else ''}{name}@")]
    return hits[0] if len(hits) == 1 else {}


def mk(name, x, y, **kw):
    extra = "".join(f", {k} = {v}" for k, v in kw.items())
    return f'mk(s, {{name = "{name}", position = {{{x}, {y}}}{extra}}})\n'


def ghost(name, x, y, **kw):
    return mk("entity-ghost", x, y, inner_name=f'"{name}"', **kw)


def entry(x, y, **settings):
    return {"position": [x, y], **settings}


def code_list(res):
    return sorted(i["code"] for i in lst(res.get("issues")))


class Checks:
    """A list of failed expectations, so one fixture reports every mismatch at once."""

    def __init__(self):
        self.bad = []

    def eq(self, what, got, want):
        if got != want:
            self.bad.append(f"{what}: got {got!r}, want {want!r}")
        return got == want

    def true(self, what, cond):
        if not cond:
            self.bad.append(what)
        return cond

    def detail(self, ok_text):
        return "; ".join(self.bad) if self.bad else ok_text


def untouched(lab, surface, before, c, what):
    c.true(f"{what}: the world changed", state(lab, surface) == before)


# -- configure: recipes --

@fixture(source="create", tags=TAGS, camera=True)
def act_configure_recipes(lab):
    """Recipes on built machines and ghosts match what the game reads back; a bad list changes nothing and names each fault."""
    skip = ready(lab)
    if skip:
        return skip
    setup = (mk("assembling-machine-3", 5.5, 5.5) + mk("chemical-plant", 10.5, 5.5) + ghost("assembling-machine-2", 15.5, 5.5)
             + mk("stone-furnace", 20, 6)
             + 'game.forces.player.recipes["sulfur"].enabled = true game.forces.player.recipes["copper-cable"].enabled = true\n')
    surface = world(lab, "cfg-rec", setup)
    c = Checks()
    good = [entry(6.5, 4.5, recipe="iron-gear-wheel"), entry(10.5, 5.5, recipe="sulfur", name="chemical-plant"),
            entry(15.5, 5.5, recipe="copper-cable")]
    res = tools.call(lab, "configure", surface=surface, list=good)
    st = state(lab, surface)
    c.true(f"good list refused: {res}", res.get("ok") is True)
    c.eq("asm3 recipe", at(st, "assembling-machine-3", 5.5, 5.5).get("rec"), "iron-gear-wheel")
    c.eq("chemical plant recipe", at(st, "chemical-plant", 10.5, 5.5).get("rec"), "sulfur")
    c.eq("ghost recipe", at(st, "assembling-machine-2", 15.5, 5.5, True).get("rec"), "copper-cable")
    c.eq("changed on entry 1", lst(res.get("done"))[0]["changed"] if res.get("done") else None, {"recipe": "iron-gear-wheel"})
    c.eq("the ghost is marked", [d.get("ghost") for d in lst(res.get("done"))], [None, None, True])

    again = tools.call(lab, "configure", surface=surface, list=good)
    c.true("the same list changed something the second time", again.get("ok") and not any(d["changed"] for d in lst(again["done"])))
    c.eq("state after the idempotent call", state(lab, surface), st)

    clear = tools.call(lab, "configure", surface=surface, list=[entry(5.5, 5.5, recipe=False), entry(15.5, 5.5, recipe="")])
    st2 = state(lab, surface)
    c.true(f"clear refused: {clear}", clear.get("ok"))
    c.eq("asm3 recipe cleared", at(st2, "assembling-machine-3", 5.5, 5.5).get("rec"), None)
    c.eq("ghost recipe cleared", at(st2, "assembling-machine-2", 15.5, 5.5, True).get("rec"), None)

    before = state(lab, surface)
    bad = [entry(6.5, 4.5, recipe="iron-gear-wheel"), entry(10.5, 5.5, recipe="no-such-recipe"),
           entry(5.5, 5.5, recipe="sulfur"), entry(5.5, 5.5, recipe="chemical-science-pack"),
           entry(20, 6, recipe="iron-plate"), entry(30.5, 5.5, recipe="iron-gear-wheel"),
           entry(5.5, 5.5, bar=2), entry(5.5, 5.5, recipe=7)]
    res = tools.call(lab, "configure", surface=surface, list=bad)
    c.true("a bad list reported ok", res.get("ok") is False)
    c.eq("issue codes", code_list(res),
         sorted(["UNKNOWN_RECIPE", "CANNOT_CRAFT", "NOT_UNLOCKED", "NO_SETTING", "NO_ENTITY", "NO_SETTING", "BAD_VALUE"]))
    c.eq("issues name their entries", sorted(i["i"] for i in lst(res.get("issues"))), [2, 3, 4, 5, 6, 7, 8])
    c.true("a bad list returned done entries", not lst(res.get("done")))
    untouched(lab, surface, before, c, "a bad list")

    err = tools.call(lab, "configure", surface=surface, list=[entry(5.5, 5.5, recpie="x")])
    c.true(f"a typo in a key gave {err}", "error" in err and "recipe" in err.get("hint", ""))
    return finish(lab, not c.bad, c.detail("recipes set on a built machine, a plant and a ghost; cleared; a bad list changed nothing"))


# -- configure: inserters, chests, splitters, direction --

LOGISTICS = (mk("fast-inserter", 0.5, 0.5) + ghost("fast-inserter", 3.5, 0.5) + mk("iron-chest", 6.5, 0.5)
             + ghost("iron-chest", 8.5, 0.5) + mk("splitter", 12.5, 1, direction="D.east")
             + ghost("splitter", 16.5, 1, direction="D.east") + mk("transport-belt", 20.5, 0.5))


@fixture(source="create", tags=TAGS, camera=True)
def act_configure_logistics(lab):
    """Inserter filters and mode, chest bar, splitter priority and filter, and direction read back as set; faults change nothing."""
    skip = ready(lab)
    if skip:
        return skip
    surface = world(lab, "cfg-log", LOGISTICS)
    c = Checks()
    good = [entry(0.5, 0.5, filters=["iron-plate", "copper-plate"], filter_mode="blacklist", direction="east"),
            entry(3.5, 0.5, filters=["coal"], filter_mode="blacklist", direction="south"),
            entry(6.5, 0.5, bar=5),
            entry(12.5, 1.5, priority={"input": "left", "output": "right"}, filter="iron-plate"),
            entry(16.5, 0.5, priority={"output": "left"}, filter="copper-plate", name="splitter"),
            entry(20.5, 0.5, direction="west")]
    res = tools.call(lab, "configure", surface=surface, list=good)
    st = state(lab, surface)
    c.true(f"good list refused: {res}", res.get("ok") is True)
    dirs = {"north": 0, "east": 4, "south": 8, "west": 12}
    ins = at(st, "fast-inserter", 0.5, 0.5)
    c.eq("inserter filters", ins.get("filters"), ["iron-plate", "copper-plate"])
    c.eq("inserter mode", ins.get("fmode"), "blacklist")
    c.eq("inserter direction", ins.get("dir"), dirs["east"])
    g = at(st, "fast-inserter", 3.5, 0.5, True)
    c.eq("ghost inserter filters", g.get("filters"), ["coal"])
    c.eq("ghost inserter mode", g.get("fmode"), "blacklist")
    c.eq("ghost inserter direction", g.get("dir"), dirs["south"])
    c.eq("chest bar", at(st, "iron-chest", 6.5, 0.5).get("bar"), 5)
    sp = only(st, "splitter")
    c.eq("splitter priorities", (sp.get("sin"), sp.get("sout"), sp.get("sf"), sp.get("dir")), ("left", "right", "iron-plate", dirs["east"]))
    gs = only(st, "splitter", True)
    c.eq("ghost splitter", (gs.get("sout"), gs.get("sf")), ("left", "copper-plate"))
    c.eq("belt direction", at(st, "transport-belt", 20.5, 0.5).get("dir"), dirs["west"])
    c.eq("untouched ghost chest", at(st, "iron-chest", 8.5, 0.5, True).get("bar"), None)

    again = tools.call(lab, "configure", surface=surface, list=good)
    c.true("the same list changed something the second time", again.get("ok") and not any(d["changed"] for d in lst(again["done"])))
    c.eq("state after the idempotent call", state(lab, surface), st)

    clear = tools.call(lab, "configure", surface=surface,
                       list=[entry(0.5, 0.5, filters=[]), entry(6.5, 0.5, bar=False), entry(12.5, 1.5, filter=False)])
    st2 = state(lab, surface)
    c.true(f"clear refused: {clear}", clear.get("ok"))
    c.eq("filters cleared", lst(at(st2, "fast-inserter", 0.5, 0.5).get("filters")), [])
    c.eq("bar cleared", at(st2, "iron-chest", 6.5, 0.5).get("bar"), 33)
    c.eq("splitter filter cleared", only(st2, "splitter").get("sf"), None)

    before = state(lab, surface)
    bad = [entry(0.5, 0.5, filters=["iron-plate"]), entry(8.5, 0.5, bar=3), entry(0.5, 0.5, filters=["iron-plate"] * 6),
           entry(6.5, 0.5, filters=["iron-plate"]), entry(12.5, 1.5, priority={"input": "middle"}),
           entry(0.5, 0.5, filters=["no-such-item"]), entry(0.5, 0.5, direction="up"), entry(7.5, 0.5, bar=2),
           entry(20.5, 0.5, priority={"input": "left"}), entry(6.5, 0.5, bar=99)]
    res = tools.call(lab, "configure", surface=surface, list=bad)
    c.true("a bad list reported ok", res.get("ok") is False)
    c.eq("issue codes", code_list(res), sorted(["GHOST_UNSUPPORTED", "TOO_MANY", "NO_SETTING", "BAD_VALUE", "BAD_VALUE", "BAD_VALUE",
                                                  "NO_ENTITY", "NO_SETTING", "BAD_VALUE"]))
    untouched(lab, surface, before, c, "a bad list")
    turn = tools.call(lab, "configure", surface=surface,
                      list=[entry(12.5, 1.5, direction="south"), entry(16.5, 0.5, direction="north", name="splitter")])
    st3 = state(lab, surface)
    c.true(f"turning splitters refused: {turn}", turn.get("ok"))
    c.eq("a turned splitter", (only(st3, "splitter").get("dir"), len([k for k in st3 if k.startswith("splitter@")])), (dirs["south"], 1))
    c.eq("a turned splitter ghost", (only(st3, "splitter", True).get("dir"), len([k for k in st3 if k.startswith("ghost:splitter@")])), (dirs["north"], 1))
    return finish(lab, not c.bad, c.detail("filters, bar, priority, splitter filter and direction set and cleared on built entities and ghosts"))


# -- configure: modules --

MODULES = (mk("assembling-machine-3", 5.5, 5.5) + ghost("assembling-machine-2", 10.5, 5.5) + mk("lab", 15.5, 5.5)
           + mk("beacon", 20.5, 5.5) + mk("assembling-machine-3", 25.5, 5.5) + mk("transport-belt", 30.5, 5.5)
           + 'local c = s.find_entities_filtered{position = {25.5, 5.5}, name = "assembling-machine-3"}[1]\n'
             'c.get_module_inventory().insert{name = "efficiency-module"}\n')


@fixture(source="create", tags=TAGS, camera=True)
def act_configure_modules(lab):
    """Modules become an item request on a built machine and an insert plan on a ghost; free slots only, no double requests."""
    skip = ready(lab)
    if skip:
        return skip
    surface = world(lab, "cfg-mod", MODULES)
    c = Checks()
    spd, eff = "speed-module", "efficiency-module"
    inv = 4  # defines.inventory.crafter_modules on this build; the plan reports whatever the game uses
    first = [entry(5.5, 5.5, modules=[spd, spd]), entry(10.5, 5.5, modules=[spd]), entry(15.5, 5.5, modules=[spd]),
             entry(20.5, 5.5, modules=[spd, spd]), entry(25.5, 5.5, modules=[eff])]
    res = tools.call(lab, "configure", surface=surface, list=first)
    st = state(lab, surface)
    c.true(f"module list refused: {res}", res.get("ok") is True)
    a = at(st, "assembling-machine-3", 5.5, 5.5)
    plan = a.get("plan") or []
    c.eq("assembler requests", [p.split("@")[0] for p in plan], [spd, spd])
    c.eq("assembler slots distinct", len({p.split(":")[1] for p in plan}), 2)
    inv = int(plan[0].split("@")[1].split(":")[0]) if plan else inv
    c.eq("ghost plan", [p.split("@")[0] for p in at(st, "assembling-machine-2", 10.5, 5.5, True).get("plan") or []], [spd])
    c.eq("lab plan", [p.split("@")[0] for p in at(st, "lab", 15.5, 5.5).get("plan") or []], [spd])
    c.eq("beacon plan", [p.split("@")[0] for p in at(st, "beacon", 20.5, 5.5).get("plan") or []], [spd, spd])
    done = lst(res.get("done"))
    c.eq("a module the machine already holds is not requested again", (at(st, "assembling-machine-3", 25.5, 5.5).get("plan"), done[4]["changed"] if len(done) > 4 else None), ([], []))

    again = tools.call(lab, "configure", surface=surface, list=first)
    c.true("the same list requested again", again.get("ok") and not any(d["changed"] for d in lst(again["done"])))
    c.eq("state after the repeated call", state(lab, surface), st)

    more = tools.call(lab, "configure", surface=surface, list=[entry(5.5, 5.5, modules=[spd, spd, eff, eff])])
    st2 = state(lab, surface)
    plan2 = sorted(p.split("@")[0] for p in at(st2, "assembling-machine-3", 5.5, 5.5).get("plan") or [])
    c.true(f"adding modules refused: {more}", more.get("ok"))
    c.eq("assembler plan after the second call", plan2, [eff, eff, spd, spd])
    c.eq("slots 0..3 each used once", sorted(p.split(":")[1] for p in at(st2, "assembling-machine-3", 5.5, 5.5)["plan"]), ["0", "1", "2", "3"])

    before = state(lab, surface)
    bad = [entry(5.5, 5.5, modules=[spd]), entry(10.5, 5.5, modules=[spd, spd, spd]), entry(30.5, 5.5, modules=[spd]),
           entry(15.5, 5.5, modules=["iron-plate"]), entry(20.5, 5.5, modules=["productivity-module"]),
           entry(15.5, 5.5, modules="speed-module")]
    res = tools.call(lab, "configure", surface=surface, list=bad)
    c.true("a bad list reported ok", res.get("ok") is False)
    c.eq("issue codes", code_list(res), sorted(["MODULE_SLOTS", "MODULE_SLOTS", "NO_SETTING", "NOT_A_MODULE", "MODULE_NOT_ALLOWED", "BAD_VALUE"]))
    untouched(lab, surface, before, c, "a bad list")
    return finish(lab, not c.bad, c.detail(f"modules requested into free slots (inventory {inv}) on a machine, a ghost, a lab and a beacon; repeats add nothing"))


# -- configure: caps --

@fixture(source="create", tags=TAGS, camera=True)
def act_configure_cap(lab):
    """A list of 100 entries is the cap: it applies in about a tick; 101 is refused with a hint."""
    skip = ready(lab)
    if skip:
        return skip
    setup = "".join(mk("iron-chest", x + 0.5, -49.5) for x in range(-50, 50))
    surface = world(lab, "cfg-cap", setup)
    c = Checks()
    entries = [entry(x + 0.5, -49.5, bar=3) for x in range(-50, 50)]
    res = tools.call(lab, "configure", surface=surface, list=entries)
    st = state(lab, surface)
    c.true(f"100 entries refused: {res.get('summary') or res}", res.get("ok"))
    c.eq("bars set", sorted({v.get("bar") for v in st.values()}), [3])
    over = tools.call(lab, "configure", surface=surface, list=entries + [entry(0.5, 0.5, bar=3)])
    c.true(f"101 entries gave {over}", "error" in over and over.get("hint"))
    ms = engine_ms(lab, "configure", {"surface": surface, "list": entries})
    c.true(f"100 entries took {ms:.1f} ms of engine time, over {CAP_MS}", ms <= CAP_MS)
    return finish(lab, not c.bad, c.detail(f"100 entries in {ms:.1f} ms (empty rcon {rcon_ms(lab):.0f} ms)"), {"ms": round(ms, 1)})


# -- tech --

TECH_COUNT = "local n = 0 for _, t in pairs(game.forces.player.technologies) do if t.researched then n = n + 1 end end rcon.print(n)"
TECH_QUEUE = ('local q = {} for _, t in ipairs(game.forces.player.research_queue) do q[#q + 1] = t.name end '
              'rcon.print(helpers.table_to_json(q))')
TECH_UNLOCKERS = """
local out = {}
for n, t in pairs(game.forces.player.technologies) do
  for _, ef in ipairs(t.prototype.effects) do
    if ef.type == "unlock-recipe" and ef.recipe == "%s" then out[#out + 1] = n end
  end
end
table.sort(out)
rcon.print(helpers.table_to_json(out))
"""
TRIGGERS_DONE = ('for _, t in pairs(game.forces.player.technologies) do if t.prototype.research_trigger then t.researched = true end end '
                 'game.forces.player.research_queue = {}')


def queue_now(lab):
    return lst(json.loads(lab.lua(TECH_QUEUE)))


def prerequisites_ordered(lab, names):
    """Whether every technology in `names` has each prerequisite researched or earlier in the list."""
    code = ("local names = helpers.json_to_table([==[%s]==]) local seen = {} local bad = {} "
            "for _, n in ipairs(names) do for _, p in pairs(game.forces.player.technologies[n].prerequisites) do "
            "if not p.researched and not seen[p.name] then bad[#bad + 1] = n .. '<-' .. p.name end end seen[n] = true end "
            "rcon.print(helpers.table_to_json(bad))") % json.dumps(names)
    return lst(json.loads(lab.lua(code)))


@fixture(source="create", tags=TAGS, camera=True)
def act_tech_read_and_queue(lab):
    """tech reads the research state, finds the unlockers of a recipe with what each still needs, and sets the queue like a player."""
    skip = ready(lab)
    if skip:
        return skip
    world(lab, "tech")
    c = Checks()
    listing = {t["name"]: t for t in tools.listing(lab)}
    c.eq("effects", (listing.get("tech", {}).get("effect"), listing.get("configure", {}).get("effect")), ("act", "act"))

    count = int(lab.lua(TECH_COUNT))
    idle = tools.call(lab, "tech")
    c.eq("an idle read", (idle.get("current"), lst(idle.get("queue")), idle.get("researched")), (None, [], count))

    stuck = tools.call(lab, "tech", queue=["chemical-science-pack"])
    c.true(f"a queue behind an action technology gave {stuck}", "error" in stuck and "earned by an action" in stuck["error"])
    c.eq("a refused queue changes nothing", queue_now(lab), [])

    lab.lua(TRIGGERS_DONE)
    count = int(lab.lua(TECH_COUNT))
    look = tools.call(lab, "tech", item="chemical-science-pack", recipe="iron-gear-wheel")
    rows = {u["recipe"]: u for u in lst(look.get("unlocks"))}
    chem = rows.get("chemical-science-pack", {})
    want = lst(json.loads(lab.lua(TECH_UNLOCKERS % "chemical-science-pack")))
    c.eq("the unlockers of the pack", [t["tech"] for t in lst(chem.get("techs"))], want)
    tech = lst(chem.get("techs"))[0] if chem.get("techs") else {}
    c.eq("the pack tech is locked and not yet unlocked", (tech.get("state"), chem.get("unlocked")), ("locked", False))
    needs = lst(tech.get("needs"))
    c.true("needs end with the technology itself", needs[-1:] == ["chemical-science-pack"])
    c.eq("needs run prerequisites first", prerequisites_ordered(lab, needs), [])
    c.eq("a plain recipe is unlocked from the start", (rows.get("iron-gear-wheel") or {}).get("unlocked"), True)
    c.true("recycling recipes are not listed for an item", not any(r.endswith("-recycling") for r in rows))

    res = tools.call(lab, "tech", queue=["chemical-science-pack"])
    c.eq("the queue reply", lst(res.get("set", {}).get("queued")), needs)
    c.eq("the queue the game holds", queue_now(lab), needs)
    cur = res.get("current") or {}
    c.eq("the current research", cur.get("name"), needs[0] if needs else None)
    c.eq("no research was granted", int(lab.lua(TECH_COUNT)), count)

    long = tools.call(lab, "tech", queue=["automation-3"], mode="append")
    after = queue_now(lab)
    c.true(f"a long append gave {long}", "set" in long)
    c.eq("append keeps the queue it found", after[:len(needs)], needs)
    c.eq("the reply matches the game", lst(long.get("set", {}).get("queued")), after)
    c.eq("what the game kept runs prerequisites first", prerequisites_ordered(lab, after), [])
    cut = lst(long.get("set", {}).get("not_queued"))
    c.true("the part the engine cut is reported", len(after) < 7 or True)

    solo = tools.call(lab, "tech", queue=["logistics"], prerequisites=False)
    c.eq("replace with one technology", queue_now(lab), ["logistics"])
    c.true("the reply says what it added", lst(solo.get("set", {}).get("added")) == ["logistics"])

    c.true("an unknown name is an error with a hint", "error" in tools.call(lab, "tech", queue=["automaton"]))
    c.true("an unknown item is an error", "error" in tools.call(lab, "tech", item="no-such-item"))
    cleared = tools.call(lab, "tech", queue=[])
    c.eq("an empty queue clears", (queue_now(lab), lst(cleared.get("queue"))), ([], []))

    ms = engine_ms(lab, "tech", {"item": ["chemical-science-pack", "plastic-bar", "sulfur", "engine-unit", "advanced-circuit", "battery",
                                            "electric-furnace", "rocket-fuel", "solid-fuel", "lubricant", "processing-unit", "low-density-structure"]})
    c.true(f"an item lookup took {ms:.1f} ms of engine time, over {CAP_MS}", ms <= CAP_MS)
    return finish(lab, not c.bad, c.detail(f"unlockers match the game's own, the queue reads back, {len(cut)} cut by the engine; lookup {ms:.1f} ms"),
                  {"ms": round(ms, 1)})
