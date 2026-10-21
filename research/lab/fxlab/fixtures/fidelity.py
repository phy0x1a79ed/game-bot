"""Fixtures for fidelity: how faithfully a slice reproduces the full world. Owned by scope fxlab-fid (T11).

Each fixture measures a rectangle the same way on a slice and on the source surface, with `fidelity/measure.lua`,
and shares nothing with `bench.py`, so the bench never grades itself. Rates are per game minute over the ticks
that really elapsed between two reads. A fixture reports every measured number in `data`.
"""

import json
import math
import statistics
import time
from pathlib import Path

from .. import lab as labmod
from ..lab import SbxError
from .registry import Result, fixture
from .slice import timed

FIDELITY = Path(__file__).resolve().parents[2] / "fidelity"
SAVE = "run4-closeout"
WARMUP, WINDOW = 10800, 36000
TOLERANCE = 0.02
RATE_FLOOR = 0.01
STOCK_FLOOR = 1.0
CEILING_SLACK = 1.005
SATURATED = 0.98
LAB = {"cpus": 3, "memory": "6g"}
MARGIN = 32
F5_CAP_MINUTES = 15
F4_OFFSETS = (3, 7)
DRAIN_CAP_MINUTES = 30
MADE_NOTHING = 0.01
NEST = {"x": -52, "y": 331, "r": 70}
COMBAT_AREA = [[-196, 187], [92, 475]]
COMBAT_CAP = 18000
COMBAT_SEEDS = (1, 2, 3, 4, 5)
CLEAR_RADIUS = 40


def corpus():
    return json.loads((FIDELITY / "modules.json").read_text())


def listing(x):
    return list(x) if x else []


def sized(lab):
    """Bring the lab up again with the fidelity resources unless it already runs with them."""
    out = labmod.docker("inspect", "-f", "{{.HostConfig.NanoCpus}} {{.HostConfig.Memory}}", lab.container)
    cpus, memory = (int(v) for v in out.split())
    if cpus == int(LAB["cpus"] * 1e9) and memory == 6 * 1024 ** 3:
        return lab
    lab.down()
    return lab.up(save=SAVE, **LAB)


def restart(lab):
    """Kill the lab's server and start it again on its original save, so the world is exactly as at first load."""
    lab.close()
    seen = lab.logs(200000).count("to(InGame)")
    labmod.docker("kill", lab.container)
    labmod.docker("start", lab.container)
    deadline = time.time() + 180
    while lab.logs(200000).count("to(InGame)") <= seen:
        if time.time() > deadline or not lab.running():
            raise RuntimeError(f"{lab.container} did not restart:\n{lab.logs(20)}")
        time.sleep(0.5)
    for _ in range(5):
        if lab.lua("game.tick_paused = true rcon.print(tostring(game.tick_paused))").strip() == "true":
            return
    raise RuntimeError(f"{lab.container} would not pause after the restart")


def run_until_stopped(lab, wall_limit=900):
    """Unpause at high speed until the harness pauses the game, then return the tick it stopped on."""
    lab.lua("fid.stopped = nil game.speed = 1000 game.tick_paused = false")
    deadline = time.time() + wall_limit
    while True:
        out = lab.lua("rcon.print(tostring(fid.stopped))").strip()
        if out != "nil":
            break
        if time.time() > deadline:
            raise RuntimeError(f"the harness did not stop within {wall_limit}s")
        time.sleep(0.25)
    lab.lua("game.speed = 1")
    return int(out)


def minute_after(lab, offset=0):
    """The first whole-minute tick that is more than 30 ticks ahead, plus `offset`."""
    return (lab.tick() + 30) // 3600 * 3600 + 3600 + offset


def align(lab, offset=0):
    """Run the game to the next whole minute plus `offset` ticks and stop on that exact tick."""
    if lab.lua("rcon.print(tostring(fid and fid.installed))").strip() != "true":
        lab.lua((FIDELITY / "stop.lua").read_text())
    lab.lua(f"fid.stop = {minute_after(lab, offset)}")
    return run_until_stopped(lab)


def read(lab, queries):
    """Snapshot rectangles in one RCON call. `queries` maps a key to (surface, area)."""
    args = [[key, surface, area] for key, (surface, area) in queries.items()]
    code = f'ARGS = helpers.json_to_table([==[{json.dumps(args)}]==])\n' + (FIDELITY / "measure.lua").read_text()
    return json.loads(lab.lua(code))


def rates(before, after):
    """Per-minute rates of one rectangle between two snapshots of it."""
    minutes = (after["tick"] - before["tick"]) / 3600
    out = {"minutes": minutes, "produced": {}, "consumed": {}, "net": {}, "ceiling": {}, "recipes": {}, "stock": {}}
    for name, r1 in after["recipes"].items():
        r0 = before["recipes"].get(name)
        if r0 is None:
            continue
        crafts = (r1["crafts"] - r0["crafts"]) / minutes
        pcrafts = (r1["pcrafts"] - r0["pcrafts"]) / minutes
        capacity = r1["speed"] * 60 / r1["energy"]
        out["recipes"][name] = {"machines": r1["n"], "crafts_per_min": crafts, "capacity_per_min": capacity,
                                "throughput": crafts / capacity if capacity else 0.0}
        for item, amount in r1["products"].items():
            out["produced"][item] = out["produced"].get(item, 0.0) + pcrafts * amount
            out["ceiling"][item] = out["ceiling"].get(item, 0.0) + r1["cap"] * amount / r1["energy"] * 60
        for item, amount in r1["ingredients"].items():
            out["consumed"][item] = out["consumed"].get(item, 0.0) + crafts * amount
    for item in set(out["produced"]) | set(out["consumed"]):
        out["net"][item] = out["produced"].get(item, 0.0) - out["consumed"].get(item, 0.0)
    for item in set(before["stock"]) | set(after["stock"]):
        out["stock"][item] = before["stock"].get(item, 0.0) - after["stock"].get(item, 0.0)
    return out


def relative(value, reference, floor=0.0):
    """|value - reference| over |reference|, where a reference under `floor` counts as `floor`."""
    scale = max(abs(reference), floor)
    if scale == 0:
        return 0.0 if value == reference else math.inf
    return abs(value - reference) / scale


def compare(mine, other, items, key="net", labels=("slice", "inplace")):
    """Per item: both quantities, named by `labels`, and the relative error of `mine` against `other`.

    A stock counts items and a rate counts items per minute: the floor keeps float noise around zero from reading as error.
    """
    floor = STOCK_FLOOR if key == "stock" else RATE_FLOOR
    out = {}
    for item in sorted(items):
        a, b = mine[key].get(item, 0.0), other[key].get(item, 0.0)
        out[item] = {labels[0]: round(a, 4), labels[1]: round(b, 4), "error": round(relative(a, b, floor), 5)}
    return out


def misses(table, items=None):
    """The items whose error exceeds the tolerance."""
    return [i for i, c in table.items() if (items is None or i in items) and c["error"] > TOLERANCE]


class Arms:
    """A slice and a second arm of one rectangle, made from the same tick. Dropping them restores nauvis.

    `other` is "inplace" for the in-place cut on nauvis, "later" for a second slice built one tick after the first
    (a control: the same arm, started one tick apart), or None for the slice alone.
    """

    def __init__(self, lab, area, tag="", other="inplace", offset=1):
        self.lab, self.area, self.offset, self.other = lab, area, offset, other
        self.names = {"slice": f"fs{tag}"}
        if other:
            self.names["inplace"] = f"fp{tag}"
        self.reply = {}
        self.queries = {}

    def __enter__(self):
        align(self.lab, self.offset)
        self.reply["slice"] = timed(self.lab, "slice_build", name=self.names["slice"], area=self.area)
        self.queries["slice"] = (f"sbx-{self.names['slice']}", self.area)
        if self.other == "inplace":
            self.reply["inplace"] = timed(self.lab, "slice_inplace", name=self.names["inplace"], area=self.area)
            self.queries["inplace"] = ("nauvis", self.area)
        elif self.other == "later":
            self.lab.lua(f"fid.stop = {self.lab.tick() + 1}")
            run_until_stopped(self.lab)
            self.reply["inplace"] = timed(self.lab, "slice_build", name=self.names["inplace"], area=self.area)
            self.queries["inplace"] = (f"sbx-{self.names['inplace']}", self.area)
        return self

    def __exit__(self, *exc):
        for name in reversed(list(self.names.values())):
            try:
                self.lab.sbx("slice_drop", name=name)
            except SbxError:
                pass

    def summary(self):
        return {arm: {"entities": r["entities"], "ports": len(listing(r["ports"])),
                      "unhandled": listing(r["unhandled"]), "build_ms": round(r["ms"]["total"])}
                for arm, r in self.reply.items()}

    def unhandled(self):
        return {arm: u for arm, r in self.reply.items() if (u := listing(r["unhandled"]))}


def window(lab, queries, warmup=WARMUP, ticks=WINDOW):
    """Advance a warm-up, then read the window's start and end."""
    lab.advance(warmup)
    first = read(lab, queries)
    lab.advance(ticks)
    return first, read(lab, queries)


def sample_machines(lab, queries):
    """Start counting working machines every 61 ticks inside the rectangles (fidelity/sampler.lua)."""
    if lab.lua("rcon.print(tostring(fid and fid.sample_start ~= nil))").strip() != "true":
        lab.lua((FIDELITY / "sampler.lua").read_text())
    args = [[key, surface, area] for key, (surface, area) in queries.items()]
    lab.lua(f"fid.sample_start(helpers.json_to_table([==[{json.dumps(args)}]==]))")


def sampled(lab):
    """Stop counting. Returns {key: {recipe: {n, working}}}."""
    return json.loads(lab.lua("rcon.print(helpers.table_to_json(fid.sample_stop()))"))


def round_all(x, digits=4):
    if isinstance(x, float):
        return round(x, digits) if math.isfinite(x) else str(x)
    if isinstance(x, dict):
        return {k: round_all(v, digits) for k, v in x.items()}
    if isinstance(x, list):
        return [round_all(v, digits) for v in x]
    return x


@fixture(source=SAVE, tags={"fidelity", "slow"})
def fid_f1(lab):
    """F1: every product of each corpus module runs within 2% of the in-place cut on nauvis, over 10 minutes."""
    lab = sized(lab)
    data, bad, worst = {}, [], 0.0
    for offset, module in enumerate(corpus(), start=1):
        with Arms(lab, module["area"], offset=offset) as arms:
            entry = data[module["id"]] = {"offset": offset, "arms": arms.summary()}
            if arms.unhandled():
                bad.append(f"{module['id']}: unhandled ports {arms.unhandled()}")
                continue
            r0, r1 = window(lab, arms.queries)
        mine, base = rates(r0["slice"], r1["slice"]), rates(r0["inplace"], r1["inplace"])
        items = set(mine["net"]) | set(base["net"])
        table = compare(mine, base, items)
        entry.update(minutes=mine["minutes"], products=module["products"], net=table,
                     stock_drain=compare(mine, base, set(mine["stock"]) | set(base["stock"]), key="stock"))
        for item in module["products"]:
            if table.get(item, {}).get("inplace", 0) <= 0:
                bad.append(f"{module['id']}: the in-place arm made no {item}")
        worst = max([worst] + [table[i]["error"] for i in module["products"] if i in table])
        wrong = misses(table, module["products"])
        bad += [f"{module['id']}: {i} slice {table[i]['slice']} vs in-place {table[i]['inplace']}" for i in wrong]
    data = round_all(data)
    if bad:
        return Result(False, "; ".join(bad), data=data)
    return Result(True, f"{len(data)} modules, worst product error {worst:.4f}", data=data)


def utilisation(counts, snapshot):
    """Per item, the share of machine-samples with status working over every recipe that makes it."""
    seen = {}
    for recipe, c in counts.items():
        for item in snapshot["recipes"][recipe]["products"]:
            n, w = seen.get(item, (0, 0))
            seen[item] = (n + c["n"], w + c["working"])
    return {item: w / n for item, (n, w) in seen.items() if n}


@fixture(source=SAVE, tags={"fidelity", "slow"})
def fid_f2(lab):
    """F2: no slice item rate passes 1.005 x its recipe ceiling, and a saturated module sits within 2% of it."""
    lab = sized(lab)
    data, bad = {}, []
    for module in corpus():
        with Arms(lab, module["area"], other=None) as arms:
            entry = data[module["id"]] = {"arms": arms.summary()}
            if arms.unhandled():
                bad.append(f"{module['id']}: unhandled ports {arms.unhandled()}")
                continue
            lab.advance(WARMUP)
            first = read(lab, arms.queries)
            sample_machines(lab, arms.queries)
            lab.advance(WINDOW)
            last = read(lab, arms.queries)
            counts = sampled(lab)["slice"]
        x = rates(first["slice"], last["slice"])
        busy = utilisation(counts, last["slice"])
        items = {}
        for item, rate in x["produced"].items():
            ceiling = x["ceiling"][item]
            items[item] = {"rate": rate, "ceiling": ceiling, "ratio": rate / ceiling if ceiling else math.inf,
                           "working": busy.get(item, 0.0)}
            if rate > ceiling * CEILING_SLACK:
                bad.append(f"{module['id']}: {item} {rate:.2f}/min passes the ceiling {ceiling:.2f}")
            if busy.get(item, 0.0) >= SATURATED and relative(rate, ceiling) > TOLERANCE:
                bad.append(f"{module['id']}: {item} {rate:.2f}/min is saturated ({busy[item]:.3f}) "
                           f"but {relative(rate, ceiling):.3f} off its ceiling {ceiling:.2f}")
        entry.update(minutes=x["minutes"], items=items, recipes=x["recipes"],
                     machine_samples=sum(c["n"] for c in counts.values()))
    data = round_all(data)
    if bad:
        return Result(False, "; ".join(bad), data=data)
    return Result(True, f"{len(data)} modules under their ceilings", data=data)


@fixture(source=SAVE, tags={"fidelity", "slow"})
def fid_f4(lab):
    """F4: the red/green slice, reset and started 3 and 7 ticks apart, makes the same rates within 2%."""
    lab = sized(lab)
    module = next(m for m in corpus() if m["id"] == "redgreen")
    area = module["area"]
    runs, bad = {}, []
    with Arms(lab, area, other=None) as arms:
        if arms.unhandled():
            return Result(False, f"unhandled ports {arms.unhandled()}")
        name = arms.names["slice"]
        for offset in F4_OFFSETS:
            start = (lab.tick() // 600 + 2) * 600 + offset
            lab.sbx("slice_reset_at", name=name, tick=start)
            lab.advance(start - lab.tick() + 1)
            reads = window(lab, arms.queries, warmup=WARMUP - (lab.tick() - start))
            runs[offset] = {"reset_tick": start, "rates": rates(reads[0]["slice"], reads[1]["slice"])}
    first, second = (runs[o]["rates"] for o in F4_OFFSETS)
    items = set(first["net"]) | set(second["net"])
    table = compare(first, second, items)
    for item in module["products"]:
        if table[item]["error"] > TOLERANCE or table[item]["inplace"] <= 0:
            bad.append(f"{item} {table[item]['slice']} vs {table[item]['inplace']}")
    data = round_all({"offsets": list(F4_OFFSETS), "reset_ticks": {o: r["reset_tick"] for o, r in runs.items()},
                      "net": {i: {"offset3": c["slice"], "offset7": c["inplace"], "error": c["error"]}
                              for i, c in table.items()}})
    if bad:
        return Result(False, "; ".join(bad), data=data)
    worst = max(table[i]["error"] for i in module["products"])
    return Result(True, f"products agree within {worst:.4f}", data=data)


@fixture(source=SAVE, tags={"fidelity", "slow"})
def fid_f5(lab):
    """F5 (scored): how many whole minutes a rect with a 32-tile margin tracks the same rect on untouched nauvis.

    The score is the first game minute, counted from 0, whose module rate differs by more than 2%, or 15 when none does.
    """
    lab = sized(lab)
    module = next(m for m in corpus() if m["id"] == "redgreen")
    area = module["area"]
    padded = [[area[0][0] - MARGIN, area[0][1] - MARGIN], [area[1][0] + MARGIN, area[1][1] + MARGIN]]
    with Arms(lab, padded, tag="m", other=None) as arms:
        queries = {"slice": (arms.queries["slice"][0], area), "base": ("nauvis", area)}
        build = arms.summary()["slice"]
        previous = read(lab, queries)
        per_minute, diverged = [], None
        for minute in range(F5_CAP_MINUTES):
            lab.advance(3600)
            now = read(lab, queries)
            mine, base = rates(previous["slice"], now["slice"]), rates(previous["base"], now["base"])
            row = {"minute": minute, "slice": sum(mine["net"].get(i, 0.0) for i in module["products"]),
                   "base": sum(base["net"].get(i, 0.0) for i in module["products"])}
            row["error"] = relative(row["slice"], row["base"])
            row["products"] = compare(mine, base, module["products"], labels=("slice", "base"))
            per_minute.append(row)
            if diverged is None and row["error"] > TOLERANCE:
                diverged = minute
                break
            previous = now
    score = diverged if diverged is not None else F5_CAP_MINUTES
    if per_minute[0]["base"] <= 0:
        return Result(False, "the module makes nothing on untouched nauvis in minute 0, so there is no rate to compare",
                      data=round_all({"area": padded, "per_minute": per_minute}))
    data = round_all({"area": padded, "slice": build, "diverged_minute": diverged, "per_minute": per_minute})
    ok = score >= 1
    return Result(ok, f"diverged in minute {diverged}" if diverged is not None else f"no divergence in {F5_CAP_MINUTES} min",
                  score=float(score), data=data)


def drain_run(lab, module, other):
    """Warm up in god mode, switch both arms to standard in one tick and run them until the module stops.

    The energy interfaces stay (power="keep"), so the module drains its stock instead of freezing. A minute with
    no product on both arms ends the run, at most DRAIN_CAP_MINUTES after the switch.
    """
    with Arms(lab, module["area"], other=other) as arms:
        if arms.unhandled():
            return {"unhandled": arms.unhandled()}
        lab.advance(WARMUP)
        ledger = {a: lab.sbx("ledger", name=n)["count"] for a, n in arms.names.items()}
        for name in arms.names.values():
            lab.sbx("sbx_mode", name=name, mode="standard", research="keep", power="keep")
        reads = [read(lab, arms.queries)]
        minutes = []
        for minute in range(DRAIN_CAP_MINUTES):
            lab.advance(3600)
            reads.append(read(lab, arms.queries))
            row = {arm: rates(reads[-2][arm], reads[-1][arm]) for arm in arms.names}
            minutes.append(row)
            if all(row[arm]["produced"].get(i, 0.0) < MADE_NOTHING for arm in row for i in module["products"]):
                break
    whole = {arm: rates(reads[0][arm], reads[-1][arm]) for arm in arms.names}
    return {"slice": whole["slice"], "inplace": whole["inplace"], "minutes": minutes, "ledger": ledger,
            "stock_at_switch": {arm: reads[0][arm]["stock"] for arm in arms.names}, "stopped": len(minutes) < DRAIN_CAP_MINUTES}


def drain_table(run, products):
    """What the two arms made after the switch: totals of the module products (gated), rates and drains (not)."""
    mine, base = run["slice"], run["inplace"]
    span = mine["minutes"]
    totals = {i: {"slice": mine["produced"].get(i, 0.0) * span, "inplace": base["produced"].get(i, 0.0) * span}
              for i in products}
    for c in totals.values():
        c["error"] = relative(c["slice"], c["inplace"], STOCK_FLOOR)
    per_minute = [{arm: {i: row[arm]["produced"].get(i, 0.0) for i in products} for arm in row} for row in run["minutes"]]
    return {"minutes": span, "stopped": run["stopped"], "ledger_entries": run["ledger"], "stock_at_switch": run["stock_at_switch"], "totals": totals,
            "per_minute": per_minute,
            "produced_rate": compare(mine, base, set(mine["produced"]) | set(base["produced"]), key="produced"),
            "drain": compare(mine, base, set(mine["stock"]) | set(base["stock"]), key="stock"),
            "net": compare(mine, base, set(mine["net"]) | set(base["net"]))}


@fixture(source=SAVE, tags={"fidelity", "slow"})
def fid_f9b(lab):
    """F9b: after both arms switch to standard in one tick and run dry, they made the same total of each product.

    Timing while a stock drains is chaotic, so the gate is conservation: the total a finite stock makes. Rates,
    intermediates and stock drains are in `data` ungated. A control repeats the run with a second slice, built one
    tick later, in place of the in-place cut: it is the noise reference.
    """
    lab = sized(lab)
    module = next(m for m in corpus() if m["id"] == "redgreen")
    run = drain_run(lab, module, "inplace")
    if "unhandled" in run:
        return Result(False, f"unhandled ports {run['unhandled']}")
    main = drain_table(run, module["products"])
    control_run = drain_run(lab, module, "later")
    control = drain_table(control_run, module["products"]) if "unhandled" not in control_run else control_run
    bad = [f"{i} total {c['slice']:.1f} vs {c['inplace']:.1f}" for i, c in main["totals"].items()
           if c["error"] > TOLERANCE or c["inplace"] <= 0]
    if not main["stopped"]:
        bad.append(f"the module still made product after {DRAIN_CAP_MINUTES} minutes")
    data = round_all({**main, "control": control})
    if bad:
        return Result(False, "; ".join(bad), data=data)
    worst = max(c["error"] for c in main["totals"].values())
    return Result(True, f"products ran dry in {main['minutes']:.0f} min with totals within {worst:.4f}", data=data)


def combat_trial(lab, arm, seed):
    """One creep against the nest at an absolute start tick plus `seed`, on a fresh world. Returns the harness report."""
    restart(lab)
    start = minute_after(lab, seed)
    box, surface, force = ("c", "sbx-c", "sbx-c") if arm == "slice" else ("c", "nauvis", "player")
    params = {"box": box, "surface": surface, "force": force, "nest": NEST, "clear_radius": CLEAR_RADIUS,
              "ammo": "piercing-rounds-magazine", "load": 50, "n": 8, "stage": 1200, "standoff": 14, "stages": 12,
              "from": {"x": -52, "y": 280}, "t0": start, "cap": COMBAT_CAP}
    align(lab, seed)
    lab.lua(f"FID = helpers.json_to_table([==[{json.dumps(params)}]==])\n" + (FIDELITY / "combat.lua").read_text())
    if arm == "slice":
        built = timed(lab, "slice_build", name=box, area=COMBAT_AREA)
        setup = {"entities": built["entities"], "unhandled": len(listing(built["unhandled"])),
                 "build_ms": round(built["ms"]["total"])}
    else:
        lab.sbx("sandbox_new", name=box, inplace={"surface": "nauvis", "force": "player"})
        setup = {}
    t0 = time.time()
    lab.lua("fid.arm()")
    run_until_stopped(lab)
    report = json.loads(lab.lua("rcon.print(helpers.table_to_json(fid.report()))"))
    report.update(setup=setup, start_tick=start, wall_s=round(time.time() - t0, 1))
    return report


@fixture(source=SAVE, tags={"fidelity", "slow"})
def fid_f6(lab):
    """F6: a gun-turret creep on a slice around the (-52, 331) nest clears and loses like the full world does.

    Five fresh-world trials per arm start one to five ticks apart. The slice's median clear time and median
    turret losses must both fall inside the full world's min-max range.
    """
    lab = sized(lab)
    trials = {"full": [], "slice": []}
    for arm, key in (("inplace", "full"), ("slice", "slice")):
        for seed in COMBAT_SEEDS:
            trials[key].append(combat_trial(lab, arm, seed))
    summary, bad = {}, []
    for metric in ("cleared", "lost"):
        cells = {key: [t.get(metric, COMBAT_CAP) for t in runs] for key, runs in trials.items()}
        low, high = min(cells["full"]), max(cells["full"])
        median = statistics.median(cells["slice"])
        summary[metric] = {"full": cells["full"], "slice": cells["slice"], "full_range": [low, high],
                           "slice_median": median, "inside": low <= median <= high}
        if not low <= median <= high:
            bad.append(f"slice median {metric} {median} outside the full world's {low}-{high}")
    failed = [f"{key} seed {i + 1}: {t.get('err')}" for key, runs in trials.items() for i, t in enumerate(runs) if t.get("err")]
    data = round_all({"summary": summary, "trials": trials})
    if failed or bad:
        return Result(False, "; ".join(failed + bad), data=data)
    return Result(True, "slice clear time and losses fall inside the full world's range", data=data)
