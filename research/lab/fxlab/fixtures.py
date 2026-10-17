"""The fixture suite: each fixture builds a world in its own lab, exercises one tool, and reports pass or fail.

A fixture returns a Result. `score` is optional and higher is better; the ratchet compares scores across
tool versions only between fixtures of the same name.
"""

from dataclasses import dataclass, field
from pathlib import Path

from . import balance

LUA = Path(__file__).resolve().parent / "lua"
FIXTURES = {}


@dataclass
class Result:
    ok: bool
    detail: str = ""
    score: float | None = None
    data: dict = field(default_factory=dict)


def fixture(source="create", tags=()):
    """Register a fixture. `source` is "create" for a new world or the name of a realm save."""
    def wrap(fn):
        FIXTURES[fn.__name__] = {"fn": fn, "source": source, "tags": set(tags)}
        return fn
    return wrap


def mini_factory(lab):
    if "deleted" in lab.lua_file(LUA / "fixture-mini-factory.lua"):
        lab.lua_file(LUA / "fixture-mini-factory.lua")
    lab.advance(3600)


def windowed(lab, act=None, ticks=18000):
    """Census, run half the window, apply `act` Lua, run the rest, census again. Returns (verdict, act output)."""
    before = balance.snapshot(lab)
    lab.advance(ticks // 2)
    printed = lab.lua(act).strip() if act else ""
    lab.advance(ticks - ticks // 2)
    return balance.judge(before, balance.snapshot(lab)), printed


def near(value, target, slack=4):
    return abs(value - target) <= slack


FX = 'local s = game.surfaces.fx '


@fixture(tags={"balance"})
def balance_clean(lab):
    mini_factory(lab)
    v, _ = windowed(lab)
    return Result(v.ok, v.summary())


@fixture(tags={"balance"})
def balance_planted_insert(lab):
    mini_factory(lab)
    v, n = windowed(lab, FX + 'rcon.print(s.find_entities_filtered{name = "iron-chest", position = {-6.5, -6.5}}[1]'
                             '.insert{name = "iron-plate", count = 50})')
    hit = near(v.created.get("iron-plate", 0), int(n))
    return Result(not v.ok and hit, v.summary())


@fixture(tags={"balance"})
def balance_planted_delete(lab):
    mini_factory(lab)
    v, n = windowed(lab, FX + 'local c = s.find_entities_filtered{name = "iron-chest", position = {-0.5, -6.5}}[1] '
                             'rcon.print(c.remove_item{name = "iron-gear-wheel", count = 40})')
    hit = int(n) > 10 and near(v.deleted.get("iron-gear-wheel", 0), -int(n))
    return Result(not v.ok and hit, v.summary())


@fixture(tags={"balance"})
def balance_unjam_clear(lab):
    """Caviar's T-B4 pattern: a worker clears a machine's output to unjam it."""
    mini_factory(lab)
    v, _ = windowed(lab, FX + 'local a = s.find_entities_filtered{name = "assembling-machine-2"}[1] '
                          'a.get_output_inventory().clear() '
                          's.find_entities_filtered{name = "iron-chest", position = {-0.5, -6.5}}[1].clear_items_inside()')
    return Result(not v.ok and "iron-gear-wheel" in v.deleted, v.summary())


@fixture(tags={"balance"})
def balance_destroy_entity(lab):
    mini_factory(lab)
    v, _ = windowed(lab, FX + 's.find_entities_filtered{name = "iron-chest", position = {6.5, 6.5}}[1].destroy()')
    hit = "automation-science-pack" in v.deleted
    return Result(not v.ok and hit, v.summary())


@fixture(tags={"balance"})
def balance_planted_fuel(lab):
    """Caviar's T-B6 pattern: sourceless coal. The furnace's fuel slot is full, so it goes into the plate chest."""
    mini_factory(lab)
    v, n = windowed(lab, FX + 'rcon.print(s.find_entities_filtered{name = "iron-chest", position = {-6.5, -6.5}}[1]'
                             '.insert{name = "coal", count = 20})')
    return Result(not v.ok and int(n) == 20 and near(v.created.get("coal", 0), 20), v.summary())


@fixture(source="run4-closeout", tags={"balance", "slow"})
def balance_run4_untouched(lab):
    """A real base with enemies, turrets and robots: an untouched window must pass."""
    v, _ = windowed(lab)
    return Result(v.ok, v.summary(), data={"excused": v.explained_by_losses})


@fixture(source="run4-closeout", tags={"bench", "slow"})
def bench_redgreen(lab):
    """Capture the run 4 red/green block from the live base and rate it: the post-mortem bench read 63 and 57."""
    from . import bench
    bp, ports = bench.capture(lab, ((112, -42), (158, -10)))
    r = bench.rate(lab, bp, minutes=5, warmup=2, ports=ports)
    red = r["outputs"].get("automation-science-pack", 0)
    green = r["outputs"].get("logistic-science-pack", 0)
    ok = near(red, 63, 6.3) and near(green, 57, 5.7)
    return Result(ok, f"red {red:.1f}/min green {green:.1f}/min, unhandled {r['unhandled']}",
                  data={"rating": {k: r[k] for k in ("outputs", "inputs", "utilisation")}})


def waits_cell(lab, cut=None):
    """Build the red-science cell, run a minute, optionally cut one input and run a minute more."""
    from . import waits
    cell = LUA / "fixture-waits.lua"
    if "deleted" in lab.lua_file(cell, prelude="WC_CUT = nil\n"):
        lab.lua_file(cell, prelude="WC_CUT = nil\n")
    lab.advance(3600)
    if cut:
        lab.lua_file(cell, prelude=f'WC_CUT = "{cut}"\n')
        lab.advance(3600)
    r = waits.census(lab, "wc")
    return r, "; ".join(waits.top(r)) or "no waits"


@fixture(tags={"waits"})
def waits_clean(lab):
    """A fed cell waits for nothing; its gear assembler shows as output-blocked, not as a wait."""
    r, detail = waits_cell(lab)
    ok = not r["waits"] and [b["item"] for b in r["blocked"]] == ["iron-gear-wheel"]
    return Result(ok, detail)


@fixture(tags={"waits"})
def waits_cut_copper(lab):
    r, detail = waits_cell(lab, "copper-plate")
    return Result(bool(r["waits"]) and r["waits"][0]["item"] == "copper-plate", detail)


@fixture(tags={"waits"})
def waits_cut_iron(lab):
    """Cutting iron starves gears too: the root, iron-plate, must rank above the derived gear wait."""
    r, detail = waits_cell(lab, "iron-plate")
    items = [w["item"] for w in r["waits"]]
    ok = items[:1] == ["iron-plate"] and any(w["item"] == "iron-gear-wheel" and w["derived"] for w in r["waits"])
    return Result(ok, detail)


@fixture(source="run4-closeout", tags={"waits", "slow"})
def waits_run4(lab):
    """The post-mortem found run 4 iron-starved: the census on its closeout must name iron-plate first."""
    from . import waits
    r = waits.census(lab)
    return Result(bool(r["waits"]) and r["waits"][0]["item"] == "iron-plate", "; ".join(waits.top(r, 5)),
                  data={"top": waits.top(r, 15), "other": r["other"]})


@fixture(tags={"acts"})
def acts_remove_off_by_one(lab):
    """A removal aimed one tile off is refused and names the real target. The exact one marks only that chest."""
    from . import acts
    mini_factory(lab)
    off = acts.act(lab, "remove", "fx", name="iron-chest", x=-5.5, y=-6.5)
    exact = acts.act(lab, "remove", "fx", name="iron-chest", x=-6.5, y=-6.5)
    marked = lab.lua(FX + 'local n = 0 for _, e in pairs(s.find_entities_filtered{to_be_deconstructed = true}) do '
                          'n = n + 1 end rcon.print(n)').strip()
    ok = not off["ok"] and "(-6.5, -6.5)" in off["refused"] and exact["ok"] and marked == "1"
    return Result(ok, f"off: {off.get('refused')}; exact: {exact.get('did')}; marked {marked}")


@fixture(tags={"acts"})
def acts_refusals(lab):
    from . import acts
    mini_factory(lab)
    tries = {
        "collision": acts.act(lab, "ghost", "fx", name="iron-chest", x=-0.5, y=-6.5),
        "prerequisite": acts.act(lab, "research", "fx", tech="logistics-2"),
        "locked recipe": acts.act(lab, "recipe", "fx", x=-3.5, y=-6.5, recipe="nuclear-reactor"),
        "no assembler": acts.act(lab, "recipe", "fx", x=-6.5, y=-6.5, recipe="iron-chest"),
        "unknown verb": acts.act(lab, "spawn", "fx", name="iron-plate"),
    }
    let_through = [k for k, r in tries.items() if r["ok"]]
    return Result(not let_through, "let through: " + ", ".join(let_through) if let_through else "all 5 refused")


@fixture(tags={"acts", "balance"})
def acts_window_balanced(lab):
    """A window of acts (recipe swap that displaces items, a ghost, a removal) passes the balance gate."""
    from . import acts
    mini_factory(lab)
    lab.lua(FX + 'local a = s.find_entities_filtered{name = "assembling-machine-2"}[1] '
                 'a.get_inventory(defines.inventory.crafter_input).insert{name = "iron-plate", count = 100}')
    before = balance.snapshot(lab)
    swap = acts.act(lab, "recipe", "fx", x=-3.5, y=-6.5, recipe="wooden-chest")
    ghost = acts.act(lab, "ghost", "fx", name="transport-belt", x=5.5, y=-15.5, direction="east")
    gone = acts.act(lab, "remove", "fx", name="iron-chest", x=-0.5, y=-6.5)
    lab.advance(10800)
    v = balance.judge(before, balance.snapshot(lab))
    built = acts.act(lab, "look", "fx", x0=5, y0=-16, x1=6, y1=-15)["did"]
    left = acts.act(lab, "look", "fx", x0=-1, y0=-7, x1=0, y1=-6)["did"]
    ok = (v.ok and swap["ok"] and swap["spilled"] and ghost["ok"] and gone["ok"]
          and [e["name"] for e in built] == ["transport-belt"] and not left)
    return Result(ok, f"{v.summary()}; spilled {swap.get('spilled')}; built {[e['name'] for e in built]}; "
                      f"chest left {bool(left)}")


@fixture(tags={"acts"})
def acts_reads(lab):
    """The read-only acts see the mini-factory as it is: two ore patches with one drill each, a robot network, gears made."""
    from . import acts
    mini_factory(lab)
    ore = {p["name"]: p for p in acts.act(lab, "resources", "fx", x0=-20, y0=-20, x1=20, y1=20)["did"]}
    net = acts.act(lab, "network", "fx", x=10, y=-10)
    rate = acts.act(lab, "rate", "fx", items=["iron-gear-wheel"])["did"]["iron-gear-wheel"]
    counted = acts.act(lab, "look", "fx", x0=-20, y0=-20, x1=20, y1=20, count=True)["did"]
    ok = (ore.get("iron-ore", {}).get("drills") == 1 and ore.get("coal", {}).get("drills") == 1
          and net["ok"] and net["did"]["construction_robots"] == 10 and rate["made_1m"] > 0
          and counted.get("assembling-machine-2") == 1)
    return Result(ok, f"ore {sorted(ore)}; robots {net.get('did', {}).get('construction_robots')}; "
                      f"gears {rate['made_1m']:.1f}/min; machines {counted.get('assembling-machine-2')}")


@fixture(tags={"acts"})
def acts_ghost_hint(lab):
    """A ghost aimed at an occupied tile is refused naming what is there, and the spot it suggests takes the ghost."""
    import re
    from . import acts
    mini_factory(lab)
    miss = acts.act(lab, "ghost", "fx", name="assembling-machine-2", x=-0.5, y=-6.5)
    m = re.search(r"fits is \((-?[\d.]+), (-?[\d.]+)\)", miss.get("refused", ""))
    hit = m and acts.act(lab, "ghost", "fx", name="assembling-machine-2", x=float(m[1]), y=float(m[2]))
    ok = not miss["ok"] and "iron-chest" in miss["refused"] and bool(hit) and hit["ok"]
    return Result(ok, f"{miss.get('refused')}; then {hit.get('did') if hit else 'no hint'}")


@fixture(tags={"acts"})
def acts_construction_reach(lab):
    """Robots build past the logistic area (25 tiles): a point 30 tiles from the roboport is covered, one 80 off is not."""
    from . import acts
    mini_factory(lab)
    inside = acts.act(lab, "network", "fx", x=40, y=-10)
    ghost = acts.act(lab, "ghost", "fx", name="transport-belt", x=39.5, y=-10.5)
    outside = acts.act(lab, "network", "fx", x=90, y=-10)
    ok = inside["ok"] and ghost["ok"] and not ghost.get("warn") and not outside["ok"] and "nearest roboport" in outside["refused"]
    return Result(ok, f"30 tiles: {inside['ok']}, ghost warn {ghost.get('warn')}; 80 tiles: {outside.get('refused')}")
