"""Fixtures for the module bench. Owned by scope fxlab-bench (T14)."""

import json
import time

from ..lab import SbxError
from .registry import Result, fixture
from .slice import RED_GREEN

RECORD_KEYS = {"subject", "mode", "warmup_min", "minutes", "ticks", "rates", "utilisation", "ceiling", "starved",
               "unhandled", "fidelity", "commit", "stamp"}


def _record_problems(r):
    problems = [f"missing key {k}" for k in sorted(RECORD_KEYS - set(r))]
    if r.get("unhandled"):
        problems.append("unhandled is not empty")
    if set(r.get("fidelity", {})) != {"corpus", "f1"}:
        problems.append("fidelity needs corpus and f1")
    return problems


@fixture(source="run4-closeout", tags={"bench", "slow"})
def bench_redgreen(lab):
    """The red/green block benches with red and green positive and every rate within its ceiling."""
    from .. import bench
    t0 = time.time()
    r = bench.bench(lab, RED_GREEN, minutes=10, warmup=3)
    wall = round(time.time() - t0, 1)
    red = r["rates"].get("automation-science-pack", 0)
    green = r["rates"].get("logistic-science-pack", 0)
    data = {"rates": r["rates"], "utilisation": r["utilisation"], "ceiling": r["ceiling"], "starved": r["starved"],
            "ticks": r["ticks"], "commit": r["commit"], "wall_s": wall}
    problems = _record_problems(r)
    if red <= 0 or green <= 0:
        problems.append(f"red {red} and green {green} must both be positive")
    over = {n: (v, r["ceiling"].get(n)) for n, v in r["rates"].items()
            if v > 0 and v > 1.005 * r["ceiling"].get(n, 0)}
    if over:
        problems.append(f"rates above the ceiling: {over}")
    if r["mode"] != "god":
        problems.append(f"mode {r['mode']}")
    return Result(not problems, "; ".join(problems) or f"red {red:.1f}/min green {green:.1f}/min over {r['ticks']} ticks",
                  data=data)


HEAT_CUT = [[792, 792], [801, 809]]


@fixture(source="run4-closeout", tags={"bench"})
def bench_refuses_unhandled(lab):
    """A rectangle that cuts a heat pipe leaves a port unhandled: the bench raises unhandled_ports and leaves no sandbox."""
    from .. import bench
    lab.lua('local s = game.surfaces.nauvis s.request_to_generate_chunks({800, 800}, 2) s.force_generate_chunk_requests() '
            'for _, x in ipairs{800.5, 801.5} do s.create_entity{name = "heat-pipe", position = {x, 800.5}, force = "player"} end')
    try:
        bench.bench(lab, HEAT_CUT, minutes=1, warmup=0)
    except SbxError as exc:
        sandboxes = lab.sbx("sandbox_list")["sandboxes"]
        data = {"code": exc.code, "unhandled": exc.detail, "sandboxes": sandboxes}
        if exc.code != "unhandled_ports":
            return Result(False, f"raised {exc.code}, not unhandled_ports: {exc.detail}", data=data)
        if sandboxes:
            return Result(False, f"refused but left sandboxes {sandboxes}", data=data)
        return Result(True, f"refused with {len(exc.detail)} unhandled port ({exc.detail[0]['reason']}), no sandbox left",
                      data=data)
    return Result(False, "the bench rated a slice with an unhandled port")


@fixture(source="run4-closeout", tags={"bench", "slow"})
def bench_standard(lab):
    """Standard mode makes no more than god mode on the red/green block, and its supply is cut by the end."""
    from .. import bench
    t0 = time.time()
    god = bench.bench(lab, RED_GREEN, minutes=3, warmup=1, mode="god")
    t1 = time.time()
    std = bench.bench(lab, RED_GREEN, minutes=3, warmup=1, mode="standard")
    t2 = time.time()
    over = {n: (v, god["rates"].get(n, 0)) for n, v in std["rates"].items() if v > god["rates"].get(n, 0) + 0.01}
    data = {"god": god["rates"], "standard": std["rates"], "starved": std["starved"], "god_starved": god["starved"],
            "mode": std["mode"],
            "wall_s": {"god": round(t1 - t0, 1), "standard": round(t2 - t1, 1)}}
    problems = [f"standard above god: {over}"] if over else []
    if std["mode"] != "standard":
        problems.append(f"mode {std['mode']}")
    if not std["starved"]:
        problems.append("standard mode starved nothing")
    return Result(not problems, "; ".join(problems) or
                  f"standard {json.dumps(std['rates'])} vs god {json.dumps(god['rates'])}, starved {len(std['starved'])}",
                  data=data)


def _derived_ports(lab, area):
    """The belt and pipe ports of a slice of `area`, as the blueprint bench takes them."""
    lab.sbx("slice_build", name="derive", area=area)
    try:
        found = lab.sbx("slice_ports", name="derive")["ports"]
    finally:
        lab.sbx("slice_drop", name="derive")
    out = []
    for p in found or []:
        if p["kind"] == "power":
            continue
        port = {"position": [p["position"]["x"], p["position"]["y"]], "kind": p["kind"], "role": p["role"]}
        if p["role"] == "feed" and p.get("fluid"):
            port["fluid"] = p["fluid"]
        elif p["role"] == "feed":
            port["items"] = list(p.get("items") or []) or [i for lane in p.get("lanes") or [] for i in lane or []]
        out.append(port)
    return out


@fixture(source="run4-closeout", tags={"bench", "slow"})
def bench_blueprint(lab):
    """The red/green block captured as a blueprint, stamped on an empty surface, rates within 5% of the block on the slice.

    A stamped design starts with empty belts and buffers, so it warms up for 8 minutes where the slice needs 2.
    """
    from .. import bench
    ports = _derived_ports(lab, RED_GREEN)
    (x0, y0), (x1, y1) = RED_GREEN
    bp = lab.lua(f'local inv = game.create_inventory(1) inv[1].set_stack{{name = "blueprint"}} '
                 f'inv[1].create_blueprint{{surface = game.surfaces.nauvis, force = "player", '
                 f'area = {{{{{x0}, {y0}}}, {{{x1}, {y1}}}}}, include_trains = false, include_station_names = false}} '
                 'rcon.print(inv[1].export_stack()) inv.destroy()').strip()
    t0 = time.time()
    area = bench.bench(lab, RED_GREEN, minutes=5, warmup=2)
    t1 = time.time()
    stamped = bench.bench(lab, RED_GREEN, blueprint=bp, ports=ports, minutes=5, warmup=8)
    t2 = time.time()
    red, green = ("automation-science-pack", "logistic-science-pack")
    data = {"ports": ports, "area": area["rates"], "blueprint": stamped["rates"], "starved": stamped["starved"],
            "wall_s": {"area": round(t1 - t0, 1), "blueprint": round(t2 - t1, 1)}}
    problems = _record_problems(stamped)
    for item in (red, green):
        a, b = area["rates"].get(item, 0), stamped["rates"].get(item, 0)
        if a <= 0 or abs(a - b) > 0.05 * a:
            problems.append(f"{item}: blueprint {b} against area {a}")
    return Result(not problems, "; ".join(problems) or
                  f"blueprint red {stamped['rates'][red]}/min green {stamped['rates'][green]}/min, "
                  f"area {area['rates'][red]}/{area['rates'][green]}", data=data)
