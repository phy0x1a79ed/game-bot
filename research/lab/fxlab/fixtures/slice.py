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
    """A reset of the 2x2-chunk cut takes at most 100 ms, a reset of the whole base at most 1000 ms (median of 3)."""
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
        runs = [timed(lab, "slice_reset", name=name)["ms"] for _ in range(3)]
        median = statistics.median(r["total"] for r in runs)
        data[name] = {"entities": built["entities"], "build_ms": round(built["ms"]["total"]),
                      "reset_ms_median": round(median, 1), "limit": limits[name],
                      "phases": {k: round(statistics.median(r[k] for r in runs), 1) for k in runs[0] if k != "total"}}
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
    r = lab.sbx("slice_inplace", name="ip", area=RED_GREEN)
    data = {"entities": before["entities"], "stashed": r.get("stashed"), "ports": len(_listing(r["ports"])),
            "unhandled": _listing(r["unhandled"])}
    cut = lab.sbx("slice_fingerprint", area=area, surface="nauvis")
    if cut["digest"] == before["digest"]:
        return Result(False, "the in-place cut changed nothing", data=data)
    lab.sbx("slice_drop", name="ip")
    after = lab.sbx("slice_fingerprint", area=area, surface="nauvis")
    lab.advance(5)
    leftover = lab.lua('local n = 0 for name in pairs(game.surfaces) do if name:find("fxlab%-stash") then n = n + 1 end end '
                       'rcon.print(n)')
    data["entities_after"] = after["entities"]
    if after["digest"] != before["digest"]:
        return Result(False, f"the base differs after the drop: {before['entities']} -> {after['entities']} entities", data=data)
    if int(leftover) or _listing(lab.sbx("sandbox_list")["sandboxes"]):
        return Result(False, "the stash surface or the box survived the drop", data=data)
    return Result(True, f"restored {before['entities']} entities exactly", data=data)


@fixture(source="run4-closeout", tags={"slice", "god"})
def slice_standard_reset(lab):
    """A standard-mode sandbox resets with no closers and no power interface."""
    if "sbx_mode" not in _verbs(lab):
        return Result(True, "skipped: sbx_mode not yet merged")
    lab.sbx("slice_build", name="rg", area=RED_GREEN)
    lab.sbx("sbx_mode", name="rg", mode="standard")
    r = lab.sbx("slice_reset", name="rg")
    here = _counts(lab, "sbx-rg", RED_GREEN, CLOSER_NAMES)
    native = _counts(lab, "nauvis", RED_GREEN, CLOSER_NAMES)
    ports = _listing(lab.sbx("slice_ports", name="rg")["ports"])
    data = {"entities": r["entities"], "play": here, "source": native}
    if ports or here != native:
        return Result(False, f"closers survive in standard mode: {here} against the source's {native}", data=data)
    power = int(lab.lua('rcon.print(#game.surfaces["sbx-rg"].find_entities_filtered{name = "electric-energy-interface"})'))
    if power:
        return Result(False, "the power interface survives in standard mode", data=data)
    return Result(True, "no closer and no power interface after a standard-mode reset", data=data)
