"""Fixtures for the census, balance gate, waits census and tool registry."""

from .. import balance
from .registry import LUA, Result, fixture, near


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


@fixture(tags={"balance"})
def balance_enemy_kill_contents(lab):
    """Contents vanish with a chest that enemies destroy: excused. The same chest killed by script is not."""
    mini_factory(lab)
    kill = FX + 's.find_entities_filtered{name = "iron-chest", position = {6.5, 6.5}}[1].die(%s)'
    by_enemy, _ = windowed(lab, kill % '"enemy"', ticks=3600)
    by_script, _ = windowed(lab, kill.replace("6.5, 6.5", "-0.5, -6.5") % "", ticks=3600)
    return Result(by_enemy.ok and not by_script.ok, f"enemy: {by_enemy.summary()}; script: {by_script.summary()}")


@fixture(source="run4-closeout", tags={"balance", "slow"})
def balance_run4_untouched(lab):
    """A real base with enemies, turrets and robots: an untouched window must pass."""
    v, _ = windowed(lab)
    return Result(v.ok, v.summary(), data={"excused": v.explained_by_losses})


@fixture(source="run4-closeout", tags={"balance", "slow"})
def balance_run4_short(lab):
    """Short windows right after load: blocked drills each hold a mined item that the census must count."""
    verdicts = [windowed(lab, ticks=2700)[0] for _ in range(3)]
    return Result(all(v.ok for v in verdicts), "; ".join(v.summary() for v in verdicts))


def waits_cell(lab, cut=None):
    """Build the red-science cell, run a minute, optionally cut one input and run a minute more."""
    from .. import waits
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
    from .. import waits
    r = waits.census(lab)
    return Result(bool(r["waits"]) and r["waits"][0]["item"] == "iron-plate", "; ".join(waits.top(r, 5)),
                  data={"top": waits.top(r, 15), "other": r["other"]})


TOOL_LIB = """--- tool: fx_geom
--- kind: lib
--- effect: read
--- summary: distance helper
--- args: none
--- returns: {dist}
return {dist = function(a, b) return ((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) ^ 0.5 end}
"""

TOOL_CALL = """--- tool: fx_near
--- kind: call
--- effect: read
--- summary: count entities within r of a point, and bump a per-tool counter
--- args: x, y, r (numbers)
--- returns: {n, calls}
--- uses: fx_geom
local a = ...
local g = use("fx_geom")
local n = 0
for _, e in pairs(game.surfaces.nauvis.find_entities_filtered{position = {a.x, a.y}, radius = a.r}) do
  if g.dist(e.position, {x = a.x, y = a.y}) <= a.r then n = n + 1 end
end
storage.calls = (storage.calls or 0) + 1
return {n = n, calls = storage.calls}
"""


@fixture(tags={"tools"}, camera=True)
def tools_registry_peer(lab):
    """tools.sync and tools.call through game-bot-control 0.6 with the camera as a second peer: no desync."""
    import tempfile
    from pathlib import Path
    from .. import camera, tools
    version = lab.lua('rcon.print(script.active_mods["game-bot-control"])').strip()
    if tuple(int(p) for p in version.split(".")) < (0, 6, 1):
        return Result(True, f"skipped: game-bot-control {version} has no tool registry")
    with tempfile.TemporaryDirectory() as root:
        for name, code in (("fx_near", TOOL_CALL), ("fx_geom", TOOL_LIB)):
            (Path(root) / f"{name}.lua").write_text(code)
        order = tools.sync(lab, root=root)
    first = tools.call(lab, "fx_near", x=0, y=0, r=64)
    lab.advance(120)
    second = tools.call(lab, "fx_near", x=0, y=0, r=64)
    listed = {t["name"]: t for t in tools.listing(lab)}
    connected = lab.lua('local p = game.players["fxcam"] rcon.print(tostring(p and p.connected))').strip()
    bad = camera.desyncs(lab)
    ok = (order == ["fx_geom", "fx_near"] and first["calls"] == 1 and second["calls"] == 2
          and listed["fx_near"]["calls"] == 2 and connected == "true" and not bad)
    return Result(ok, f"order {order}; calls {first['calls']}, {second['calls']}; n {first['n']}; "
                      f"camera connected {connected}; desync lines {len(bad)}",
                  data={"desyncs": bad[:5]})
