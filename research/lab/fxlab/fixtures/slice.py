"""Fixtures for slicing and reset. Owned by scope fxlab-slice (T4).

Lua profilers cannot be read as numbers, so the slice verbs report no `ms` in their reply. `timed` calls a verb
and reads the phase timings that the mod prints through `slice_timing` in the same RCON call.
"""

import json
import re
import statistics

from ..lab import SbxError
from .registry import Result, fixture

RED_GREEN = [[111, -40], [153, -14]]
CUT_2X2 = [[64, 0], [128, 64]]
INPLACE_MARGIN = 16

_LAP = re.compile(r"^(\w+)\s+Duration: ([\d.]+)\s*(ms|s|us|µs|ns)?", re.M)
_UNIT = {"s": 1000.0, "ms": 1.0, "us": 1e-3, "µs": 1e-3, "ns": 1e-6, None: 1.0}


def timed(lab, verb, **args):
    """Call an sbx verb. Returns its reply with `ms` replaced by {phase: milliseconds, "total": sum}."""
    src = json.dumps(args)
    out = lab.lua(f'local r = remote.call("sbx", "{verb}", helpers.json_to_table([==[{src}]==])) '
                  f'rcon.print(helpers.table_to_json({{r = r}})) remote.call("sbx", "slice_timing", {{}})')
    first, _, rest = out.partition("\n")
    reply = json.loads(first)["r"]
    if isinstance(reply, dict) and reply.get("ok") is False:
        raise SbxError(reply.get("error", "error"), reply.get("detail", ""))
    ms = {name: float(value) * _UNIT[unit] for name, value, unit in _LAP.findall(rest)}
    ms["total"] = sum(ms.values())
    reply["ms"] = ms
    reply["raw"] = rest.strip()
    return reply


def _listing(x):
    return list(x) if x else []


def _production(lab, name):
    out = lab.lua(
        f'local f = game.forces["sbx-{name}"] '
        f'local st = f.get_item_production_statistics(game.surfaces["sbx-{name}"]) '
        'rcon.print(helpers.table_to_json({red = st.get_input_count("automation-science-pack"), '
        'green = st.get_input_count("logistic-science-pack")}))')
    return json.loads(out)


def _digest(lab, name, which):
    return lab.sbx("slice_fingerprint", name=name, which=which)["digest"]


def _rail_rect(lab):
    """The 64x64 chunk-aligned rectangle of the base with the most rails, or None."""
    out = lab.lua(
        'local n = {} for _, r in pairs(game.surfaces.nauvis.find_entities_filtered{type = '
        '{"straight-rail", "curved-rail-a", "curved-rail-b", "half-diagonal-rail"}}) do '
        'local k = math.floor(r.position.x / 64) .. "," .. math.floor(r.position.y / 64) n[k] = (n[k] or 0) + 1 end '
        'local best, bk = 0 for k, c in pairs(n) do if c > best then best, bk = c, k end end rcon.print(bk or "")')
    if not out.strip():
        return None
    cx, cy = (int(v) for v in out.strip().split(","))
    return [[cx * 64, cy * 64], [cx * 64 + 64, cy * 64 + 64]]


def _verbs(lab):
    return set(_listing(lab.sbx("verbs")["verbs"]))


def _counts(lab, surface, area, names):
    """Entities per name in a rectangle."""
    code = (f'local s = game.surfaces["{surface}"] local out = {{}} '
            f'for _, n in ipairs(helpers.json_to_table([==[{json.dumps(names)}]==])) do '
            f'out[n] = #s.find_entities_filtered{{area = helpers.json_to_table([==[{json.dumps(area)}]==]), name = n}} end '
            'rcon.print(helpers.table_to_json(out))')
    return json.loads(lab.lua(code))


CLOSER_NAMES = ["infinity-chest", "infinity-pipe", "loader-1x1", "electric-energy-interface"]


@fixture(source="run4-closeout", tags={"slice", "god"})
def slice_redgreen(lab):
    """The red/green science module runs alone on a slice with nothing left unhandled."""
    r = lab.sbx("slice_build", name="rg", area=RED_GREEN)
    unhandled = _listing(r["unhandled"])
    if unhandled:
        return Result(False, f"unhandled ports: {unhandled}")
    before = _production(lab, "rg")
    lab.advance(3600)
    after = _production(lab, "rg")
    red, green = after["red"] - before["red"], after["green"] - before["green"]
    data = {"red_per_min": red, "green_per_min": green, "entities": r["entities"], "ports": len(_listing(r["ports"]))}
    if red <= 0 or green <= 0:
        return Result(False, f"science did not rise: red {red}, green {green}", data=data)
    return Result(True, f"red {red}/min, green {green}/min over 3600 ticks", data=data)


def _reset_is_exact(lab, name, area):
    lab.sbx("slice_build", name=name, area=area)
    lab.advance(3600)
    during = _digest(lab, name, "play")
    reset = timed(lab, "slice_reset", name=name)
    play, snap = _digest(lab, name, "play"), _digest(lab, name, "snapshot")
    return play == snap, {"drifted": during != snap, "reset_ms": round(reset["ms"]["total"], 1), "entities": reset["entities"]}


@fixture(source="run4-closeout", tags={"slice", "fidelity"})
def slice_reset_exact(lab):
    """F3: after a run and a reset, the play surface fingerprints exactly like the snapshot."""
    data = {}
    for name, area in (("rg", RED_GREEN), ("c2", CUT_2X2)):
        exact, info = _reset_is_exact(lab, name, area)
        data[name] = info
        if not exact:
            return Result(False, f"{name}: play differs from the snapshot after reset", data=data)
        if not info["drifted"]:
            return Result(False, f"{name}: the slice did not change in 3600 ticks, so the reset proves nothing", data=data)
    return Result(True, "play equals snapshot after reset on both cuts", data=data)


@fixture(source="run4-closeout", tags={"slice", "slow"})
def slice_reset_speed(lab):
    """A reset of the 2x2-chunk cut takes at most 100 ms, a reset of the whole base at most 1000 ms (median of 3).

    A run that parsed no phase fails: with no laps the total would read 0 ms and pass any limit.
    """
    limits = {"c2": 100.0, "wb": 1000.0}
    data = {}
    ok = True
    for name in ("c2", "wb"):
        if name == "c2":
            area = CUT_2X2
        else:
            area = lab.sbx("slice_area_of_base", pad=32)["area"]
        built = timed(lab, "slice_build", name=name, area=area)
        lab.advance(600)
        replies = [timed(lab, "slice_reset", name=name) for _ in range(3)]
        runs = [r["ms"] for r in replies]
        phases = [{k: round(v, 1) for k, v in r.items() if k != "total"} for r in runs]
        data[name] = {"entities": built["entities"], "build_phases": len(built["ms"]) - 1, "limit": limits[name],
                      "build_ms": round(built["ms"]["total"]), "reset_runs": phases,
                      "reset_totals": [round(r["total"], 1) for r in runs], "raw": [r["raw"] for r in replies]}
        if built["ms"].keys() == {"total"} or any(not p for p in phases):
            return Result(False, f"{name}: no phase timing parsed from slice_timing", data=data)
        median = statistics.median(r["total"] for r in runs)
        data[name]["reset_ms_median"] = round(median, 1)
        ok = ok and median <= limits[name]
    detail = ", ".join(f"{n}: {d['reset_ms_median']} ms of {d['limit']}" for n, d in data.items())
    return Result(ok, detail, data=data)


@fixture(source="run4-closeout", tags={"slice"})
def slice_arbitrary_cut(lab):
    """A cut through the middle of the base: tanks and underground pipes close, every refusal says why, rails are listed."""
    r = lab.sbx("slice_build", name="c2", area=CUT_2X2)
    ports, unhandled, rails = _listing(r["ports"]), _listing(r["unhandled"]), _listing(r["rails"])
    data = {"ports": len(ports), "unhandled": unhandled, "rails": len(rails), "rail_count": r["rail_count"]}
    kinds = {}
    for p in ports:
        kinds[p["kind"]] = kinds.get(p["kind"], 0) + 1
    data["kinds"] = kinds
    if not any(p["kind"] == "tank" and p.get("closer") for p in ports):
        return Result(False, "no closed tank port in a cut that crosses a tank", data=data)
    if not any(p.get("how") == "fluid-under" and p.get("closer") for p in ports):
        return Result(False, "no closed pipe-to-ground port in a cut that crosses undergrounds", data=data)
    open_ones = [u for u in unhandled if u["name"] in ("storage-tank", "pipe-to-ground")]
    if open_ones:
        return Result(False, f"tank or pipe-to-ground ports left open: {open_ones}", data=data)
    if any(not u.get("reason") for u in unhandled):
        return Result(False, "an unhandled port has no reason", data=data)
    rail_rect = _rail_rect(lab)
    if rail_rect:
        rl = lab.sbx("slice_build", name="rl", area=rail_rect)
        listed = _listing(rl["rails"])
        data["rail_cut"] = {"area": rail_rect, "rail_count": rl["rail_count"], "listed": len(listed)}
        if rl["rail_count"] == 0 or not listed:
            return Result(False, "a cut through rails lists no rails", data=data)
        if any(p["kind"] not in ("belt", "pipe", "inserter", "splitter", "tank", "power") for p in _listing(rl["ports"])):
            return Result(False, "a rail was reported as a port", data=data)
    scripted = [p for p in ports if p.get("scripted") and p.get("how") == "belt-in"]
    data["scripted_feeds"] = len(scripted)
    if scripted:
        probe = json.dumps([[p["name"], p["x"], p["y"]] for p in scripted])
        code = ('local s = game.surfaces["sbx-c2"] local n = 0 '
                f'for _, k in ipairs(helpers.json_to_table([==[{probe}]==])) do local e = s.find_entity(k[1], {{k[2], k[3]}}) '
                'if e then n = n + #e.get_transport_line(1) + #e.get_transport_line(2) end end rcon.print(n)')
        lab.advance(600)
        fed = int(lab.lua(code))
        lab.sbx("slice_reset", name="c2")
        lab.advance(600)
        fed_after_reset = int(lab.lua(code))
        data["fed_items"] = fed
        data["fed_items_after_reset"] = fed_after_reset
        if fed == 0 or fed_after_reset == 0:
            return Result(False, "scripted feeds put nothing on the cut belts", data=data)
    rail_cut = data.get("rail_cut", {})
    return Result(True, f"{len(ports)} ports, {len(unhandled)} unhandled (all with a reason); a rail cut lists "
                        f"{rail_cut.get('listed', 0)} of {rail_cut.get('rail_count', 0)} rails", data=data)


@fixture(source="run4-closeout", tags={"slice"})
def slice_inplace_restore(lab):
    """The in-place arm cuts the module out of the live base and `slice_drop` leaves the base as it was."""
    margin = INPLACE_MARGIN
    area = [[RED_GREEN[0][0] - margin, RED_GREEN[0][1] - margin], [RED_GREEN[1][0] + margin, RED_GREEN[1][1] + margin]]
    before = lab.sbx("slice_fingerprint", area=area, surface="nauvis")
    wires_before = _crossing(lab, RED_GREEN)
    r = lab.sbx("slice_inplace", name="ip", area=RED_GREEN)
    data = {"entities": before["entities"], "stashed": r.get("stashed"), "ports": len(_listing(r["ports"])),
            "unhandled": _listing(r["unhandled"]), "wires_before": wires_before}
    cut = lab.sbx("slice_fingerprint", area=area, surface="nauvis")
    if cut["digest"] == before["digest"]:
        return Result(False, "the in-place cut changed nothing", data=data)
    data["wires_cut"] = _crossing(lab, RED_GREEN)
    if any(data["wires_cut"].values()):
        return Result(False, f"wires still cross the edge of the in-place cut: {data['wires_cut']}", data=data)
    lab.sbx("slice_drop", name="ip")
    after = lab.sbx("slice_fingerprint", area=area, surface="nauvis")
    data["wires_after"] = _crossing(lab, RED_GREEN)
    if data["wires_after"] != wires_before:
        return Result(False, f"the wires did not come back: {wires_before} -> {data['wires_after']}", data=data)
    lab.advance(5)
    leftover = lab.lua('local n = 0 for name in pairs(game.surfaces) do if name:find("fxlab%-stash") then n = n + 1 end end '
                       'rcon.print(n)')
    data["entities_after"] = after["entities"]
    if after["digest"] != before["digest"]:
        return Result(False, f"the base differs after the drop: {before['entities']} -> {after['entities']} entities", data=data)
    if int(leftover) or _listing(lab.sbx("sandbox_list")["sandboxes"]):
        return Result(False, "the stash surface or the box survived the drop", data=data)
    return Result(True, f"restored {before['entities']} entities exactly", data=data)


def _surface_counts(lab, surface, names):
    """Entities per name over the whole surface."""
    code = (f'local s = game.surfaces["{surface}"] local out = {{}} '
            f'for _, n in ipairs(helpers.json_to_table([==[{json.dumps(names)}]==])) do '
            'out[n] = #s.find_entities_filtered{name = n} end rcon.print(helpers.table_to_json(out))')
    return json.loads(lab.lua(code))


def _power_status(lab, surface):
    """Machine and inserter statuses on a surface, as {status name: count}."""
    code = (f'local s = game.surfaces["{surface}"] local names = {{}} '
            'for k, v in pairs(defines.entity_status) do names[v] = k end local out = {} '
            'for _, e in pairs(s.find_entities_filtered{type = {"assembling-machine", "furnace", "lab", "inserter"}}) do '
            'local k = names[e.status] or "none" out[k] = (out[k] or 0) + 1 end rcon.print(helpers.table_to_json(out))')
    return json.loads(lab.lua(code))


@fixture(source="run4-closeout", tags={"slice", "god"})
def slice_standard_reset(lab):
    """A standard-mode sandbox with power cut resets with no closers, no power interface and no global network."""
    if "sbx_mode" not in _verbs(lab):
        return Result(True, "skipped: sbx_mode not yet merged")
    lab.sbx("slice_build", name="rg", area=RED_GREEN)
    lab.advance(120)
    god_status = _power_status(lab, "sbx-rg")
    lab.sbx("sbx_mode", name="rg", mode="standard", power="cut")
    r = lab.sbx("slice_reset", name="rg")
    # the snapshot surface holds the closers the source already had, so it is the baseline for the whole play surface
    here = _surface_counts(lab, "sbx-rg", CLOSER_NAMES)
    native = _surface_counts(lab, "sbx-rg-snap", CLOSER_NAMES)
    ports = _listing(lab.sbx("slice_ports", name="rg")["ports"])
    lab.advance(120)
    status = _power_status(lab, "sbx-rg")
    data = {"entities": r["entities"], "play": here, "snapshot": native, "status_god": god_status, "status_standard": status}
    if ports or here != native:
        return Result(False, f"closers survive in standard mode: {here} against the snapshot's {native}", data=data)
    if here["electric-energy-interface"] != native["electric-energy-interface"]:
        return Result(False, "the power interface survives in standard mode", data=data)
    unpowered = status.get("no_power", 0) + status.get("low_power", 0)
    if status.get("working", 0) or not unpowered:
        return Result(False, f"the machines still run on a standard-mode sandbox: {status}", data=data)
    return Result(True, f"no closer, no power interface and {unpowered} unpowered machines after a standard-mode reset",
                  data=data)


# -- fixtures on a created world --

def _jl(lab, code):
    return json.loads(lab.lua(code))


def _flat(lab, area):
    """Level a rectangle of nauvis: grass, nothing standing on it."""
    (x0, y0), (x1, y1) = area
    lab.lua(
        f'local s = game.surfaces.nauvis s.request_to_generate_chunks({{{(x0 + x1) // 2}, {(y0 + y1) // 2}}}, 3) '
        's.force_generate_chunk_requests() local tiles = {} '
        f'for x = {x0}, {x1 - 1} do for y = {y0}, {y1 - 1} do tiles[#tiles + 1] = {{name = "grass-1", position = {{x, y}}}} end end '
        's.set_tiles(tiles) '
        f'for _, e in pairs(s.find_entities_filtered{{area = {{{{{x0}, {y0}}}, {{{x1}, {y1}}}}}}}) do '
        'if e.type ~= "character" then e.destroy() end end')


def _names_in(lab, surface, area, margin=0):
    """Entity count per name in a rectangle widened by `margin`."""
    (x0, y0), (x1, y1) = area
    box = [[x0 - margin, y0 - margin], [x1 + margin, y1 + margin]]
    return _jl(lab, f'local out = {{}} for _, e in pairs(game.surfaces["{surface}"].find_entities_filtered{{area = '
                    f'helpers.json_to_table([==[{json.dumps(box)}]==])}}) do out[e.name] = (out[e.name] or 0) + 1 end '
                    'rcon.print(helpers.table_to_json(out))')


EDGE = [[110, 100], [129, 120]]
EDGE_WORLD = '''
local s = game.surfaces.nauvis
local f = game.forces.player
local D = defines.direction
-- machine flush with the left edge, fed by an inserter outside the cut from a chest outside the cut
local a1 = s.create_entity{name = "assembling-machine-1", position = {111.5, 102.5}, force = f}
a1.set_recipe("iron-gear-wheel")
local c1 = s.create_entity{name = "wooden-chest", position = {107.5, 102.5}, force = f}
c1.insert{name = "iron-plate", count = 400}
local i1 = s.create_entity{name = "inserter", position = {109.5, 102.5}, direction = D.EAST_FEED, force = f}
s.create_entity{name = "inserter", position = {113.5, 102.5}, direction = D.EAST_FEED, force = f}
s.create_entity{name = "wooden-chest", position = {114.5, 102.5}, force = f}
-- machine flush with the right edge, fed from inside, unloaded by an inserter outside the cut into a chest outside
local a2 = s.create_entity{name = "assembling-machine-1", position = {127.5, 108.5}, force = f}
a2.set_recipe("iron-gear-wheel")
local c2 = s.create_entity{name = "wooden-chest", position = {124.5, 108.5}, force = f}
c2.insert{name = "iron-plate", count = 400}
s.create_entity{name = "inserter", position = {125.5, 108.5}, direction = D.EAST_FEED, force = f}
s.create_entity{name = "inserter", position = {129.5, 108.5}, direction = D.EAST_FEED, force = f}
s.create_entity{name = "wooden-chest", position = {130.5, 108.5}, force = f}
-- a drill outside the cut that drops into a chest inside
for x = 107, 109 do for y = 112, 114 do s.create_entity{name = "iron-ore", position = {x + 0.5, y + 0.5}, amount = 100000} end end
s.create_entity{name = "electric-mining-drill", position = {108.5, 113.5}, direction = D.east, force = f}
s.create_entity{name = "wooden-chest", position = {110.5, 113.5}, force = f}
-- poles inside the cut: none reaches the drill's inserter, so the in-place arm must power that one itself
for _, x in ipairs{112.5, 119.5, 126.5} do s.create_entity{name = "medium-electric-pole", position = {x, 105.5}, force = f} end
'''


def _edge_world(lab):
    """Build the edge world. An inserter faces away from its drop side, so the ones that drop eastward face west."""
    _flat(lab, [[100, 94], [136, 126]])
    lab.lua(EDGE_WORLD.replace("D.EAST_FEED", "D.west"))
    drop = float(lab.lua('rcon.print(game.surfaces.nauvis.find_entity("inserter", {109.5, 102.5}).drop_position.x)'))
    if drop < 109.5:
        raise RuntimeError("the outside inserter drops away from the machine")


EDGE_PROBE = ('local s = game.surfaces["{surface}"] local out = {{}} '
              'local a1 = s.find_entity("assembling-machine-1", {{111.5, 102.5}}) local a2 = s.find_entity("assembling-machine-1", {{127.5, 108.5}}) '
              'out.gears = a1 and a1.products_finished or -1 out.gears_b = a2 and a2.products_finished or -1 '
              'local ch = s.find_entity("wooden-chest", {{114.5, 102.5}}) out.gear_chest = ch and ch.get_item_count("iron-gear-wheel") or -1 '
              'local ore = s.find_entity("wooden-chest", {{110.5, 113.5}}) out.ore = ore and ore.get_item_count("iron-ore") or -1 '
              'rcon.print(helpers.table_to_json(out))')


def _edge_ports(ports):
    return {p.get("how"): p for p in ports if p.get("how") in ("ext-inserter", "ext-drill")}


@fixture(source="create", tags={"slice"})
def slice_outside_ports(lab):
    """Inserters and a drill outside the cut that load or unload it are listed and closed, and the machines at the edge work."""
    _edge_world(lab)
    r = lab.sbx("slice_build", name="ed", area=EDGE)
    ports, unhandled = _listing(r["ports"]), _listing(r["unhandled"])
    ext = [p for p in ports if p.get("how") in ("ext-inserter", "ext-drill")]
    data = {"ports": len(ports), "ext": [(p["how"], p["role"], p.get("closer") is not None) for p in ext],
            "unhandled": unhandled}
    roles = sorted((p["how"], p["role"]) for p in ext)
    if roles != [("ext-drill", "feed"), ("ext-inserter", "drain"), ("ext-inserter", "feed")]:
        return Result(False, f"outside ports not listed as expected: {roles}", data=data)
    if unhandled or any(not p.get("closer") for p in ext):
        return Result(False, f"an outside port stayed open: {unhandled}", data=data)
    lab.advance(1200)
    play = _jl(lab, EDGE_PROBE.format(surface="sbx-ed"))
    data["play"] = play
    if play["gears"] <= 0 or play["gear_chest"] <= 0 or play["gears_b"] <= 0 or play["ore"] <= 0:
        return Result(False, f"a machine at the edge did not work: {play}", data=data)
    # a reset rebuilds the outside closers too
    lab.sbx("slice_reset", name="ed")
    before = play
    lab.advance(1200)
    again = _jl(lab, EDGE_PROBE.format(surface="sbx-ed"))
    data["after_reset"] = again
    if again["gears"] <= 0 or again["gears_b"] <= 0 or again["ore"] <= 0:
        return Result(False, f"the outside closers did not survive a reset: {again}", data=data)
    lab.sbx("slice_drop", name="ed")
    lab.advance(5)
    # the in-place arm closes the same ports on the source surface
    names0 = _names_in(lab, "nauvis", EDGE, 8)
    probe0 = _jl(lab, EDGE_PROBE.format(surface="nauvis"))
    ip = lab.sbx("slice_inplace", name="ip", area=EDGE)
    ip_ext = [p for p in _listing(ip["ports"]) if p.get("how") in ("ext-inserter", "ext-drill")]
    data["inplace"] = {"ext": len(ip_ext), "unhandled": _listing(ip["unhandled"]), "stashed": ip.get("stashed")}
    if len(ip_ext) != 3 or _listing(ip["unhandled"]):
        return Result(False, f"the in-place cut did not close the outside ports: {data['inplace']}", data=data)
    lab.advance(1200)
    probe1 = _jl(lab, EDGE_PROBE.format(surface="nauvis"))
    data["inplace"]["probe"] = [probe0, probe1]
    if probe1["gears"] <= probe0["gears"] or probe1["gears_b"] <= probe0["gears_b"] or probe1["ore"] <= probe0["ore"]:
        return Result(False, f"a machine did not work on the in-place cut: {probe0} -> {probe1}", data=data)
    lab.sbx("slice_drop", name="ip")
    lab.advance(5)
    names1 = _names_in(lab, "nauvis", EDGE, 8)
    data["inplace"]["names"] = [names0, names1]
    if names0 != names1:
        return Result(False, f"the base differs after the drop: {names0} -> {names1}", data=data)
    return Result(True, f"{len(ext)} outside ports closed; gears {play['gears']}, gears_b {play['gears_b']}, "
                        f"ore {play['ore']} on the play surface and on the in-place cut", data=data)


SMALL = [[110, 100], [126, 116]]


def _small_world(lab):
    _flat(lab, [[100, 94], [136, 126]])
    lab.lua('local s = game.surfaces.nauvis local f = game.forces.player '
            's.create_entity{name = "wooden-chest", position = {114.5, 104.5}, force = f}.insert{name = "iron-plate", count = 50} '
            's.create_entity{name = "inserter", position = {116.5, 104.5}, direction = defines.direction.east, force = f} '
            's.create_entity{name = "wooden-chest", position = {117.5, 104.5}, force = f} '
            's.create_entity{name = "inserter", position = {109.5, 104.5}, direction = defines.direction.east, force = f} '
            's.create_entity{name = "wooden-chest", position = {110.5, 104.5}, force = f} '
            's.create_entity{name = "wooden-chest", position = {108.5, 104.5}, force = f}.insert{name = "coal", count = 10}')


def _slice_state(lab, name):
    stash = lab.lua(f'rcon.print(game.surfaces["fxlab-stash-{name}"] ~= nil)').strip() == "true"
    return {"slice": any(x["name"] == name for x in _listing(lab.sbx("slice_list")["slices"])),
            "box": any(x["name"] == name for x in _listing(lab.sbx("sandbox_list")["sandboxes"])), "stash": stash}


@fixture(source="create", tags={"slice"})
def slice_drop_hook(lab):
    """`sandbox_drop` on a slice leaves no slice state, restores an in-place cut and lets the name be built again."""
    _small_world(lab)
    data = {}
    lab.sbx("slice_build", name="dh", area=SMALL)
    lab.sbx("sandbox_drop", name="dh")
    data["play"] = _slice_state(lab, "dh")
    listed = [x["name"] for x in _listing(lab.sbx("slice_list")["slices"])]
    lab.advance(2)
    if data["play"]["slice"] or "dh" in listed or any(x["name"] == "dh" for x in _listing(lab.sbx("sandbox_list")["sandboxes"])):
        return Result(False, f"slice state survives sandbox_drop: {data['play']} {listed}", data=data)
    try:
        lab.sbx("slice_build", name="dh", area=SMALL)
    except SbxError as err:
        return Result(False, f"slice_build after sandbox_drop failed: {err.code} {err}", data=data)
    lab.sbx("slice_drop", name="dh")
    lab.advance(2)
    before = lab.sbx("slice_fingerprint", area=[[96, 90], [140, 130]], surface="nauvis")
    ip = lab.sbx("slice_inplace", name="dp", area=SMALL)
    data["inplace_stashed"] = ip.get("stashed")
    cut = lab.sbx("slice_fingerprint", area=[[96, 90], [140, 130]], surface="nauvis")
    if cut["digest"] == before["digest"] or not ip.get("stashed"):
        return Result(False, "the in-place cut did not change the base, so the drop proves nothing", data=data)
    lab.sbx("sandbox_drop", name="dp")
    data["inplace"] = _slice_state(lab, "dp")
    after = lab.sbx("slice_fingerprint", area=[[96, 90], [140, 130]], surface="nauvis")
    lab.advance(2)
    data["inplace_after_tick"] = _slice_state(lab, "dp")
    if after["digest"] != before["digest"]:
        return Result(False, "sandbox_drop on an in-place slice did not restore the base", data=data)
    if data["inplace"]["slice"] or data["inplace_after_tick"]["stash"]:
        return Result(False, f"state survives sandbox_drop on an in-place slice: {data['inplace_after_tick']}", data=data)
    if lab.sbx("slice_list")["slices"]:
        return Result(False, "slice_list still lists a dropped slice", data=data)
    try:
        lab.sbx("slice_inplace", name="dp", area=SMALL)
    except SbxError as err:
        return Result(False, f"slice_inplace after sandbox_drop failed: {err.code} {err}", data=data)
    lab.sbx("slice_drop", name="dp")
    return Result(True, "sandbox_drop clears a play slice and restores an in-place slice; both names build again", data=data)


@fixture(source="create", tags={"slice"})
def slice_reset_at_error(lab):
    """A scheduled reset that fails stores `last_error`, clears `reset_at` and never raises from on_tick."""
    _small_world(lab)
    lab.sbx("slice_build", name="ok", area=SMALL)
    lab.sbx("slice_build", name="bad", area=SMALL)
    now = lab.tick()
    lab.sbx("slice_reset_at", name="ok", tick=now + 30)
    lab.sbx("slice_reset_at", name="bad", tick=now + 30)
    lab.lua('game.delete_surface("sbx-bad-snap")')
    lab.advance(120)
    listed = {x["name"]: x for x in _listing(lab.sbx("slice_list")["slices"])}
    pending = {k: listed[k].get("reset_at") is None for k in ("ok", "bad")}
    data = {"listed": listed, "pending_cleared": pending}
    if not listed["bad"].get("last_error"):
        return Result(False, "a failed scheduled reset left no last_error", data=data)
    if not (pending["ok"] and pending["bad"]):
        return Result(False, "reset_at was not cleared", data=data)
    if listed["ok"].get("last_error") or not listed["ok"].get("last_reset"):
        return Result(False, "the healthy scheduled reset did not run cleanly", data=data)
    lab.advance(60)
    again = {x["name"]: x for x in _listing(lab.sbx("slice_list")["slices"])}
    if again["bad"].get("last_error") != listed["bad"]["last_error"]:
        return Result(False, "the failed reset ran again", data=data)
    return Result(True, f"last_error: {listed['bad']['last_error'][:80]}", data=data)


TRAIN_RECT = [[96, 96], [124, 114]]


@fixture(source="create", tags={"slice"})
def slice_trains(lab):
    """Snapshot trains are held manual at rest; a reset restores manual_mode and speed, and `trains_auto` frees only the automatic ones."""
    _flat(lab, [[90, 90], [130, 120]])
    lab.lua('local s = game.surfaces.nauvis local f = game.forces.player '
            'for _, y in ipairs{101, 107} do for x = 97, 117, 2 do s.create_entity{name = "straight-rail", position = {x, y}, '
            'direction = defines.direction.east, force = f} end end '
            'for _, y in ipairs{101, 107} do local l = s.create_entity{name = "locomotive", position = {105, y}, '
            'orientation = 0.25, force = f} l.insert{name = "coal", count = 5} end '
            'local trains = game.train_manager.get_trains{surface = s} '
            'for _, t in pairs(trains) do if t.carriages[1].position.y < 104 then t.manual_mode = false else '
            't.manual_mode = true t.speed = 0.05 end end')
    summary = ('local out = {} for _, t in pairs(game.train_manager.get_trains{surface = game.surfaces["%s"]}) do '
               'out[#out + 1] = {y = t.carriages[1].position.y, manual = t.manual_mode, speed = t.speed} end '
               'table.sort(out, function(a, b) return a.y < b.y end) rcon.print(helpers.table_to_json({trains = out}))')
    source = _jl(lab, summary % "nauvis")["trains"]
    data = {"source": source}
    if len(source) != 2 or source[0]["manual"] or not source[1]["manual"] or source[1]["speed"] <= 0:
        return Result(False, f"the source trains are not set up as planned: {source}", data=data)
    lab.sbx("slice_build", name="tr", area=TRAIN_RECT)
    snap = _jl(lab, summary % "sbx-tr-snap")["trains"]
    data["snapshot"] = snap
    if len(snap) != 2 or any(not t["manual"] or t["speed"] != 0 for t in snap):
        return Result(False, f"snapshot trains are not held manual at rest: {snap}", data=data)

    def trains(label):
        data[label] = _jl(lab, summary % "sbx-tr")["trains"]
        return data[label]

    def matches(got, want):
        return len(got) == 2 and all(g["manual"] == m and abs(g["speed"] - v) <= 5e-3 for g, (m, v) in zip(got, want))

    auto_and_moving = [(False, 0), (True, source[1]["speed"])]
    if not matches(trains("built"), auto_and_moving):
        return Result(False, f"built: {data['built']}", data=data)
    lab.sbx("slice_reset", name="tr", trains_auto=True)
    if not matches(trains("reset_auto"), auto_and_moving):
        return Result(False, f"reset with trains_auto: {data['reset_auto']}", data=data)
    lab.sbx("slice_reset", name="tr", trains_auto=False)
    if not matches(trains("reset_manual"), [(True, 0), (True, 0)]):
        return Result(False, f"reset without trains_auto: {data['reset_manual']}", data=data)
    return Result(True, "trains held in the snapshot and restored to their source state", data=data)


WIRE_RECT = [[110, 100], [126, 116]]


def _crossing(lab, area):
    """Red, green and copper wires with one end inside the rectangle and the other outside, on nauvis."""
    (x0, y0), (x1, y1) = area
    return _jl(lab, (
        'local s = game.surfaces.nauvis local out = {red = 0, green = 0, copper = 0} '
        'local names = {[defines.wire_connector_id.circuit_red] = "red", [defines.wire_connector_id.circuit_green] = "green", '
        '[defines.wire_connector_id.pole_copper] = "copper"} '
        f'local function inside(p) return p.x >= {x0} and p.x <= {x1} and p.y >= {y0} and p.y <= {y1} end '
        f'for _, e in pairs(s.find_entities_filtered{{area = {{{{{x0}, {y0}}}, {{{x1}, {y1}}}}}}}) do '
        'local conns = e.unit_number and e.get_wire_connectors(false) '
        'if conns then for _, c in pairs(conns) do local k = names[c.wire_connector_id] '
        'if k then for _, w in ipairs(c.connections) do if w.target.owner.valid and not inside(w.target.owner.position) '
        'then out[k] = out[k] + 1 end end end end end end rcon.print(helpers.table_to_json(out))'))


@fixture(source="create", tags={"slice"})
def slice_inplace_wires(lab):
    """The in-place cut takes the red, green and copper wires that cross the edge off, and `slice_drop` puts them back."""
    _flat(lab, [[100, 94], [136, 126]])
    lab.lua('''
local s = game.surfaces.nauvis local f = game.forces.player
local R, G, C = defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green, defines.wire_connector_id.pole_copper
local function link(a, b, id) a.get_wire_connector(id, true).connect_to(b.get_wire_connector(id, true), false, defines.wire_origin.player) end
local comb = s.create_entity{name = "constant-combinator", position = {113.5, 104.5}, force = f}
local lamp_in = s.create_entity{name = "small-lamp", position = {115.5, 104.5}, force = f}
local lamp_a = s.create_entity{name = "small-lamp", position = {107.5, 104.5}, force = f}
local lamp_b = s.create_entity{name = "small-lamp", position = {107.5, 108.5}, force = f}
local pole_in = s.create_entity{name = "small-electric-pole", position = {113.5, 110.5}, force = f}
local pole_out = s.create_entity{name = "small-electric-pole", position = {107.5, 112.5}, force = f}
link(comb, lamp_in, R)
link(comb, lamp_a, R)
link(comb, lamp_b, G)
link(pole_in, pole_out, C)''')
    area = [[96, 90], [140, 130]]
    before_fp = lab.sbx("slice_fingerprint", area=area, surface="nauvis")
    before = _crossing(lab, WIRE_RECT)
    data = {"crossing_before": before}
    if before != {"red": 1, "green": 1, "copper": 1}:
        return Result(False, f"the world does not have the crossing wires it should: {before}", data=data)
    lab.sbx("slice_inplace", name="wi", area=WIRE_RECT)
    cut = _crossing(lab, WIRE_RECT)
    data["crossing_cut"] = cut
    if any(cut.values()):
        return Result(False, f"wires still cross the edge of the in-place cut: {cut}", data=data)
    cut_fp = lab.sbx("slice_fingerprint", area=area, surface="nauvis")
    lab.sbx("slice_drop", name="wi")
    after = _crossing(lab, WIRE_RECT)
    after_fp = lab.sbx("slice_fingerprint", area=area, surface="nauvis")
    data["crossing_after"] = after
    if after != before:
        return Result(False, f"the wires did not come back: {after}", data=data)
    if after_fp["digest"] != before_fp["digest"] or cut_fp["digest"] == before_fp["digest"]:
        return Result(False, "the fingerprint does not follow the wires", data=data)
    # the fingerprint sees a wire
    lab.lua('local s = game.surfaces.nauvis local a = s.find_entity("small-lamp", {115.5, 104.5}) '
            'local b = s.find_entity("small-lamp", {107.5, 104.5}) local id = defines.wire_connector_id.circuit_green '
            'a.get_wire_connector(id, true).connect_to(b.get_wire_connector(id, true), false, defines.wire_origin.player)')
    wired = lab.sbx("slice_fingerprint", area=area, surface="nauvis")
    if wired["digest"] == before_fp["digest"]:
        return Result(False, "an extra wire does not change the fingerprint", data=data)
    return Result(True, "red, green and copper wires cut at the edge and restored by the drop", data=data)


@fixture(source="run4-closeout", tags={"slice", "god"})
def slice_standard_keep_power(lab):
    """Standard mode keeps the slice's power by default: no item closer survives, the machines stay powered."""
    if "sbx_mode" not in _verbs(lab):
        return Result(True, "skipped: sbx_mode not yet merged")
    lab.sbx("slice_build", name="rg", area=RED_GREEN)
    lab.advance(120)
    lab.sbx("sbx_mode", name="rg", mode="standard")
    lab.advance(120)
    before_reset = _power_status(lab, "sbx-rg")
    lab.sbx("slice_reset", name="rg")
    here = _surface_counts(lab, "sbx-rg", CLOSER_NAMES)
    native = _surface_counts(lab, "sbx-rg-snap", CLOSER_NAMES)
    kinds = sorted(p["kind"] for p in _listing(lab.sbx("slice_ports", name="rg")["ports"]))
    lab.advance(120)
    status = _power_status(lab, "sbx-rg")
    data = {"play": here, "snapshot": native, "ports": kinds, "status_switch": before_reset, "status_reset": status}
    unpowered = status.get("no_power", 0) + status.get("low_power", 0)
    unpowered_switch = before_reset.get("no_power", 0) + before_reset.get("low_power", 0)
    extra = {k: here[k] - native.get(k, 0) for k in here if here[k] != native.get(k, 0)}
    ok = kinds == ["power"] and extra == {"electric-energy-interface": 1} and not unpowered and not unpowered_switch
    return Result(ok, f"ports after reset {kinds}; extra closers {extra}; unpowered {unpowered_switch} after the switch, "
                      f"{unpowered} after the reset", data=data)
