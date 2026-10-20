"""Fixtures for the module bench. Owned by scope fxlab-bench (T14)."""

from .registry import Result, fixture, near


@fixture(source="run4-closeout", tags={"bench", "slow"})
def bench_redgreen(lab):
    """Capture the run 4 red/green block from the live base and rate it: the post-mortem bench read 63 and 57."""
    from .. import bench
    bp, ports = bench.capture(lab, ((112, -42), (158, -10)))
    r = bench.rate(lab, bp, minutes=5, warmup=2, ports=ports)
    red = r["outputs"].get("automation-science-pack", 0)
    green = r["outputs"].get("logistic-science-pack", 0)
    ok = near(red, 63, 6.3) and near(green, 57, 5.7)
    return Result(ok, f"red {red:.1f}/min green {green:.1f}/min, unhandled {r['unhandled']}",
                  data={"rating": {k: r[k] for k in ("outputs", "inputs", "utilisation")}})
