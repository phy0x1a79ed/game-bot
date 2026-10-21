"""Re-capture a sandbox rectangle's blueprint without the port stubs outside it, keeping the ports of the first capture.

usage: recapture.py <lab> <sandbox> <dir> item-fix-json   (item-fix: {"x,y": ["item", ...]} to correct feed items)
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lab"))
from fxlab import designs  # noqa: E402
from fxlab.lab import Lab  # noqa: E402

lab, name, d = Lab(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
fix = json.loads(sys.argv[4]) if len(sys.argv) > 4 else {}
p = json.loads((d / "ports.json").read_text())
(x0, y0), (x1, y1) = p["area"]
lab.lua(f'''for _, e in pairs(game.surfaces["sbx-{name}"].find_entities_filtered{{force = "sbx-{name}"}}) do
  local x, y = e.position.x, e.position.y
  if x < {x0} or x > {x1} or y < {y0} or y > {y1} then e.destroy() end end''')
bp = designs._lua_json(lab, designs.CREATE, surface=f"sbx-{name}", area=p["area"])["bp"]
(d / "blueprint.txt").write_text(bp + "\n")
for q in p["ports"]:
    k = f"{q['position'][0]},{q['position'][1]}"
    if k in fix:
        q["items"] = fix[k]
(d / "ports.json").write_text(json.dumps(p, indent=1))
print(designs.facts(lab, bp)["w"], designs.facts(lab, bp)["h"], json.dumps(p["ports"]))
