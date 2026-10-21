"""Fixtures for the build tools under research/tools/build/ (check, route, place). Owned by scope fxlab-tools-build (T13).

The fifteen check cases port the intent-check prototype. Each builds its world on a flat surface of its own, calls
`check` through the tool registry and compares the codes, directions and types per entry. A check call must leave the
entities, items, surfaces and tick unchanged. Every fixture runs with the camera attached and ends by confirming the
camera is still connected with no desync lines.
"""

import itertools
import json
import statistics
import time

from .. import camera, tools
from .registry import Result, fixture

BUILD = ("check", "route", "place")
SEEDED = "run4-closeout+cam"
MODULE_AREA = ((111, -40), (153, -14))

PRELUDE = """
local D = defines.direction
local function mk(s, t)
  t.force = t.force or "player"
  local e = s.create_entity(t)
  assert(e, "create failed: " .. t.name .. " at " .. serpent.line(t.position))
  return e
end
local function ore(s, name, x0, y0, x1, y1)
  for x = x0, x1 do for y = y0, y1 do mk(s, {name = name, position = {x + 0.5, y + 0.5}, amount = 5000, force = "neutral"}) end end
end
local function power(s)
  local eei = mk(s, {name = "electric-energy-interface", position = {-30, -30}})
  eei.power_production = 1e8 eei.electric_buffer_size = 1e9 eei.energy = 1e9
  s.create_global_electric_network()
end
local function pipe(s, x, y, fluid)
  local p = mk(s, {name = "pipe", position = {x, y}})
  if fluid then p.insert_fluid{name = fluid, amount = 50} end
  return p
end
local s = game.create_surface(SURFACE, {width = 128, height = 128, peaceful_mode = true, no_enemies_mode = true})
s.request_to_generate_chunks({0, 0}, 2)
s.force_generate_chunk_requests()
local tiles = {}
for x = -64, 63 do for y = -64, 63 do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end end
s.set_tiles(tiles)
for _, e in pairs(s.find_entities_filtered{}) do e.destroy() end
s.always_day = true
"""

CENSUS = """
local n, items = 0, 0
for _, e in pairs(game.surfaces[SURFACE].find_entities_filtered{}) do
  n = n + 1
  if e.get_item_count then local ok, k = pcall(e.get_item_count) if ok then items = items + k end end
end
rcon.print(helpers.table_to_json({n = n, items = items, surfaces = #game.surfaces, tick = game.tick}))
"""


def lst(x):
    return list(x) if x else []


def ent(name, x, y, intent=None, accept=None, direction=None):
    out = {"name": name, "position": [x, y]}
    if intent:
        out["intent"] = intent
    if accept:
        out["accept"] = accept
    if direction is not None:
        out["direction"] = direction
    return out


def belt(x, y, flow, **kw):
    return ent("transport-belt", x, y, {"flow": flow}, **kw)


def ins(x, y, drop, name="inserter", item=None, **kw):
    return ent(name, x, y, {"drop": drop, **({"item": item} if item else {})}, **kw)


def chest(x, y):
    return ent("iron-chest", x, y)


def ug(x, y, flow, role):
    return ent("underground-belt", x, y, {"flow": flow, "role": role})


def ptg(x, y, toward):
    return ent("pipe-to-ground", x, y, {"toward": toward})


def number(lab, expr):
    return float(lab.lua(f"rcon.print({expr})"))


WORLDS = itertools.count(1)


def world(lab, tag, setup=""):
    """A flat 128 x 128 surface b-<tag>-<n> with no entities, then `setup` Lua with `s`, `mk`, `ore`, `power` and `pipe` in scope.

    Returns the surface name. The counter keeps names unique when fixtures share one lab.
    """
    surface = f"b-{tag}-{next(WORLDS)}"
    lab.lua(f'SURFACE = "{surface}"\n' + PRELUDE + setup)
    return surface


def census(lab, surface):
    return json.loads(lab.lua(f'SURFACE = "{surface}"\n' + CENSUS))


def peer(lab):
    """Whether the camera client is still connected, and its desync lines."""
    connected = lab.lua('local p = game.players["fxcam"] rcon.print(tostring(p and p.connected))').strip() == "true"
    return connected, camera.desyncs(lab)


def finish(lab, ok, detail, data=None):
    """Let the game run a moment so the camera peer sees every change, then fold its state into the result."""
    lab.advance(120)
    connected, bad = peer(lab)
    attached = camera.seat(lab) is not None
    data = dict(data or {}, camera_connected=connected, desyncs=bad[:5])
    return Result(ok and (connected or not attached) and not bad,
                  f"{detail}; camera connected {connected}, desync lines {len(bad)}", data=data)


def ready(lab):
    """Load the build tools, or say why the lab cannot. Returns the skip Result or None."""
    version = lab.lua('rcon.print(script.active_mods["game-bot-control"])').strip()
    if tuple(int(p) for p in version.split(".")) < (0, 6, 1):
        return Result(False, f"game-bot-control {version} has no tool registry")
    tools.sync(lab, names=BUILD)
    return None


def call(lab, name, **args):
    """tools.call with the wall milliseconds it took, round trip included."""
    t0 = time.perf_counter()
    r = tools.call(lab, name, **args)
    return r, (time.perf_counter() - t0) * 1000


def rcon_ms(lab, n=20):
    """The wall milliseconds of an empty RCON call, which every tool call includes."""
    times = []
    for _ in range(n):
        t0 = time.perf_counter()
        lab.lua("rcon.print(1)")
        times.append((time.perf_counter() - t0) * 1000)
    return statistics.median(times)


def engine_ms(lab, name, args, n=10, rounds=3):
    """The game's own milliseconds for one call of a tool: n calls inside one RCON command, less one call, over n - 1.

    The server runs a command in one tick, so the frame and the reply transfer cancel out. The best of `rounds` rounds
    is returned, because other labs on the box only ever add time.
    """
    src = json.dumps(args)

    def run(count):
        code = (f'local a = helpers.json_to_table([==[{src}]==]) for i = 1, {count} do '
                f'remote.call("game_bot", "tool_call", {{name = "{name}", args = a}}) end rcon.print(1)')
        t0 = time.perf_counter()
        lab.lua(code)
        return (time.perf_counter() - t0) * 1000

    return min((run(n) - run(1)) / (n - 1) for _ in range(rounds))


def codes(entry):
    return sorted(x["code"] for x in lst(entry.get("issues")))


def judge(res, expect):
    """The mismatches between a check result and the expected codes, direction and type per entry."""
    fails = []
    entries = lst(res.get("entries"))
    if len(entries) != len(expect):
        return [f"{len(entries)} entries back for {len(expect)} sent"]
    for i, (r, ex) in enumerate(zip(entries, expect), 1):
        want, got = sorted(ex.get("codes", [])), codes(r)
        if want != got:
            fails.append(f"entry {i}: want {want} got {got}")
        if "direction" in ex and ex["direction"] != r.get("direction"):
            fails.append(f"entry {i}: want direction {ex['direction']} got {r.get('direction')}")
        if "type" in ex and ex["type"] != r.get("type"):
            fails.append(f"entry {i}: want type {ex['type']} got {r.get('type')}")
    return fails


def run_check(lab, case, tag):
    skip = ready(lab)
    if skip:
        return skip
    surface = world(lab, tag, case.get("setup", ""))
    entries = case["list"](lab) if callable(case["list"]) else case["list"]
    before = census(lab, surface)
    res, ms = call(lab, "check", surface=surface, list=entries)
    after = census(lab, surface)
    fails = [] if before == after else [f"not a pure read: {before} -> {after}"]
    if "all_ok" in case:
        if not res["ok"]:
            fails.append(res["summary"])
        ms = engine_ms(lab, "check", {"surface": surface, "list": entries})
    else:
        fails += judge(res, case["expect"])
    base = rcon_ms(lab)
    detail = (f"{res['summary']}; {len(entries)} entries in {ms:.0f} ms (empty rcon {base:.0f} ms)"
              + ("; " + "; ".join(fails) if fails else ""))
    return finish(lab, not fails, detail, {"ms": round(ms, 1), "rcon_ms": round(base, 1), "entries": len(entries)})


def ug_max(lab):
    return int(number(lab, 'prototypes.entity["underground-belt"].max_underground_distance'))


def pole_reach(lab):
    return int(number(lab, 'math.floor(prototypes.entity["small-electric-pole"].get_max_wire_distance())'))


def pipe_ug_max(lab):
    return int(number(lab, '(function() for _, fb in pairs(prototypes.entity["pipe-to-ground"].fluidbox_prototypes) do '
                           'for _, c in pairs(fb.pipe_connections) do if c.connection_type == "underground" then '
                           'return c.max_underground_distance end end end end)()'))


def underground_reach_list(lab):
    m = ug_max(lab)
    return [ug(0.5, 0.5, [1, 0], "entry"), ug(0.5 + m, 0.5, [1, 0], "exit"),
            ug(0.5, 3.5, [1, 0], "entry"), ug(1.5 + m, 3.5, [1, 0], "exit"),
            ug(0.5, 6.5, [1, 0], "entry"),
            ug(0.5, 9.5, [-1, 0], "exit"), ug(4.5, 9.5, [-1, 0], "entry")]


def pole_island_list(lab):
    n = pole_reach(lab)
    return [ent("small-electric-pole", 0.5 + n, 0.5), ent("small-electric-pole", 0.5 + 2 * n, 0.5),
            ent("small-electric-pole", 0.5 + 3 * n + 2, 0.5), ent("medium-electric-pole", 0.5, 0.5 + n + 1)]


def pipe_to_ground_list(lab):
    m = pipe_ug_max(lab)
    return [ptg(0.5, 0.5, [1, 0]), ptg(4.5, 0.5, [-1, 0]), ptg(0.5, 3.5, [0, 1]), ptg(0.5, 3.5 + m + 1, [0, -1]),
            ptg(10.5, 0.5, [1, 0])]


def read_50_list(lab):
    out = []
    for k in range(6):
        x = 1.5 + 3 * k
        out.append(ent("electric-mining-drill", x, 2.5, {"output": [0, 1]}))
        out += [belt(x, 4.5, [0, 1]), belt(x, 5.5, [0, 1]), belt(x, 6.5, [0, 1]),
                belt(x, 7.5, [0, 1], accept=["BELT_SIDELOADS"]), ent("small-electric-pole", x + 1, 5.5)]
    for k in range(4):
        x = 3.5 + 3 * k
        out += [ins(x, 9.5, [0, 1]), chest(x, 10.5)]
    for k in range(2):
        out += [ug(30.5, 0.5 + 6 * k, [1, 0], "entry"), ug(33.5, 0.5 + 6 * k, [1, 0], "exit")]
    out += [ent("pipe", -4.5, 0.5), ent("pipe", -3.5, 0.5)]
    while len(out) < 50:
        out.append(chest(40.5 + len(out), 20.5))
    return out


CHECK_CASES = {
    "raw_diagonal": {
        "list": [belt(0.5, 0.5, [1, 0]), belt(0.5, 3.5, [1, 0], direction=2), belt(0.5, 6.5, [0, 1], direction=4),
                 belt(0.5, 9.5, [0, 1], direction=8), ent("iron-chest", 0.5, 12.5, direction=6)],
        "expect": [{"direction": 4}, {"codes": ["BAD_INTENT"]}, {"codes": ["BAD_INTENT"]}, {"direction": 8},
                   {"codes": ["BAD_INTENT"]}]},
    "inserter_convention": {
        "setup": """
power(s)
mk(s, {name = "iron-chest", position = {0.5, -0.5}}).insert{name = "iron-plate", count = 10}
mk(s, {name = "iron-chest", position = {0.5, 1.5}})
mk(s, {name = "iron-chest", position = {5.5, -0.5}}).insert{name = "copper-plate", count = 10}
mk(s, {name = "iron-chest", position = {5.5, 1.5}})
mk(s, {name = "inserter", position = {5.5, 0.5}, direction = D.north})
""",
        "list": [ins(0.5, 0.5, [0, 1]), ins(3.5, 0.5, [1, 0])],
        "expect": [{"direction": 0}, {"direction": 12, "codes": ["INSERTER_PICKS_NOTHING", "INSERTER_DROPS_ON_GROUND"]}]},
    "inserter_targets": {
        "setup": """
mk(s, {name = "iron-chest", position = {0.5, -0.5}})
mk(s, {name = "iron-chest", position = {6.5, -0.5}})
mk(s, {name = "small-electric-pole", position = {9.5, -0.5}})
mk(s, {name = "iron-chest", position = {9.5, 1.5}})
mk(s, {name = "transport-belt", position = {12.5, -0.5}, direction = D.east})
""",
        "list": [ins(0.5, 0.5, [0, 1]), ins(3.5, 0.5, [0, 1]), ins(6.5, 0.5, [0, 1]), chest(6.5, 1.5),
                 ins(9.5, 0.5, [0, 1]), ins(12.5, 0.5, [0, 1]),
                 ent("assembling-machine-1", 12.5, 2.5, {"recipe": "iron-gear-wheel"}),
                 ent("assembling-machine-1", 20.5, 2.5, {"recipe": "no-such-recipe"}),
                 ent("assembling-machine-1", 25.5, 2.5, {"recipe": "nuclear-fuel"})],
        "expect": [{"codes": ["INSERTER_DROPS_ON_GROUND"]}, {"codes": ["INSERTER_PICKS_NOTHING", "INSERTER_DROPS_ON_GROUND"]},
                   {}, {}, {"codes": ["INSERTER_PICKS_NOTHING"]}, {}, {}, {"codes": ["BAD_RECIPE"]}, {"codes": ["BAD_RECIPE"]}]},
    "long_handed_reach": {
        "setup": """
power(s)
mk(s, {name = "iron-chest", position = {0.5, -0.5}})
mk(s, {name = "iron-chest", position = {0.5, 2.5}})
mk(s, {name = "iron-chest", position = {5.5, -1.5}}).insert{name = "iron-plate", count = 10}
mk(s, {name = "iron-chest", position = {5.5, 2.5}})
mk(s, {name = "iron-chest", position = {10.5, -1.5}})
mk(s, {name = "iron-chest", position = {10.5, 2.5}})
""",
        "list": [ins(0.5, 0.5, [0, 1], name="long-handed-inserter"), ins(5.5, 0.5, [0, 1], name="long-handed-inserter"),
                 ins(10.5, 0.5, [0, 1]), ins(14.5, 0.5, [0, 2])],
        "expect": [{"codes": ["INSERTER_PICKS_NOTHING"], "direction": 0}, {"direction": 0},
                   {"codes": ["INSERTER_PICKS_NOTHING", "INSERTER_DROPS_ON_GROUND"]},
                   {"codes": ["BAD_INTENT", "INSERTER_PICKS_NOTHING", "INSERTER_DROPS_ON_GROUND"]}]},
    "drill_output": {
        "setup": """
power(s)
ore(s, "iron-ore", -2, -1, 2, 2)
mk(s, {name = "iron-chest", position = {0.5, -1.5}})
ore(s, "iron-ore", 10, -1, 12, 1)
""",
        "list": [ent("electric-mining-drill", 0.5, 0.5, {"output": [0, -1]}), ent("burner-mining-drill", 20, 0, {"output": [1, 0]}),
                 ent("electric-mining-drill", 11.5, 0.5, {"output": [0, 1]}), ent("burner-mining-drill", 30, 0, {"output": [1, 0]}),
                 chest(31.5, -0.5)],
        "expect": [{"direction": 0}, {"codes": ["DRILL_NO_ORE", "DRILL_DROPS_ON_GROUND"]},
                   {"direction": 8, "codes": ["DRILL_DROPS_ON_GROUND"]}, {"codes": ["DRILL_NO_ORE"], "direction": 4}, {}]},
    "underground_ends": {
        "list": [belt(0.5, 0.5, [1, 0]), ug(1.5, 0.5, [1, 0], "entry"), ug(4.5, 0.5, [1, 0], "exit"), belt(5.5, 0.5, [1, 0]),
                 ug(10.5, 0.5, [0, -1], "entry"), ug(10.5, -3.5, [0, -1], "exit")],
        "expect": [{"direction": 4}, {"direction": 4, "type": "input"}, {"direction": 4, "type": "output"}, {"direction": 4},
                   {"direction": 0, "type": "input"}, {"direction": 0, "type": "output"}]},
    "underground_reach": {
        "list": underground_reach_list,
        "expect": [{}, {}, {"codes": ["UNDERGROUND_TOO_LONG"]}, {"codes": ["UNDERGROUND_TOO_LONG"]},
                   {"codes": ["UNDERGROUND_UNPAIRED"]}, {"direction": 12, "type": "output"}, {"direction": 12, "type": "input"}]},
    "chest_on_belt": {
        "setup": 'mk(s, {name = "transport-belt", position = {0.5, 0.5}, direction = D.east})',
        "list": [chest(0.5, 0.5), chest(3.5, 0.5), belt(3.5, 0.5, [1, 0]), chest(6.5, 0.5),
                 ent("assembling-machine-1", 10.5, 0.5), ins(11.5, 1.5, [1, 0])],
        "expect": [{"codes": ["COLLIDES_WORLD"]}, {"codes": ["COLLIDES_LIST"]}, {"codes": ["COLLIDES_LIST"]}, {},
                   {"codes": ["COLLIDES_LIST"]}, {"codes": ["COLLIDES_LIST", "INSERTER_DROPS_ON_GROUND"]}]},
    "belt_joins": {
        "setup": """
for y = 0, 5 do
  local b = mk(s, {name = "transport-belt", position = {0.5, y + 0.5}, direction = D.north})
  b.get_transport_line(1).insert_at_back{name = "coal"}
end
mk(s, {name = "transport-belt", position = {10.5, 0.5}, direction = D.north})
mk(s, {name = "transport-belt", position = {20.5, 0.5}, direction = D.east})
mk(s, {name = "transport-belt", position = {41.5, 0.5}, direction = D.west})
mk(s, {name = "transport-belt", position = {50.5, 0.5}, direction = D.east})
""",
        "list": [belt(-0.5, 2.5, [1, 0]), belt(9.5, 0.5, [1, 0]), belt(19.5, 0.5, [1, 0]), belt(30.5, 0.5, [1, 0]),
                 belt(0.5, 6.5, [0, -1]), belt(40.5, 0.5, [1, 0]), belt(1.5, 3.5, [-1, 0], accept=["BELT_SIDELOADS"]),
                 belt(51.5, 0.5, [1, 0])],
        "expect": [{"codes": ["BELT_SIDELOADS"]}, {"codes": ["BELT_JOINS_FOREIGN"]}, {"codes": ["BELT_JOINS_FOREIGN"]}, {},
                   {"codes": ["BELT_JOINS_FOREIGN"]}, {"codes": ["BELT_FACES_BELT"]}, {}, {"codes": ["BELT_JOINS_FOREIGN"]}]},
    "pole_island": {
        "setup": 'mk(s, {name = "small-electric-pole", position = {0.5, 0.5}})',
        "list": pole_island_list,
        "expect": [{}, {}, {"codes": ["POLE_ISLAND"]}, {"codes": ["POLE_ISLAND"]}]},
    "fluid_mix": {
        "setup": """
pipe(s, 0.5, 0.5, "water") pipe(s, 2.5, 0.5, "crude-oil")
pipe(s, 10.5, 0.5, "water")
pipe(s, 19.5, 0.5, "water") pipe(s, 23.5, 0.5, "steam")
pipe(s, 30.5, 0.5, "water") pipe(s, 36.5, 0.5, "crude-oil")
pipe(s, 30.5, 5.5, "water")
""",
        "list": [ent("pipe", 1.5, 0.5), ent("pipe", 11.5, 0.5), ent("pipe", 12.5, 0.5), ent("pipe", 20.5, 0.5),
                 ent("pipe", 21.5, 0.5), ent("pipe", 22.5, 0.5), ptg(31.5, 0.5, [1, 0]), ptg(35.5, 0.5, [-1, 0]),
                 ptg(31.5, 5.5, [1, 0]), ptg(35.5, 5.5, [-1, 0])],
        "expect": [{"codes": ["FLUID_MIX"]}, {}, {}, {"codes": ["FLUID_MIX"]}, {"codes": ["FLUID_MIX"]}, {"codes": ["FLUID_MIX"]},
                   {"codes": ["FLUID_MIX"]}, {"codes": ["FLUID_MIX"]}, {}, {}]},
    "pipe_to_ground": {
        "list": pipe_to_ground_list,
        "expect": [{}, {}, {"codes": ["UNDERGROUND_TOO_LONG"]}, {"codes": ["UNDERGROUND_TOO_LONG"]},
                   {"codes": ["UNDERGROUND_UNPAIRED"]}]},
    "pure_read_50": {
        "setup": """
ore(s, "iron-ore", 0, 0, 20, 4)
for x = 0, 20 do mk(s, {name = "transport-belt", position = {x + 0.5, 8.5}, direction = D.east}) end
mk(s, {name = "small-electric-pole", position = {-1.5, 6.5}})
pipe(s, -5.5, 0.5, "water")
""",
        "list": read_50_list, "all_ok": True},
    "worked_example": {
        "setup": """
for y = -3, 3 do
  mk(s, {name = "transport-belt", position = {0.5, y + 0.5}, direction = D.north}).get_transport_line(2).insert_at_back{name = "iron-plate"}
end
mk(s, {name = "small-electric-pole", position = {-1.5, 2.5}})
""",
        "list": [ins(1.5, 0.5, [1, 0], item="iron-plate"), ent("assembling-machine-1", 3.5, 0.5, {"recipe": "iron-gear-wheel"}),
                 ins(5.5, 0.5, [-1, 0], item="iron-gear-wheel"), chest(6.5, 0.5), ent("small-electric-pole", 1.5, 2.5)],
        "expect": [{"direction": 12}, {}, {"direction": 4, "codes": ["INSERTER_WRONG_ITEM"]}, {}, {}]},
    "inserter_item": {
        "setup": """
for y = -3, 3 do
  mk(s, {name = "transport-belt", position = {0.5, y + 0.5}, direction = D.north}).get_transport_line(1).insert_at_back{name = "iron-plate"}
end
mk(s, {name = "iron-chest", position = {2.5, -1.5}}).insert{name = "coal", count = 50}
mk(s, {name = "iron-chest", position = {2.5, 1.5}}).insert{name = "iron-plate", count = 50}
""",
        "list": [ins(1.5, -1.5, [-1, 0], item="coal"), ins(1.5, 1.5, [-1, 0], item="iron-plate"),
                 ins(1.5, 0.5, [-1, 0], item="copper-plate"), chest(2.5, 0.5),
                 ins(1.5, 2.5, [-1, 0], item="no-such-item"), chest(2.5, 2.5)],
        "expect": [{"codes": ["INSERTER_WRONG_ITEM"]}, {}, {"codes": ["INSERTER_WRONG_ITEM"]}, {}, {"codes": ["BAD_INTENT"]}, {}]},
}


def register_check_cases():
    for key, case in CHECK_CASES.items():
        def fn(lab, case=case, key=key):
            return run_check(lab, case, key.replace("_", "-"))
        fn.__name__ = f"build_check_{key}"
        fn.__doc__ = f"check on the `{key}` case of the intent-check prototype: expected codes fire and stay clear, nothing changes."
        fixture(source="create", tags={"tools", "build"}, camera=True)(fn)


register_check_cases()


def wall(x0, y0, x1, y1):
    return f'for x = {x0}, {x1} do for y = {y0}, {y1} do mk(s, {{name = "iron-chest", position = {{x + 0.5, y + 0.5}}}}) end end\n'


def route_args(surface, a, b, box, **kw):
    return {"surface": surface, "from": {"x": a[0] + 0.5, "y": a[1] + 0.5}, "to": {"x": b[0] + 0.5, "y": b[1] + 0.5},
            "box": {"x0": box[0], "y0": box[1], "x1": box[2], "y1": box[3]}, **kw}


def route_case(lab, tag, setup, a, b, box, **kw):
    """Build the world, route, then run the returned list through check again from Python."""
    skip = ready(lab)
    if skip:
        return skip, None, None, None
    surface = world(lab, tag, setup)
    before = census(lab, surface)
    res, ms = call(lab, "route", **route_args(surface, a, b, box, **kw))
    again = None
    if isinstance(res, dict) and res.get("list"):
        again = tools.call(lab, "check", surface=surface, list=lst(res["list"]))
    return res, again, ms, before == census(lab, surface)


@fixture(source="create", tags={"tools", "build"}, camera=True)
def build_route_around_obstacle(lab):
    """A wall 6 tiles thick spans the middle: no underground clears it, so the belt goes around, and check passes the list."""
    res, again, ms, pure = route_case(lab, "route-around", wall(5, -5, 10, 5), (0, 0), (15, 0), (-4, -9, 20, 9))
    if again is None:
        return res if isinstance(res, Result) else Result(False, f"no route: {res}")
    ys = [e["position"][1] for e in res["list"]]
    ok = (res["ok"] and again["ok"] and res["undergrounds"] == 0 and res["length"] == res["belts"] > 16
          and max(abs(y) for y in ys) > 5 and not lst(res["issues"]) and pure)
    return finish(lab, ok, f"{res['summary']}; length {res['length']}, belts {res['belts']}, undergrounds {res['undergrounds']}, "
                           f"y span {min(ys):.1f}..{max(ys):.1f}, searched {res.get('searched')}; {ms:.0f} ms; pure read {pure}",
                  {"ms": round(ms, 1), "length": res["length"], "searched": res.get("searched")})


@fixture(source="create", tags={"tools", "build"}, camera=True)
def build_route_underground(lab):
    """A wall 3 thick spans the whole box: the only way through is one underground pair, entry before and exit after it."""
    res, again, ms, pure = route_case(lab, "route-ug", wall(5, -3, 7, 3), (0, 0), (11, 0), (-2, -3, 13, 3))
    if again is None:
        return res if isinstance(res, Result) else Result(False, f"no route: {res}")
    roles = [(e["name"], e["intent"].get("role")) for e in res["list"] if e["name"] == "underground-belt"]
    ok = (res["ok"] and again["ok"] and res["undergrounds"] == 1 and roles == [("underground-belt", "entry"), ("underground-belt", "exit")]
          and res["length"] == 12 and pure)
    return finish(lab, ok, f"{res['summary']}; length {res['length']}, belts {res['belts']}, undergrounds {res['undergrounds']}; "
                           f"{ms:.0f} ms; pure read {pure}", {"ms": round(ms, 1)})


@fixture(source="create", tags={"tools", "build"}, camera=True)
def build_route_no_path(lab):
    """A wall 7 thick spans the whole box: no path, so the answer is {error, hint} naming how close the search got."""
    res, again, ms, pure = route_case(lab, "route-none", wall(5, -3, 11, 3), (0, 0), (15, 0), (-2, -3, 17, 3))
    if isinstance(res, Result):
        return res
    ok = isinstance(res, dict) and "error" in res and bool(res.get("hint")) and again is None and pure
    return finish(lab, ok, f"{res.get('error')}; hint: {res.get('hint')}; {ms:.0f} ms; pure read {pure}", {"ms": round(ms, 1)})


@fixture(source="create", tags={"tools", "build"}, camera=True)
def build_route_avoids_foreign_belt(lab):
    """A tile that an existing belt feeds is not stepped on: the route detours, and check finds nothing joined."""
    setup = "".join(f'mk(s, {{name = "transport-belt", position = {{5.5, {y + 0.5}}}, direction = D.south}})\n' for y in (-2, -1, 0, 1))
    res, again, ms, pure = route_case(lab, "route-foreign", setup, (0, 2), (10, 2), (-2, -6, 14, 8))
    if again is None:
        return res if isinstance(res, Result) else Result(False, f"no route: {res}")
    stepped = [e for e in res["list"] if e["position"] == [5.5, 2.5]]
    ok = res["ok"] and again["ok"] and not stepped and not lst(res["issues"]) and pure
    return finish(lab, ok, f"{res['summary']}; length {res['length']}, undergrounds {res['undergrounds']}; stepped on the fed tile: "
                           f"{bool(stepped)}; {ms:.0f} ms; pure read {pure}", {"ms": round(ms, 1)})


@fixture(source="create", tags={"tools", "build"}, camera=True)
def build_bad_args(lab):
    """A malformed call to any build tool answers {error, hint}: no Lua error, and nothing is counted as a tool error."""
    skip = ready(lab)
    if skip:
        return skip
    s = world(lab, "bad-args")
    good = [chest(0.5, 0.5)]
    tries = {
        "check no list": ("check", {"surface": s}),
        "check list not an array": ("check", {"surface": s, "list": {"name": "iron-chest"}}),
        "check empty list": ("check", {"surface": s, "list": []}),
        "check entry not a table": ("check", {"surface": s, "list": [5]}),
        "check intent not a table": ("check", {"surface": s, "list": [{"name": "inserter", "position": [0, 0], "intent": "up"}]}),
        "check unknown surface": ("check", {"surface": "nowhere", "list": good}),
        "check unknown force": ("check", {"surface": s, "force": "nobody", "list": good}),
        "place no list": ("place", {"surface": s}),
        "place unknown surface": ("place", {"surface": "nowhere", "list": good}),
        "route no ends": ("route", {"surface": s, "box": {"x0": 0, "y0": 0, "x1": 5, "y1": 5}}),
        "route no box": ("route", {"surface": s, "from": [0, 0], "to": [3, 3]}),
        "route box too big": ("route", route_args(s, (0, 0), (3, 3), (0, 0, 200, 10))),
        "route end outside": ("route", route_args(s, (0, 0), (30, 3), (0, 0, 10, 10))),
        "route unknown belt": ("route", route_args(s, (0, 0), (3, 3), (0, 0, 10, 10), belt="no-such-belt")),
        "route diagonal flow": ("route", route_args(s, (0, 0), (3, 3), (0, 0, 10, 10), start_flow=[1, 1])),
        "check too many entries": ("check", {"surface": s, "list": [chest(0.5 + i, 0.5) for i in range(201)]}),
        "check surface a table": ("check", {"surface": {"a": 1}, "list": good}),
        "check force a table": ("check", {"surface": s, "force": {"a": 1}, "list": good}),
        "check name a table": ("check", {"surface": s, "list": [{"name": {"a": 1}, "position": [0, 0]}]}),
        "place surface a table": ("place", {"surface": [1], "list": good}),
        "route surface a table": ("route", route_args({"a": 1}, (0, 0), (3, 3), (0, 0, 10, 10))),
        "route force a table": ("route", route_args(s, (0, 0), (3, 3), (0, 0, 10, 10), force={"a": 1})),
        "route belt a table": ("route", route_args(s, (0, 0), (3, 3), (0, 0, 10, 10), belt={"a": 1})),
        "route box 49 wide": ("route", route_args(s, (0, 0), (3, 3), (0, 0, 48, 10))),
    }
    out, bad = {}, []
    for label, (name, args) in tries.items():
        try:
            r = tools.call(lab, name, **args)
        except Exception as exc:
            bad.append(f"{label}: raised {exc}")
            continue
        out[label] = r
        if not (isinstance(r, dict) and r.get("error") and r.get("hint")):
            bad.append(f"{label}: {json.dumps(r)[:120]}")
    odd = tools.call(lab, "check", surface=s, list=[{"name": "iron-chest", "position": ["a", "b"]}])
    if odd.get("ok") is not False or codes(lst(odd["entries"])[0]) != ["BAD_INTENT"]:
        bad.append(f"check position text: {json.dumps(odd)[:120]}")
    for name in ("entity-ghost", "iron-ore", "character"):
        r = tools.call(lab, "check", surface=s, list=[ent(name, 0.5, 0.5)])
        if r.get("ok") is not False or codes(lst(r["entries"])[0]) != ["BAD_INTENT"]:
            bad.append(f"check {name}: {json.dumps(r)[:120]}")
    errors = {t["name"]: t["errors"] for t in tools.listing(lab) if t["name"] in BUILD}
    ok = not bad and not any(errors.values())
    return finish(lab, ok, f"{len(tries) - len(bad)} of {len(tries)} answered {{error, hint}}; tool errors {errors}"
                           + ("; " + "; ".join(bad) if bad else ""))


PLACE_WORLD = """
for y = -3, 3 do
  mk(s, {name = "transport-belt", position = {0.5, y + 0.5}, direction = D.north}).get_transport_line(2).insert_at_back{name = "iron-plate"}
end
mk(s, {name = "small-electric-pole", position = {-1.5, 2.5}})
"""

GHOSTS = """
local g, real = 0, 0
for _, e in pairs(game.surfaces[SURFACE].find_entities_filtered{}) do
  if e.name == "entity-ghost" then g = g + 1 else real = real + 1 end
end
rcon.print(helpers.table_to_json({ghosts = g, real = real}))
"""


GHOST_LIST = """
local out = {}
for _, g in pairs(game.surfaces[SURFACE].find_entities_filtered{name = "entity-ghost"}) do
  local r = nil
  if g.ghost_type == "assembling-machine" then local ok, v = pcall(g.get_recipe) r = ok and v and v.name or nil end
  out[#out + 1] = {name = g.ghost_name, x = g.position.x, y = g.position.y, direction = g.direction, recipe = r}
end
rcon.print(helpers.table_to_json(out))
"""


def ghosts(lab, surface):
    return json.loads(lab.lua(f'SURFACE = "{surface}"\n' + GHOSTS))


def clean_cell():
    """The worked example with its output arm the right way round, plus a belt run with an underground hop."""
    return [ins(1.5, 0.5, [1, 0], item="iron-plate"), ent("assembling-machine-1", 3.5, 0.5, {"recipe": "iron-gear-wheel"}),
            ins(5.5, 0.5, [1, 0], item="iron-gear-wheel"), chest(6.5, 0.5), ent("small-electric-pole", 1.5, 2.5),
            belt(0.5, 6.5, [1, 0]), belt(1.5, 6.5, [1, 0]), ug(2.5, 6.5, [1, 0], "entry"), ug(5.5, 6.5, [1, 0], "exit"),
            belt(6.5, 6.5, [1, 0])]


@fixture(source="create", tags={"tools", "build"}, camera=True)
def build_place_clean_list(lab):
    """A clean list places every entry as a ghost at the checked direction, with its recipe, and creates nothing built."""
    skip = ready(lab)
    if skip:
        return skip
    surface = world(lab, "place-clean", PLACE_WORLD)
    entries = clean_cell()
    before = ghosts(lab, surface)
    res, ms = call(lab, "place", surface=surface, list=entries)
    after = ghosts(lab, surface)
    found = json.loads(lab.lua(f'SURFACE = "{surface}"\n' + GHOST_LIST))
    want = {(p["name"], p["position"][0], p["position"][1], p["direction"]) for p in lst(res.get("placed"))}
    got = {(g["name"], g["x"], g["y"], g["direction"]) for g in found}
    recipe = [g["recipe"] for g in found if g["name"] == "assembling-machine-1"]
    ok = (res.get("ok") and len(lst(res["placed"])) == len(entries) and want == got and len(found) == len(entries)
          and after["ghosts"] == len(entries) and after["real"] == before["real"] and recipe == ["iron-gear-wheel"])
    return finish(lab, ok, f"{res.get('summary')}; ghosts {before['ghosts']} -> {after['ghosts']}, built {before['real']} -> "
                           f"{after['real']}; recipe {recipe}; {ms:.0f} ms; warn {res.get('warn')}", {"ms": round(ms, 1)})


@fixture(source="create", tags={"tools", "build"}, camera=True)
def build_place_one_bad_entry(lab):
    """One failing entry in an otherwise clean list: nothing is placed and the issue names the entry."""
    skip = ready(lab)
    if skip:
        return skip
    surface = world(lab, "place-bad", PLACE_WORLD)
    entries = clean_cell()
    entries.insert(4, ins(20.5, 0.5, [0, 1]))
    before = ghosts(lab, surface)
    res, ms = call(lab, "place", surface=surface, list=entries)
    after = ghosts(lab, surface)
    issues = lst(res.get("issues"))
    ok = (res.get("ok") is False and not lst(res.get("placed")) and after == before
          and sorted({x["code"] for x in issues}) == ["INSERTER_DROPS_ON_GROUND", "INSERTER_PICKS_NOTHING"]
          and {x["i"] for x in issues} == {5})
    return finish(lab, ok, f"{res.get('summary')}; ghosts {before['ghosts']} -> {after['ghosts']}; issues "
                           f"{[(x['i'], x['code']) for x in issues]}; {ms:.0f} ms", {"ms": round(ms, 1)})


RUN4_RECT = ((20, 0), (40, 20))
COPY_TYPES = ("transport-belt", "underground-belt", "splitter", "inserter", "mining-drill", "assembling-machine", "furnace",
              "electric-pole", "pipe", "pipe-to-ground", "container", "logistic-container", "lab", "boiler", "storage-tank",
              "pump", "offshore-pump", "generator")

# Reads the real entities of a run4 rect, up to 26 machines, inserters, poles and pipes and then 24 belts and undergrounds,
# nearest the middle first, destroys them in this throwaway world and returns each
# as a check entry with the intent its real state implies (an inserter drops where its hand drops, a drill outputs where it
# drops). The check then runs against the surroundings alone, so every issue it raises is judged against a layout that worked.
COPY_OUT = """
local s = game.surfaces.nauvis
local C = {[0] = {0, -1}, [4] = {1, 0}, [8] = {0, 1}, [12] = {-1, 0}}
local function card(dx, dy)
  if math.abs(dx) > math.abs(dy) then return {dx > 0 and 1 or -1, 0} end
  return {0, dy > 0 and 1 or -1}
end
local types = {}
for _, t in pairs(TYPES) do types[t] = true end
local found = {}
for _, e in pairs(s.find_entities_filtered{area = AREA, force = "player"}) do
  if types[e.type] then found[#found + 1] = e end
end
local cx, cy = (AREA[1][1] + AREA[2][1]) / 2, (AREA[1][2] + AREA[2][2]) / 2
table.sort(found, function(a, b)
  local da, db = (a.position.x - cx) ^ 2 + (a.position.y - cy) ^ 2, (b.position.x - cx) ^ 2 + (b.position.y - cy) ^ 2
  if da ~= db then return da < db end
  return a.unit_number < b.unit_number
end)
local belts = {transport_belt = true, ["transport-belt"] = true, ["underground-belt"] = true, splitter = true}
local picked, rest = {}, {}
for _, e in ipairs(found) do
  if belts[e.type] or #picked >= COUNT - BELTS then rest[#rest + 1] = e else picked[#picked + 1] = e end
end
for _, e in ipairs(rest) do
  if #picked < COUNT and belts[e.type] then picked[#picked + 1] = e end
end
for _, e in ipairs(rest) do
  if #picked < COUNT and not belts[e.type] then picked[#picked + 1] = e end
end
found = picked
local out, kinds = {}, {}
for i = 1, #found do
  local e = found[i]
  local r = {name = e.name, position = {e.position.x, e.position.y}}
  local t = e.type
  if t == "inserter" then r.intent = {drop = card(e.drop_position.x - e.position.x, e.drop_position.y - e.position.y)}
  elseif t == "mining-drill" then r.intent = {output = card(e.drop_position.x - e.position.x, e.drop_position.y - e.position.y)}
  elseif t == "transport-belt" or t == "splitter" then r.intent = {flow = C[e.direction]}
  elseif t == "underground-belt" then r.intent = {flow = C[e.direction], role = e.belt_to_ground_type == "input" and "entry" or "exit"}
  elseif t == "pipe-to-ground" then
    for _, fb in pairs(e.prototype.fluidbox_prototypes) do
      for _, c in pairs(fb.pipe_connections) do
        if c.connection_type == "underground" then r.intent = {toward = C[(c.direction + e.direction) % 16]} end
      end
    end
  else
    r.direction = e.direction
    if t == "assembling-machine" then
      local rec = e.get_recipe()
      if rec then r.intent = {recipe = rec.name} end
    end
  end
  out[#out + 1] = r
  kinds[t] = (kinds[t] or 0) + 1
end
for i = 1, #found do found[i].destroy() end
rcon.print(helpers.table_to_json({list = out, kinds = kinds}))
"""


@fixture(source=SEEDED, tags={"tools", "build", "slow"}, camera=True)
def build_check_run4_false_positives(lab):
    """check on 50 real run4 entities, read from a rect and removed from the world first, so each issue it raises is a false positive."""
    skip = ready(lab)
    if skip:
        return skip
    area = [list(RUN4_RECT[0]), list(RUN4_RECT[1])]
    copied = json.loads(lab.lua(f"AREA = {json.dumps(area).replace('[', '{').replace(']', '}')}\n"
                                f"COUNT = 50\nBELTS = 24\nTYPES = {json.dumps(list(COPY_TYPES)).replace('[', '{').replace(']', '}')}\n" + COPY_OUT))
    entries = lst(copied["list"])
    res, ms = call(lab, "check", list=entries)
    if "entries" not in res:
        return Result(False, f"check answered {res}")
    failing = [(i + 1, entries[i], r) for i, r in enumerate(lst(res["entries"])) if lst(r.get("issues"))]
    by_code = {}
    for i, e, r in failing:
        for x in r["issues"]:
            by_code.setdefault(x["code"], []).append({"i": i, "name": e["name"], "position": e["position"], "msg": x["msg"]})
    detail = (f"{len(entries)} entries ({dict(copied['kinds'])}), {len(failing)} with issues "
              f"{ {c: len(v) for c, v in sorted(by_code.items())} }; {ms:.0f} ms")
    ok = len(entries) == 50 and len(lst(res["entries"])) == 50
    return finish(lab, ok, detail, {"false_positives": by_code, "kinds": dict(copied["kinds"]), "ms": round(ms, 1)})


# The first free w x h block of land found on rings around the roboports, clear of every entity but ore and inside a
# construction area that holds robots. Prints the block's top-left tile, or nothing.
FREE_SPOT = """
local s = game.surfaces.nauvis
local f = game.forces.player
local function free(x0, y0)
  for _, e in pairs(s.find_entities_filtered{area = {{x0 - 1, y0 - 1}, {x0 + W + 1, y0 + H + 1}}}) do
    if e.type ~= "resource" and e.type ~= "character" and not e.type:find("robot") then return false end
  end
  for x = x0, x0 + W - 1 do for y = y0, y0 + H - 1 do
    if not s.can_place_entity{name = "iron-chest", position = {x + 0.5, y + 0.5}, force = f, build_check_type = defines.build_check_type.manual_ghost} then return false end
  end end
  local nets = s.find_logistic_networks_by_construction_area({x0 + W / 2, y0 + H / 2}, f)
  return nets[1] ~= nil and nets[1].available_construction_robots > 0
end
local ports = s.find_entities_filtered{type = "roboport", force = "player"}
table.sort(ports, function(a, b) return a.unit_number < b.unit_number end)
for _, r in ipairs(ports) do
  for ring = 6, 40, 2 do
    for dx = -ring, ring, 2 do
      for _, dy in ipairs{-ring, ring} do
        local x, y = math.floor(r.position.x) + dx, math.floor(r.position.y) + dy
        if free(x, y) then rcon.print(x .. "," .. y) return end
        x, y = math.floor(r.position.x) + dy, math.floor(r.position.y) + dx
        if free(x, y) then rcon.print(x .. "," .. y) return end
      end
    end
  end
end
"""

BUILT = """
local s = game.surfaces.nauvis
local out = {ghosts = 0, built = {}}
for _, e in pairs(s.find_entities_filtered{area = AREA}) do
  if e.name == "entity-ghost" then out.ghosts = out.ghosts + 1
  elseif e.type ~= "resource" and e.type ~= "character" and not e.type:find("robot") then
    local r = {name = e.name, x = e.position.x, y = e.position.y, direction = e.direction}
    if e.type == "inserter" then r.pick = {e.pickup_position.x, e.pickup_position.y} r.drop = {e.drop_position.x, e.drop_position.y} end
    if e.type == "underground-belt" then r.ug = e.belt_to_ground_type r.linked = e.underground_belt_neighbour ~= nil end
    if e.type == "assembling-machine" then local rec = e.get_recipe() r.recipe = rec and rec.name end
    out.built[#out.built + 1] = r
  end
end
rcon.print(helpers.table_to_json(out))
"""


def robot_cell(ox, oy):
    """A chest, an arm, an assembler, an arm and a chest in a row, and under it a belt run with an underground hop."""
    return [chest(ox + 0.5, oy + 0.5), ins(ox + 1.5, oy + 0.5, [1, 0]),
            ent("assembling-machine-1", ox + 3.5, oy + 0.5, {"recipe": "iron-gear-wheel"}),
            ins(ox + 5.5, oy + 0.5, [1, 0]), chest(ox + 6.5, oy + 0.5),
            belt(ox + 0.5, oy + 4.5, [1, 0]), belt(ox + 1.5, oy + 4.5, [1, 0]), ug(ox + 2.5, oy + 4.5, [1, 0], "entry"),
            ug(ox + 5.5, oy + 4.5, [1, 0], "exit"), belt(ox + 6.5, oy + 4.5, [1, 0])]


@fixture(source=SEEDED, tags={"tools", "build", "slow"}, camera=True)
def build_route_robots_flow(lab):
    """A route with an underground hop, placed by `place` and built by robots, carries a plate from its first belt to its last."""
    skip = ready(lab)
    if skip:
        return skip
    w, h = 14, 9
    spot = lab.lua(f"W = {w}\nH = {h}\n" + FREE_SPOT).strip()
    if not spot:
        return Result(False, "no free spot in reach of a roboport with robots")
    ox, oy = (int(v) for v in spot.split(","))
    lab.lua(f"""local s = game.surfaces.nauvis
for x = {ox + 5}, {ox + 7} do for y = {oy}, {oy + h - 1} do s.create_entity{{name = "iron-chest", position = {{x + 0.5, y + 0.5}}, force = "player"}} end end""")
    routed, ms = call(lab, "route", **route_args("nauvis", (ox, oy + 4), (ox + w - 1, oy + 4), (ox, oy, ox + w - 1, oy + h - 1)))
    if "error" in routed:
        return Result(False, f"no route: {routed}")
    placed = tools.call(lab, "place", list=lst(routed["list"]))
    t0, ticks = time.time(), 0
    area = f"{{{{{ox - 1}, {oy - 1}}}, {{{ox + w + 1}, {oy + h + 1}}}}}"
    while ticks < 7200:
        lab.advance(300)
        ticks += 300
        state = json.loads(lab.lua(f"AREA = {area}\n" + BUILT))
        if state["ghosts"] == 0:
            break
    first, last = routed["list"][0]["position"], routed["list"][-1]["position"]
    lab.lua(f"""local s = game.surfaces.nauvis
s.find_entities_filtered{{name = "transport-belt", position = {{{first[0]}, {first[1]}}}}}[1].get_transport_line(1).insert_at_back{{name = "iron-plate"}}""")
    lab.advance(900)
    carried = lab.lua(f"""local s = game.surfaces.nauvis
local b = s.find_entities_filtered{{name = "transport-belt", position = {{{last[0]}, {last[1]}}}}}[1]
local n = 0
for i = 1, b.get_max_transport_line_index() do n = n + b.get_transport_line(i).get_item_count("iron-plate") end
rcon.print(n)""").strip()
    ok = (routed["ok"] and routed["undergrounds"] == 1 and placed.get("ok") and state["ghosts"] == 0 and carried == "1")
    return finish(lab, ok, f"spot ({ox}, {oy}); route length {routed['length']}, undergrounds {routed['undergrounds']}; "
                           f"{placed.get('summary')}; ghosts left {state['ghosts']} after {ticks} ticks ({time.time() - t0:.0f} s); "
                           f"plates on the last belt {carried}", {"ticks": ticks, "spot": [ox, oy]})


@fixture(source=SEEDED, tags={"tools", "build", "slow"}, camera=True)
def build_place_robots_build(lab):
    """A list placed by `place` inside run4's robot network is built by construction robots with the arms facing as checked."""
    skip = ready(lab)
    if skip:
        return skip
    w, h = 9, 7
    spot = lab.lua(f"W = {w}\nH = {h}\n" + FREE_SPOT).strip()
    if not spot:
        return Result(False, "no free spot in reach of a roboport with robots")
    ox, oy = (int(v) for v in spot.split(","))
    entries = robot_cell(ox, oy)
    area = f"{{{{{ox - 1}, {oy - 1}}}, {{{ox + w + 1}, {oy + h + 1}}}}}"
    res, ms = call(lab, "place", list=entries)
    if not res.get("ok"):
        return Result(False, f"place refused at ({ox}, {oy}): {res.get('summary')} {res.get('issues')}")
    t0, ticks = time.time(), 0
    while ticks < 7200:
        lab.advance(300)
        ticks += 300
        state = json.loads(lab.lua(f"AREA = {area}\n" + BUILT))
        if state["ghosts"] == 0:
            break
    built = {(b["name"], b["x"], b["y"]): b for b in lst(state["built"])}
    want = {(e["name"], e["position"][0], e["position"][1]) for e in entries}
    arms = [b for b in built.values() if b["name"] == "inserter"]
    arms_ok = all(abs(a["pick"][0] - (a["x"] - 1)) < 0.3 and abs(a["drop"][0] - (a["x"] + 1)) < 0.3
                  and abs(a["pick"][1] - a["y"]) < 0.3 for a in arms)
    ugs = sorted(b["ug"] for b in built.values() if b["name"] == "underground-belt")
    linked = all(b["linked"] for b in built.values() if b["name"] == "underground-belt")
    recipe = [b["recipe"] for b in built.values() if b["name"] == "assembling-machine-1"]
    ok = (state["ghosts"] == 0 and set(built) == want and len(arms) == 2 and arms_ok and ugs == ["input", "output"]
          and linked and recipe == ["iron-gear-wheel"] and not res.get("warn"))
    return finish(lab, ok, f"spot ({ox}, {oy}); {res['summary']}; ghosts left {state['ghosts']} after {ticks} ticks "
                           f"({time.time() - t0:.0f} s); built {len(built)} of {len(want)}; arms ok {arms_ok}; undergrounds {ugs} "
                           f"linked {linked}; recipe {recipe}; warn {res.get('warn')}", {"ticks": ticks, "spot": [ox, oy]})


CAP_MS = 20


def cap_lists():
    """The largest lists check accepts: 200 entries, mixed with a 50-pole chain, and 200 pipe-to-ground ends."""
    mixed = [belt(-59.5 + i, -49.5, [1, 0]) for i in range(60)]
    mixed += [ent("small-electric-pole", -52.5 + 7 * (i % 16), -59.5 + 7 * (i // 16)) for i in range(50)]
    for i in range(45):
        mixed += [chest(-59.5 + 2 * i, -34.5), ins(-59.5 + 2 * i, -33.5, [0, 1])]
    mixed += [chest(-59.5 + i, -28.5) for i in range(200 - len(mixed))]
    pipes = [x for j in range(100) for x in (ptg(-59.5 + 12 * (j % 5), -59.5 + 2 * (j // 5), [1, 0]),
                                             ptg(-54.5 + 12 * (j % 5), -59.5 + 2 * (j // 5), [-1, 0]))]
    return {"mixed": mixed, "underground pipes": pipes}


@fixture(source="create", tags={"tools", "build"}, camera=True)
def build_cost_at_caps(lab):
    """A call runs in one tick on every peer, so each build tool must stay near 20 ms of engine time at its caps."""
    skip = ready(lab)
    if skip:
        return skip
    surface = world(lab, "cost", 'mk(s, {name = "small-electric-pole", position = {-59.5, -59.5}})')
    times, notes = {}, []
    for label, entries in cap_lists().items():
        assert len(entries) == 200, (label, len(entries))
        res = tools.call(lab, "check", surface=surface, list=entries)
        times[f"check {label}"] = engine_ms(lab, "check", {"surface": surface, "list": entries})
        if label == "mixed" and (len(lst(res["entries"])) != 200 or any(x["code"] == "POLE_ISLAND" for r in lst(res["entries"])
                                                                         for x in lst(r.get("issues")))):
            notes.append("the pole chain was not seen as linked")
    wall = "".join(f'mk(s, {{name = "iron-chest", position = {{{x + 0.5}, {y + 0.5}}}}})\n' for x in range(36, 45) for y in range(48))
    box = (0, 0, 47, 47)
    shut = world(lab, "cost-shut", wall)
    args = route_args(shut, (2, 24), (46, 24), box)
    answer = tools.call(lab, "route", **args)
    if "error" not in answer:
        notes.append("the unreachable route answered a path")
    times["route unreachable 48x48"] = engine_ms(lab, "route", args, n=5)
    ring = "".join(f'mk(s, {{name = "iron-chest", position = {{{x + 0.5}, {y + 0.5}}}}})\n'
                   for x in range(30, 47) for y in range(10, 27) if x < 35 or x > 41 or y < 15 or y > 21)
    sealed = world(lab, "cost-ring", ring)
    args = route_args(sealed, (2, 40), (38, 18), box)
    tools.call(lab, "route", **args)
    times["route goal walled in"] = engine_ms(lab, "route", args, n=5)
    over = [k for k, v in times.items() if v > CAP_MS]
    detail = "; ".join(f"{k} {v:.1f} ms" for k, v in times.items()) + (f"; over {CAP_MS} ms: {over}" if over else "")
    return finish(lab, not over and not notes, detail + ("; " + "; ".join(notes) if notes else ""),
                  {k: round(v, 1) for k, v in times.items()})
