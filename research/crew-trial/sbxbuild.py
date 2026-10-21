"""Build a `check`-format build list in a fresh god-mode sandbox of a lab: check, place as ghosts, revive.

usage: sbxbuild.py <lab> <sandbox> <list.json>   (prints the check summary and the revive count)
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lab"))
from fxlab import tools  # noqa: E402
from fxlab.lab import Lab, SbxError  # noqa: E402

lab, name, path = Lab(sys.argv[1]), sys.argv[2], sys.argv[3]
build = json.loads(Path(path).read_text())
try:
    lab.sbx("sandbox_drop", name=name)
    lab.advance(2)
except SbxError:
    pass
lab.sbx("sandbox_new", name=name, research="copy")
where = dict(surface=f"sbx-{name}", force=f"sbx-{name}")
lab.lua(f'local s = game.surfaces["sbx-{name}"] s.request_to_generate_chunks({{0, 0}}, 3) s.force_generate_chunk_requests()')
r = tools.call(lab, "place", list=build, accept=["POLE_ISLAND"], **where)
bad = [e for e in (r.get("entries") or []) if not e.get("ok")]
print(json.dumps({"ok": r.get("ok"), "summary": r.get("summary"), "bad": bad[:10]}, indent=1))
if r.get("ok"):
    print(lab.lua(f'''local n = 0
for _, g in pairs(game.surfaces["sbx-{name}"].find_entities_filtered{{type = "entity-ghost"}}) do
  if g.revive() then n = n + 1 end end
rcon.print(n)'''))
