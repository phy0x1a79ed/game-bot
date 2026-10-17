"""Ratchet runner: run the fixture suite in parallel labs and keep a tool version only if nothing regressed.

Each run writes runs/<stamp>.json under the lab root. best.json holds the best accepted run. A run is
accepted when every fixture that passed in best still passes, and either a new fixture passes or some
score rose. A fixture once in best stays judged against it forever.
"""

import argparse
import json
import subprocess
import sys
import time
import traceback
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from .fixtures import FIXTURES, Result
from .lab import ROOT, Lab

RATCHET = ROOT / "ratchet"
REPO = Path(__file__).resolve().parents[3]


def commit():
    head = subprocess.run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"], capture_output=True, text=True)
    dirty = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain", "research/lab"],
                           capture_output=True, text=True).stdout.strip()
    return head.stdout.strip() + ("+dirty" if dirty else "")


def run_one(name):
    spec = FIXTURES[name]
    lab = Lab(f"rk-{name.replace('_', '-')}")
    t0 = time.time()
    try:
        lab.up(save=None if spec["source"] == "create" else spec["source"], create=spec["source"] == "create")
        res = spec["fn"](lab)
    except Exception as exc:
        res = Result(False, f"error: {exc!r}", data={"trace": traceback.format_exc()})
    finally:
        lab.down()
    return name, {"ok": res.ok, "detail": res.detail, "score": res.score, "data": res.data,
                  "wall_s": round(time.time() - t0, 1)}


def compare(run, best):
    """Return (accepted, reasons)."""
    if best is None:
        return True, ["first run"]
    regressions, gains = [], []
    for name, b in best["results"].items():
        r = run["results"].get(name)
        if r is None:
            continue
        if b["ok"] and not r["ok"]:
            regressions.append(f"{name} now fails: {r['detail']}")
        elif b["ok"] and r["ok"] and b["score"] is not None and r["score"] is not None and r["score"] < b["score"]:
            regressions.append(f"{name} score {r['score']} < best {b['score']}")
        elif r["ok"] and (not b["ok"] or (r["score"] or 0) > (b["score"] or 0)):
            gains.append(name)
    gains += [n for n, r in run["results"].items() if r["ok"] and n not in best["results"]]
    missing = [n for n, b in best["results"].items() if b["ok"] and n not in run["results"]]
    if missing:
        return False, [f"not run: {', '.join(missing)} (a partial run cannot advance best)"]
    if regressions:
        return False, regressions
    return bool(gains), (["gains: " + ", ".join(gains)] if gains else ["no gain"])


def main(argv=None):
    p = argparse.ArgumentParser(prog="fxlab.ratchet")
    p.add_argument("names", nargs="*", help="fixtures to run; default all")
    p.add_argument("--tag", action="append", default=[])
    p.add_argument("--skip-tag", action="append", default=[])
    p.add_argument("--parallel", type=int, default=4)
    p.add_argument("--no-advance", action="store_true")
    a = p.parse_args(argv)
    names = a.names or [n for n, s in FIXTURES.items()
                        if (not a.tag or s["tags"] & set(a.tag)) and not s["tags"] & set(a.skip_tag)]
    RATCHET.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    with ThreadPoolExecutor(max_workers=a.parallel) as pool:
        results = dict(pool.map(run_one, names))
    run = {"stamp": stamp, "commit": commit(), "results": results}
    (RATCHET / "runs").mkdir(exist_ok=True)
    (RATCHET / "runs" / f"{stamp}.json").write_text(json.dumps(run, indent=1))
    for name, r in sorted(results.items()):
        print(f"{'PASS' if r['ok'] else 'FAIL'} {name} ({r['wall_s']}s) {r['detail']}")
    best_path = RATCHET / "best.json"
    best = json.loads(best_path.read_text()) if best_path.exists() else None
    accepted, reasons = compare(run, best)
    if accepted and not a.no_advance:
        merged = dict(best["results"]) if best else {}
        merged.update(results)
        best_path.write_text(json.dumps({**run, "results": merged}, indent=1))
    print(("ACCEPTED" if accepted else "REJECTED") + ": " + "; ".join(reasons))
    return 0 if all(r["ok"] for r in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
