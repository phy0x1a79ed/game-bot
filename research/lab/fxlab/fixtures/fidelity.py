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
MARGIN = 32
F5_CAP_MINUTES = 15
F4_OFFSETS = (3, 7)
DRAIN_CAP_MINUTES = 30
DRAIN_IDLE_MINUTES = 3
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
    """The lab, brought up on the fidelity save unless it already runs."""
    return lab if lab.running() else lab.up(save=SAVE)


def restart(lab):
    """Load the lab's original save in place, so the world is exactly as at first load."""
    lab.reload(SAVE)


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


def step(lab, ticks):
    """Run exactly `ticks` ticks (lab.advance overshoots by up to about 15) and stop on the last."""
    lab.lua(f"fid.stop = {lab.tick() + ticks}")
    return run_until_stopped(lab)


def closers(lab, box):
    """Name and position of every live entity that a port closer of `box` placed, read from its ledger."""
    return [[e["name"], e["position"]["x"], e["position"]["y"]]
            for e in lab.sbx("ledger", name=box)["entries"] if e["kind"] == "entity" and e.get("valid")]


def read(lab, queries, boxes=None):
    """Snapshot rectangles in one RCON call. `queries` maps a key to (surface, area).

    `boxes` maps a key to the sandbox whose closers the stock leaves out.
    """
    boxes = boxes or {}
    args = [[key, surface, area, closers(lab, boxes[key]) if key in boxes else []]
            for key, (surface, area) in queries.items()]
    code = f'ARGS = helpers.json_to_table([==[{json.dumps(args)}]==])\n' + (FIDELITY / "measure.lua").read_text()
    return json.loads(lab.lua(code))


def rates(before, after):
    """Per-minute rates of one rectangle between two snapshots of it.

    Deltas are taken per machine, and only for a machine that has the same recipe at both reads. products_finished
    counts product units already, with the productivity bonus; the ceiling adds the bonus to the crafting speed.
    """
    minutes = (after["tick"] - before["tick"]) / 3600
    out = {"minutes": minutes, "produced": {}, "consumed": {}, "net": {}, "ceiling": {}, "recipes": {}, "stock": {},
           "skipped": 0}
    groups = {}
    for key, m1 in after["machines"].items():
        m0 = before["machines"].get(key)
        if m0 is None or m0["r"] != m1["r"]:
            out["skipped"] += 1
            continue
        g = groups.setdefault(m1["r"], {"n": 0, "speed": 0.0, "cap": 0.0, "crafts": 0.0, "units": 0.0})
        units = (m1["pf"] - m0["pf"]) + (m1["pg"] - m0["pg"]) * (1 + m1["pb"])
        g["n"] += 1
        g["speed"] += m1["sp"]
        g["cap"] += m1["sp"] * (1 + m1["pb"])
        g["units"] += units
        g["crafts"] += units / (1 + m1["pb"])
    for name, g in groups.items():
        info = after["recipes"][name]
        crafts, units = g["crafts"] / minutes, g["units"] / minutes
        capacity = g["speed"] * 60 / info["energy"]
        out["recipes"][name] = {"machines": g["n"], "crafts_per_min": crafts, "capacity_per_min": capacity,
                                "throughput": crafts / capacity if capacity else 0.0}
        for item, amount in info["products"].items():
            out["produced"][item] = out["produced"].get(item, 0.0) + units * amount
            out["ceiling"][item] = out["ceiling"].get(item, 0.0) + g["cap"] * amount / info["energy"] * 60
        for item, amount in info["ingredients"].items():
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
        try:
            self._build()
        except BaseException:
            self.__exit__(None, None, None)
            raise
        return self

    def read(self):
        """Snapshot both rectangles, leaving each box's closers out of the stock."""
        return read(self.lab, self.queries, boxes=self.names)

    def _build(self):
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


def window(lab, reader, warmup=WARMUP, ticks=WINDOW):
    """Advance a warm-up, then read the window's start and end with `reader()`."""
    lab.advance(warmup)
    first = reader()
    lab.advance(ticks)
    return first, reader()


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
            r0, r1 = window(lab, arms.read)
        mine, base = rates(r0["slice"], r1["slice"]), rates(r0["inplace"], r1["inplace"])
        items = set(mine["net"]) | set(base["net"])
        table = compare(mine, base, items)
        entry.update(minutes=mine["minutes"], products=module["products"], net=table,
                     skipped_machines={"slice": mine["skipped"], "inplace": base["skipped"]},
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
        for item in snapshot["recipes"].get(recipe, {"products": {}})["products"]:
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
            first = arms.read()
            sample_machines(lab, arms.queries)
            lab.advance(WINDOW)
            last = arms.read()
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
            # a failed scheduled reset raises nothing: it shows up as last_error in slice_list
            row = next((r for r in listing(lab.sbx("slice_list")["slices"]) if r["name"] == name), {})
            runs[offset] = {"reset_tick": start, "last_reset": row.get("last_reset"), "last_error": row.get("last_error")}
            if row.get("last_reset") != start or row.get("last_error"):
                return Result(False, f"the reset at tick {start} did not run: last_reset {row.get('last_reset')}, "
                                     f"last_error {row.get('last_error')}", data=round_all({"runs": runs}))
            reads = window(lab, arms.read, warmup=WARMUP - (lab.tick() - start))
            runs[offset]["rates"] = rates(reads[0]["slice"], reads[1]["slice"])
    first, second = (runs[o]["rates"] for o in F4_OFFSETS)
    items = set(first["net"]) | set(second["net"])
    table = compare(first, second, items)
    for item in module["products"]:
        if table[item]["error"] > TOLERANCE or table[item]["inplace"] <= 0:
            bad.append(f"{item} {table[item]['slice']} vs {table[item]['inplace']}")
    data = round_all({"offsets": list(F4_OFFSETS), "reset_ticks": {o: r["reset_tick"] for o, r in runs.items()},
                      "last_reset": {o: r["last_reset"] for o, r in runs.items()},
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
        boxes = {"slice": arms.names["slice"]}
        build = arms.summary()["slice"]
        previous = read(lab, queries, boxes)
        per_minute, diverged, ended = [], None, None
        for minute in range(F5_CAP_MINUTES):
            step(lab, 3600)
            now = read(lab, queries, boxes)
            mine, base = rates(previous["slice"], now["slice"]), rates(previous["base"], now["base"])
            table = compare(mine, base, module["products"], key="produced", labels=("slice", "base"))
            row = {"minute": minute, "products": table, "error": max(c["error"] for c in table.values()),
                   "slice": sum(mine["produced"].get(i, 0.0) for i in module["products"]),
                   "base": sum(base["produced"].get(i, 0.0) for i in module["products"])}
            per_minute.append(row)
            if row["base"] <= 0:
                ended = minute
                break
            if row["error"] > TOLERANCE:
                diverged = minute
                break
            previous = now
    area_data = {"area": padded, "slice": build, "per_minute": per_minute}
    if per_minute[0]["base"] <= 0:
        return Result(False, "the module makes nothing on untouched nauvis in minute 0, so there is no rate to compare",
                      data=round_all(area_data))
    score = diverged if diverged is not None else ended if ended is not None else F5_CAP_MINUTES
    data = round_all({**area_data, "diverged_minute": diverged, "base_stopped_minute": ended})
    if diverged is not None:
        detail = f"diverged in minute {diverged}: worst product error {per_minute[-1]['error']:.4f}"
    elif ended is not None:
        detail = f"agreed for {ended} min, then the module made nothing on untouched nauvis"
    else:
        detail = f"no divergence in {F5_CAP_MINUTES} min"
    return Result(score >= 1, detail, score=float(score), data=data)


def drain_run(lab, module, other):
    """Switch both arms to standard in the tick after the build and run them until the module stops.

    There is no god warm-up, so both arms start the drain from the same cloned stock.

    The energy interfaces stay (power="keep"), so the module drains its stock instead of freezing. Three minutes
    in a row with no product on either arm end the run, at most DRAIN_CAP_MINUTES after the switch.
    """
    with Arms(lab, module["area"], other=other) as arms:
        if arms.unhandled():
            return {"unhandled": arms.unhandled()}
        ledger = {a: lab.sbx("ledger", name=n)["count"] for a, n in arms.names.items()}
        for name in arms.names.values():
            lab.sbx("sbx_mode", name=name, mode="standard", research="keep", power="keep")
        reads = [arms.read()]
        minutes, idle = [], 0
        for minute in range(DRAIN_CAP_MINUTES):
            step(lab, 3600)
            reads.append(arms.read())
            row = {arm: rates(reads[-2][arm], reads[-1][arm]) for arm in arms.names}
            minutes.append(row)
            made = any(row[arm]["produced"].get(i, 0.0) >= MADE_NOTHING for arm in row for i in module["products"])
            idle = 0 if made else idle + 1
            if idle >= DRAIN_IDLE_MINUTES:
                break
    whole = {arm: rates(reads[0][arm], reads[-1][arm]) for arm in arms.names}
    return {"slice": whole["slice"], "inplace": whole["inplace"], "minutes": minutes, "ledger": ledger,
            "stock_at_switch": {arm: reads[0][arm]["stock"] for arm in arms.names}, "stopped": idle >= DRAIN_IDLE_MINUTES}


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
    """F9b: both arms switch to standard right after the build and run dry; they made the same total of each product.

    Timing while a stock drains is chaotic, so the gate is conservation: the total a finite stock makes. Rates,
    intermediates and stock drains are in `data` ungated. A control repeats the run with a second slice, built one
    tick later, in place of the in-place cut: it is the noise reference.
    """
    lab = sized(lab)
    module = next(m for m in corpus() if m["id"] == "redgreen")
    # the control goes first: the in-place arm drains the real module, and a slice cloned after it would start empty
    control_run = drain_run(lab, module, "later")
    control = drain_table(control_run, module["products"]) if "unhandled" not in control_run else control_run
    restart(lab)
    run = drain_run(lab, module, "inplace")
    if "unhandled" in run:
        return Result(False, f"unhandled ports {run['unhandled']}")
    main = drain_table(run, module["products"])
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
    cleared = {key: [t.get("cleared") is not None for t in runs] for key, runs in trials.items()}
    if not all(cleared["full"]):
        bad.append(f"full-world trials that did not clear in {COMBAT_CAP} ticks: seeds "
                   f"{[i + 1 for i, c in enumerate(cleared['full']) if not c]}")
    timed_out = [i + 1 for i, c in enumerate(cleared["slice"]) if not c]
    if timed_out:
        bad.append(f"slice trials that did not clear in {COMBAT_CAP} ticks: seeds {timed_out}")
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
