"""Fixtures for the assault bench. Owned by scope fxlab-assault (T15).

All four assault the run-4 nest at (-52, 331): 7 spawners, 10 worms and 54 units at evolution 0.653.
"""

from ..assault import assault_compare, assault_report, assault_run
from .registry import Result, fixture

NEST = (-52, 331)
SEEDS = 3
WORLD_SEEDS = 5
STEP = 5  # the driver reads the clear condition every 5 ticks, so a median can sit one step outside a range
TAGS = {"assault", "slow"}


@fixture(source="run4-closeout", tags=TAGS)
def assault_creep(lab):
    trials = assault_run(lab, "creep", seeds=SEEDS, nest_at=NEST, where="world")
    rep = assault_report(trials)
    ok = rep["clear_rate"] == 1.0
    ct = rep["clear_tick"]
    turrets = rep["losses"].get("gun-turret")
    return Result(ok, f"cleared {sum(t['cleared'] for t in trials)}/{SEEDS}; clear tick "
                  f"{ct and (ct['min'], ct['median'], ct['max'])}; gun-turrets lost "
                  f"{turrets and (turrets['min'], turrets['median'], turrets['max'])}",
                  data={"report": rep, "trials": trials})


@fixture(source="run4-closeout", tags=TAGS)
def assault_soldier(lab):
    trials = assault_run(lab, "soldier", seeds=SEEDS, nest_at=NEST, where="world")
    rep = assault_report(trials)
    deaths = rep["losses"].get("character", {"median": 0, "min": 0, "max": 0})
    ct = rep["clear_tick"]
    ok = rep["clear_rate"] == 1.0 and deaths["median"] == 0
    return Result(ok, f"cleared {sum(t['cleared'] for t in trials)}/{SEEDS}; clear tick "
                  f"{ct and (ct['min'], ct['median'], ct['max'])}; body deaths median {deaths['median']} "
                  f"(max {deaths['max']})", data={"report": rep, "trials": trials})


@fixture(source="run4-closeout", tags=TAGS)
def assault_compare_idle(lab):
    creep = assault_run(lab, "creep", seeds=SEEDS, nest_at=NEST, where="world")
    idle = assault_run(lab, "idle", seeds=SEEDS, nest_at=NEST, where="world", max_ticks=6000)
    cmp = assault_compare(creep, idle)
    never = not any(t["cleared"] for t in idle)
    ok = cmp["better"] == "a" and cmp["real"] and never and all(t["cleared"] for t in creep)
    return Result(ok, f"{cmp['verdict']}: creep {cmp['clear_tick']['a']} vs idle {cmp['clear_tick']['b']}; "
                  f"idle cleared {sum(t['cleared'] for t in idle)}/{SEEDS}",
                  data={"compare": cmp, "creep": assault_report(creep), "idle": assault_report(idle)})


@fixture(source="run4-closeout", tags=TAGS)
def assault_slice_matches(lab):
    world = assault_report(assault_run(lab, "creep", seeds=WORLD_SEEDS, nest_at=NEST, where="world"))
    sliced_trials = assault_run(lab, "creep", seeds=SEEDS, nest_at=NEST, where="slice")
    sliced = assault_report(sliced_trials)
    w, s = world["clear_tick"], sliced["clear_tick"]
    strict = bool(w and s and w["min"] <= s["median"] <= w["max"])
    inside = bool(w and s and w["min"] - STEP <= s["median"] <= w["max"] + STEP)
    return Result(inside, f"slice median {s and s['median']} (range {s and (s['min'], s['max'])}) "
                  f"vs world range {w and (w['min'], w['max'])}; strictly inside: {strict}",
                  data={"strict": strict, "world": world, "slice": sliced, "slice_trials": sliced_trials})
