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
