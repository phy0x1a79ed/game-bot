"""Design bench: capture a design as a blueprint, rate it on an empty surface with free inputs and voided outputs.

The rating is what the design makes per minute when nothing upstream or downstream binds it, plus how busy
each recipe's machines were. Compare it with what the same design delivers in the base: the gap is supply.
"""

import json
from collections import defaultdict
from pathlib import Path

LUA = Path(__file__).resolve().parent / "lua"
TICKS_PER_MIN = 3600

STATS = """
local st = game.forces.player.get_item_production_statistics(game.surfaces.bench)
local inv = {} for k, v in pairs(defines.entity_status) do inv[v] = k end
local machines = {}
for _, e in pairs(game.surfaces.bench.find_entities_filtered{type = {"assembling-machine", "furnace", "lab", "mining-drill"}}) do
  local r = (e.type == "assembling-machine" or e.type == "furnace") and e.get_recipe()
  machines[#machines + 1] = {recipe = r and r.name or e.name, status = inv[e.status] or "?"}
end
rcon.print(helpers.table_to_json{tick = game.tick, made = st.input_counts, used = st.output_counts, machines = machines})
"""


def lua_string(text):
    return "[==[" + text + "]==]"


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ", ".join(lua_value(x) for x in v) + "}"
    return "{" + ", ".join(f"[{json.dumps(k)}] = {lua_value(x)}" for k, x in v.items()) + "}"


def capture(lab, area, surface="nauvis"):
    """Blueprint string of every player entity in area ((x0, y0), (x1, y1)), plus the ports a live base shows."""
    (x0, y0), (x1, y1) = area
    cap = f"CAP = {{surface = \"{surface}\", x0 = {x0}, y0 = {y0}, x1 = {x1}, y1 = {y1}}}\n"
    ports = json.loads(lab.lua_file(LUA / "capture-ports.lua", prelude=cap))["ports"]
    return capture_bp(lab, area, surface), ports


def capture_bp(lab, area, surface="nauvis"):
    (x0, y0), (x1, y1) = area
    out = lab.lua(f"""
local inv = game.create_inventory(1)
inv[1].set_stack{{name = "blueprint"}}
inv[1].create_blueprint{{surface = game.surfaces["{surface}"], force = "player", area = {{{{{x0}, {y0}}}, {{{x1}, {y1}}}}},
  include_trains = false, include_station_names = false}}
rcon.print(inv[1].export_stack())
inv.destroy()""")
    return out.strip()


def build(lab, bp, fuel="coal", swap=(), ports=None):
    swaps = ", ".join(f'["{k}"] = true' for k in swap)
    declared = f", ports = {lua_value(ports)}" if ports else ""
    prelude = f"BENCH = {{bp = {lua_string(bp)}, fuel = \"{fuel}\", swap = {{{swaps}}}{declared}}}\n"
    return json.loads(lab.lua_file(LUA / "bench-build.lua", prelude=prelude))


def _stats(lab):
    return json.loads(lab.lua(STATS))


def port_key(p):
    return f"{p['x']:.1f},{p['y']:.1f}"


def lane_choice(lab, bp, fuel="coal", trial_min=2):
    """Which lane gets which item matters when a design splits lanes. Try each two-item port both ways."""
    report = build(lab, bp, fuel)
    two = [port_key(p) for p in report["ports"] if p["kind"] == "belt-in" and len(p.get("items", [])) >= 2]
    best, best_out = (), -1.0
    for mask in range(2 ** min(len(two), 3)):
        swap = tuple(k for i, k in enumerate(two) if mask >> i & 1)
        build(lab, bp, fuel, swap)
        first = _stats(lab)
        lab.advance(trial_min * TICKS_PER_MIN)
        last = _stats(lab)
        out = sum(max(0, last["made"].get(n, 0) - first["made"].get(n, 0)
                      - (last["used"].get(n, 0) - first["used"].get(n, 0))) for n in last["made"])
        if out > best_out:
            best, best_out = swap, out
    return best


def rate(lab, bp, minutes=10, warmup=3, samples_per_min=6, fuel="coal", ports=None, swap=None):
    """Build bp on the bench, run warmup minutes, then measure for `minutes`. Returns a rating dict.

    Pass the ports `capture` returned. Without them the bench guesses ports and tries lane orders."""
    if swap is None:
        swap = () if ports else lane_choice(lab, bp, fuel)
    report = build(lab, bp, fuel, swap, ports)
    lab.advance(warmup * TICKS_PER_MIN)
    first = _stats(lab)
    busy = defaultdict(lambda: [0, 0])
    step = TICKS_PER_MIN // samples_per_min
    for _ in range(minutes * samples_per_min):
        lab.advance(step)
        for m in _stats(lab)["machines"]:
            busy[m["recipe"]][1] += 1
            if m["status"] == "working":
                busy[m["recipe"]][0] += 1
    last = _stats(lab)
    span = (last["tick"] - first["tick"]) / TICKS_PER_MIN

    def per_min(key):
        names = set(first[key]) | set(last[key])
        return {n: (last[key].get(n, 0) - first[key].get(n, 0)) / span for n in names}

    made, used = per_min("made"), per_min("used")
    net = {n: round(made.get(n, 0) - used.get(n, 0), 2) for n in set(made) | set(used)}
    statuses = defaultdict(lambda: defaultdict(int))
    for m in last["machines"]:
        statuses[m["recipe"]][m["status"]] += 1
    return {
        "minutes": round(span, 2),
        "outputs": {n: v for n, v in sorted(net.items()) if v > 0.05},
        "inputs": {n: -v for n, v in sorted(net.items()) if v < -0.05},
        "utilisation": {r: round(w / t, 2) for r, (w, t) in sorted(busy.items())},
        "status_at_end": {r: dict(v) for r, v in statuses.items()},
        "ports": report["ports"],
        "unhandled": report["unhandled"],
        "entities": report["entities"],
        "swap": list(swap),
    }
