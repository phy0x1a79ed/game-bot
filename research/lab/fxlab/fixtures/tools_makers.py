"""Fixtures for the makers tool (research/tools/read/makers.lua). Owned by scope trial-tools-1.

The world is two gear sites, a cable assembler and a furnace on a flat surface. The fed site runs for ten seconds,
and the gears its machines finish are the ground truth for the ceiling makers claims.
"""

from .registry import fixture
from .tools_read import BUDGET_MS, POWER, RUN4, TAGS, arena, call, case, jlua, same, timed

SURFACE = "mk"
SECONDS = 10

WORLD = POWER + """
local function am(x, y, recipe, plates, modules)
  local e = mk{name = "assembling-machine-2", position = {x, y}}
  e.set_recipe(recipe)
  if plates then e.get_inventory(defines.inventory.crafter_input).insert{name = plates, count = 200} end
  if modules then e.get_module_inventory().insert{name = modules, count = 2} end
  return e
end
-- fed gear site, one machine with two speed modules
am(-10.5, 0.5, "iron-gear-wheel", "iron-plate")
am(-7.5, 0.5, "iron-gear-wheel", "iron-plate", "speed-module")
am(-4.5, 0.5, "iron-gear-wheel", "iron-plate")
am(-7.5, 4.5, "copper-cable", "copper-plate")
-- starved gear site with a ghost beside it
am(20.5, 20.5, "iron-gear-wheel")
am(23.5, 20.5, "iron-gear-wheel")
mk{name = "entity-ghost", inner_name = "assembling-machine-2", position = {26.5, 20.5}, recipe = "iron-gear-wheel"}
local f = mk{name = "stone-furnace", position = {0, -10}}
f.insert{name = "coal", count = 20}
f.insert{name = "iron-ore", count = 50}
"""

FINISHED = """
local out = {}
for _, e in pairs(game.surfaces.mk.find_entities_filtered{type = {"assembling-machine", "furnace"}}) do
  out[#out + 1] = {name = e.get_recipe() and e.get_recipe().name or "none", x = e.position.x, y = e.position.y,
    done = e.products_finished, speed = e.crafting_speed}
end
rcon.print(helpers.table_to_json(out))
"""


def world(lab):
    arena(lab, WORLD, surface=SURFACE)
    lab.advance(60 * SECONDS)


def by_pos(sites, x, y):
    return next(s for s in sites if s["x0"] <= x <= s["x1"] and s["y0"] <= y <= s["y1"])


@fixture("create", tags=TAGS, camera=True)
@case(["makers"], surface=SURFACE, build=world)
def tools_read_makers(lab, bad, data):
    """makers groups gear machines into a fed site and a starved one, and the fed site's ceiling matches the gears it finished."""
    truth = jlua(lab, FINISHED)
    fed = [m for m in truth if m["name"] == "iron-gear-wheel" and m["y"] < 1]
    made = sum(m["done"] for m in fed)
    r, size = call(lab, "makers", item="iron-gear-wheel", surface=SURFACE)
    same(bad, "machines, ghosts, sites, scope", (r["machines"], r["ghosts"], r["total"], r["scope"]), (5, 1, 2, "surface"))
    a, b = by_pos(r["sites"], -7.5, 0.5), by_pos(r["sites"], 23.5, 20.5)
    same(bad, "fed site", (a["n"], a["ghosts"], a["status"]), (3, 0, {"working": 3}))
    same(bad, "starved site", (b["n"], b["ghosts"], b.get("missing")), (2, 1, {"iron-plate": 2}))
    want_speed = round(sum(m["speed"] for m in fed), 2)
    same(bad, "fed site speed", a["speed"], want_speed)
    claimed = a["ceiling"] * SECONDS / 60
    if abs(claimed - made) > len(fed):
        bad.append(f"fed site ceiling {a['ceiling']}/min claims {claimed:.1f} gears in {SECONDS} s; they finished {made}")
    same(bad, "total ceiling", r["ceiling"], round(a["ceiling"] + b["ceiling"], 2))
    if abs(r["measured"]["made"] - made / 10) > 1:
        bad.append(f"measured made {r['measured']['made']}/min over 10 minutes, want about {made / 10:.1f}")
    same(bad, "recipe listed", [(x["name"], x["enabled"], x["products"]) for x in r["recipes"]],
         [("iron-gear-wheel", True, {"iron-gear-wheel": 1})])

    use, _ = call(lab, "makers", item="iron-plate", use=True, surface=SURFACE)
    same(bad, "plate users", (use["machines"], use["total"], use.get("use")), (5, 2, True))
    same(bad, "plate use ceiling", round(use["ceiling"], 1), round(2 * r["ceiling"], 1))
    plate, _ = call(lab, "makers", item="iron-plate", surface=SURFACE)
    same(bad, "furnace site", [(s["recipe"], s["n"], s["status"]) for s in plate["sites"]],
         [("iron-plate", 1, {"working": 1})])

    one, _ = call(lab, "makers", item="iron-gear-wheel", gap=32, surface=SURFACE)
    same(bad, "a wide gap joins the sites", one["total"], 1)
    page, _ = call(lab, "makers", item="iron-gear-wheel", limit=1, surface=SURFACE)
    same(bad, "page", (len(page["sites"]), page.get("more"), page.get("next"), page["sites"][0]["recipe"]),
         (1, True, 1, "iron-gear-wheel"))
    area, _ = call(lab, "makers", item="iron-gear-wheel", x0=15, y0=15, x1=30, y1=25, surface=SURFACE)
    same(bad, "area", (area["machines"], area["ghosts"], area["scope"]), (2, 1, "area"))
    for args in (dict(item="nope"), dict(), dict(item="iron-plate", gap=99), dict(item="iron-plate", bogus=1)):
        e, _ = call(lab, "makers", surface=SURFACE, **args)
        if not (e.get("error") and e.get("hint")):
            bad.append(f"{args} gave {e}, want an error with a hint")
    data.update(bytes=size, made=made, ceiling=a["ceiling"])
    return f"fed site {a['ceiling']}/min claimed, {made} gears in {SECONDS} s ({made * 60 / SECONDS:.0f}/min); reply {size} B"


@fixture(RUN4, tags=TAGS, camera=True)
@case(["makers"])
def tools_read_makers_budget(lab, bad, data):
    """makers over the whole run4 base, for the items with the most machines, answers within 20 ms of engine time."""
    runs = [("iron-plate", {}), ("iron-plate", {"use": True}), ("iron-gear-wheel", {}), ("electronic-circuit", {}),
            ("copper-cable", {"use": True}), ("chemical-science-pack", {}), ("petroleum-gas", {})]
    times, worst = {}, 0.0
    for item, extra in runs:
        label = item + (" use" if extra else "")
        tries = [timed(lab, "makers", item=item, limit=300, **extra) for _ in range(3)]
        reply, _, size = tries[0]
        ms = min(t for _, t, _ in tries)
        worst = max(worst, ms)
        times[label] = {"ms": round(ms, 2), "bytes": size, "machines": reply.get("machines"), "sites": reply.get("total")}
        if reply.get("scope") != "robots":
            bad.append(f"{label} scanned {reply.get('scope')}, want the robots' box by default")
        if ms > BUDGET_MS:
            bad.append(f"{label} took {ms:.1f} ms of engine time at best of 3, over {BUDGET_MS:.0f}")
        if reply.get("error"):
            bad.append(f"{label} refused: {reply['error']}")
    data["times"] = times
    return f"worst {worst:.1f} ms. " + "; ".join(
        f"{k} {v['ms']} ms, {v['machines']} machines, {v['sites']} sites, {v['bytes']} B" for k, v in times.items())
