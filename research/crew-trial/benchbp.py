"""Bench a captured design (blueprint.txt + ports.json) on a lab and print the record's rates, utilisation and starved ports.

usage: benchbp.py <lab> <dir> [warmup] [minutes] [mode]
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lab"))
from fxlab import bench  # noqa: E402
from fxlab.lab import Lab  # noqa: E402

lab, d = Lab(sys.argv[1]), Path(sys.argv[2])
warmup = int(sys.argv[3]) if len(sys.argv) > 3 else 8
minutes = int(sys.argv[4]) if len(sys.argv) > 4 else 10
mode = sys.argv[5] if len(sys.argv) > 5 else "god"
p = json.loads((d / "ports.json").read_text())
rec = bench.bench(lab, p["area"], blueprint=(d / "blueprint.txt").read_text().strip(), ports=p["ports"],
                  warmup=warmup, minutes=minutes, mode=mode, name="rb")
(d / f"bench-{mode}.json").write_text(json.dumps(rec, indent=1))
print(json.dumps({k: rec[k] for k in ("rates", "utilisation", "starved")}, indent=1))
