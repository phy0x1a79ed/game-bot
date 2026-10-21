"""The design library: modules that a research lead built in a sandbox and the bench vouches for.

A design is a folder under `research/designs/<name>/` holding `blueprint.txt`, `design.json` and `render.png`.
`admit` writes one only when its numbers can be trusted: a bench record from a setup that passed fidelity F1,
no unhandled port, every product positive and a render. `find` looks designs up by need, `capture` turns a
rectangle of a world into the blueprint and ports that `admit` takes.
"""

import json
import os
import re
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from . import bench, camera, render
from .lab import SHARED, Lab, SbxError

DESIGNS = Path(__file__).resolve().parents[2] / "designs"
NAME = re.compile(r"[a-z0-9-]{1,48}")
OUTPUT = "/opt/factorio/script-output"
LIBRARY_PX = 1536

FACTS = """
local B = helpers.json_to_table([==[%s]==])
local inv = game.create_inventory(1)
local stack = inv[1]
if stack.import_stack(B.blueprint) == 1 then inv.destroy() error("the blueprint string did not import") end
local planned = stack.get_blueprint_entities() or {}
inv.destroy()
local lo, hi = {1e9, 1e9}, {-1e9, -1e9}
local items, recipes = {}, {}
for _, e in ipairs(planned) do
  local p = prototypes.entity[e.name]
  local w, h = p.tile_width, p.tile_height
  if e.direction == 4 or e.direction == 12 then w, h = h, w end
  lo = {math.min(lo[1], e.position.x - w / 2), math.min(lo[2], e.position.y - h / 2)}
  hi = {math.max(hi[1], e.position.x + w / 2), math.max(hi[2], e.position.y + h / 2)}
  for _, it in ipairs(p.items_to_place_this or {}) do items[it.name] = true end
  if e.recipe then recipes[e.recipe] = true end
end

local unlockers = {}
for _, t in pairs(prototypes.technology) do
  for _, fx in ipairs(t.effects or {}) do
    if fx.type == "unlock-recipe" then
      unlockers[fx.recipe] = unlockers[fx.recipe] or {}
      table.insert(unlockers[fx.recipe], t)
    end
  end
end
local function depth(t, seen)
  seen = seen or {}
  if seen[t.name] then return 0 end
  seen[t.name] = true
  local n = 1
  for _, pre in pairs(t.prerequisites) do n = n + depth(pre, seen) end
  return n
end
local function makers(item)
  if prototypes.recipe[item] then return {prototypes.recipe[item]} end
  local out = {}
  for _, r in pairs(prototypes.recipe) do
    if r.category ~= "recycling" then
      for _, pr in ipairs(r.products) do if pr.type == "item" and pr.name == item then out[#out + 1] = r break end end
    end
  end
  return out
end
local techs = {}
local function need(candidates)
  local best
  for _, r in ipairs(candidates) do
    if r.enabled then return end
    for _, t in ipairs(unlockers[r.name] or {}) do
      if not best or depth(t) < depth(best) then best = t end
    end
  end
  if best then techs[best.name] = true end
end
for item in pairs(items) do need(makers(item)) end
for name in pairs(recipes) do need({prototypes.recipe[name]}) end
local function keys(t) local out = {} for k in pairs(t) do out[#out + 1] = k end table.sort(out) return out end
rcon.print(helpers.table_to_json{entities = #planned, w = math.ceil(hi[1] - lo[1] - 1e-6), h = math.ceil(hi[2] - lo[2] - 1e-6),
                                 tech = keys(techs)})
"""

CREATE = """
local B = helpers.json_to_table([==[%s]==])
local inv = game.create_inventory(1)
inv[1].set_stack{name = "blueprint"}
inv[1].create_blueprint{surface = game.surfaces[B.surface], force = "player", area = B.area,
                        include_trains = false, include_station_names = false}
rcon.print(helpers.table_to_json{bp = inv[1].export_stack()})
inv.destroy()
"""


class Refused(ValueError):
    """The gate turned a design away; `rule` names the rule that failed."""

    def __init__(self, rule, detail):
        super().__init__(f"{rule}: {detail}")
        self.rule = rule


def _listing(x):
    return list(x) if x else []


def _lua_json(lab, template, **args):
    return json.loads(lab.lua(template % json.dumps(args)))


def facts(lab, blueprint):
    """What a blueprint string says about itself: `entities`, `w`, `h` (its true footprint) and `tech` (the unlockers)."""
    return _lua_json(lab, FACTS, blueprint=blueprint)


def _port(p):
    port = {"position": [p["position"]["x"], p["position"]["y"]], "kind": p["kind"], "role": p["role"]}
    if p["role"] == "feed" and p.get("fluid"):
        port["fluid"] = p["fluid"]
    elif p["role"] == "feed":
        port["items"] = list(p.get("items") or []) or [i for lane in _listing(p.get("lanes")) for i in _listing(lane)]
    return port


def capture(lab, area, surface="nauvis"):
    """Capture a rectangle `((x0, y0), (x1, y1))` as `{blueprint, area, ports, footprint, entities}`.

    The blueprint takes in entities that only overlap the edge, so `footprint` is measured on its entities.
    The ports come from a slice of the same rectangle, power ports left out. A slice with unhandled ports
    raises SbxError("unhandled_ports", list).
    """
    area = [list(p) for p in area]
    blueprint = _lua_json(lab, CREATE, surface=surface, area=area)["bp"]
    name = "design-capture"
    built = lab.sbx("slice_build", name=name, area=area, source=surface)
    try:
        unhandled = _listing(built["unhandled"])
        if unhandled:
            raise SbxError("unhandled_ports", unhandled)
        found = _listing(lab.sbx("slice_ports", name=name)["ports"])
    finally:
        bench._drop(lab, name)
    info = facts(lab, blueprint)
    return {"blueprint": blueprint, "area": area, "ports": [_port(p) for p in found if p["kind"] != "power"],
            "footprint": {"w": info["w"], "h": info["h"]}, "entities": info["entities"]}


def _check_name(name, root):
    if not isinstance(name, str) or not NAME.fullmatch(name):
        raise ValueError(f"design name {name!r}: 1 to 48 characters of a-z, 0-9 and -")
    if (Path(root) / name).exists():
        raise ValueError(f"design {name!r} exists")


def gate(record, products):
    """Raise Refused unless the bench record clears the rules that do not need the render."""
    f1 = (record.get("fidelity") or {}).get("f1")
    if not f1:
        raise Refused("f1", "the bench record carries no F1 verdict")
    if not f1.get("ok"):
        raise Refused("f1", f"the slicing code failed fidelity F1 (commit {f1.get('commit')})")
    if record.get("unhandled"):
        raise Refused("unhandled", f"unhandled ports: {record['unhandled']}")
    rates = record.get("rates") or {}
    dead = {p: rates.get(p, 0) for p in products if rates.get(p, 0) <= 0}
    if dead:
        raise Refused("products", f"no positive rate for {dead}")


def _seeded(save):
    seeded = save if save.endswith("+cam") else f"{save}+cam"
    if not (SHARED / "_saves" / f"{seeded}.zip").exists():
        camera.seed(seeded.removesuffix("+cam"))
    return seeded


def _fetch(lab, shot, dest):
    """Copy a render out of the lab's script-output, through the container when the root-owned file is unreadable."""
    path = Path(shot["path"])
    if not path.exists():
        raise Refused("render", f"the render left no file at {path}")
    try:
        shutil.copyfile(path, dest)
    except PermissionError:
        rel = path.relative_to(lab.output)
        with open(dest, "wb") as fh:
            subprocess.run(["docker", "exec", lab.container, "cat", f"{OUTPUT}/{rel}"], stdout=fh, check=True)
    return path


def _check_render(shot, dest):
    size = camera.png_size(dest)
    if size is None or list(size) != list(shot["resolution"]):
        raise Refused("render", f"the render is {size}, expected {shot['resolution']}")
    if shot["left"] or not shot["built"]:
        raise Refused("render", f"built {shot['built']} entities, {len(shot['left'])} left unrevived")


def admit(blueprint, ports, products, name, summary="", author="", save="run4-closeout", minutes=10, warmup=8,
          root=DESIGNS, area=None):
    """Bench a blueprint on its own camera lab and write it to the library if the gate holds.

    `area` is the rectangle `capture` reported. The ports sit on its edge, and the bench takes the bounding box of
    the entities when it is missing, which lies outside the edge whenever an entity overlaps it.
    The lab starts from `<save>+cam`, so the numbers are those of the base the design is for. A refusal raises
    Refused (a ValueError) naming the rule, and leaves nothing in `root`.
    """
    root = Path(root)
    _check_name(name, root)
    products = list(products)
    if not products:
        raise ValueError("a design needs at least one product")
    t0 = time.time()
    lab = Lab(f"design-{name}")
    stage = root / f".{name}.tmp"
    shot_path = None
    try:
        lab.up(save=_seeded(save), camera=True)
        record = bench.bench(lab, area, blueprint=blueprint, ports=ports, minutes=minutes, warmup=warmup)
        gate(record, products)
        info = facts(lab, blueprint)
        # a library render is for recognising a design, so its longest side stays near LIBRARY_PX
        zoom = round(min(1.0, LIBRARY_PX / (32 * (max(info["w"], info["h"]) + 2))), 2)
        shot = render.render_blueprint(lab, blueprint, zoom=zoom)
        root.mkdir(parents=True, exist_ok=True)
        shutil.rmtree(stage, ignore_errors=True)
        stage.mkdir()
        shot_path = _fetch(lab, shot, stage / "render.png")
        _check_render(shot, stage / "render.png")
        design = {
            "name": name, "summary": summary, "products": products, "ports": ports, "area": area,
            "footprint": {"w": info["w"], "h": info["h"]},
            "tags": {"items": products, "tech": info["tech"]},
            "bench": record,
            "render": {"file": "render.png", "area": shot["area"], "position": shot["position"],
                       "resolution": shot["resolution"], "zoom": shot["zoom"]},
            "admitted": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "author": author,
        }
        (stage / "blueprint.txt").write_text(blueprint.strip() + "\n")
        (stage / "design.json").write_text(json.dumps(design, indent=1) + "\n")
        os.rename(stage, root / name)
    except BaseException:
        shutil.rmtree(stage, ignore_errors=True)
        raise
    finally:
        if shot_path is not None:
            subprocess.run(["docker", "exec", lab.container, "rm", "-f",
                            f"{OUTPUT}/{shot_path.relative_to(lab.output)}"], capture_output=True)
        lab.down()
    return {**design, "path": str(root / name), "wall_s": round(time.time() - t0, 1)}


def _designs(root):
    root = Path(root)
    for folder in sorted(root.iterdir()) if root.is_dir() else []:
        if folder.name.startswith(".") or not (folder / "design.json").exists():
            continue
        yield folder, json.loads((folder / "design.json").read_text())


def find(item=None, min_rate=None, max_w=None, max_h=None, tech=None, root=DESIGNS):
    """Designs that make `item` at `min_rate`/min or more, fit `max_w` x `max_h` and need only techs in `tech`.

    Best rate per tile first. Without `item` there is no rate to rank by and the rows come by name.
    """
    if min_rate is not None and item is None:
        raise ValueError("min_rate needs an item")
    allowed = None if tech is None else set(tech)
    rows = []
    for folder, d in _designs(root):
        w, h = d["footprint"]["w"], d["footprint"]["h"]
        rate = d["bench"]["rates"].get(item, 0) if item else None
        if item and (rate <= 0 or (min_rate is not None and rate < min_rate)):
            continue
        if (max_w is not None and w > max_w) or (max_h is not None and h > max_h):
            continue
        if allowed is not None and not set(d["tags"]["tech"]) <= allowed:
            continue
        row = {"name": d["name"], "summary": d["summary"], "rate": rate, "footprint": d["footprint"], "path": str(folder)}
        row["rate_per_tile"] = round(rate / (w * h), 4) if item else None
        rows.append(row)
    rows.sort(key=lambda r: (-(r["rate_per_tile"] or 0), r["name"]))
    return rows


def show(name, root=DESIGNS):
    """The design.json of design `name`."""
    path = Path(root) / name / "design.json"
    if not path.exists():
        raise KeyError(f"no design {name!r}")
    return json.loads(path.read_text())


def register(sub):
    """CLI: design-capture, design-admit, design-find, design-show. Each prints JSON."""
    cp = sub.add_parser("design-capture", help="blueprint, ports and footprint of a rectangle of a lab, as JSON")
    cp.add_argument("name")
    for k in ("x0", "y0", "x1", "y1"):
        cp.add_argument(k, type=float)
    cp.add_argument("--surface", default="nauvis")
    cp.add_argument("--out", help="write blueprint.txt and ports.json here instead of printing the blueprint")
    ad = sub.add_parser("design-admit", help="bench a blueprint on its own lab and admit it to the library")
    ad.add_argument("name")
    ad.add_argument("--bp", required=True, help="file with the blueprint string")
    ad.add_argument("--ports", required=True, help="file with the ports as JSON, a list or {ports, area}")
    ad.add_argument("--products", required=True, help="comma-separated item names")
    ad.add_argument("--summary", default="")
    ad.add_argument("--author", default="")
    ad.add_argument("--save", default="run4-closeout")
    ad.add_argument("--minutes", type=int, default=10)
    ad.add_argument("--warmup", type=int, default=8)
    fd = sub.add_parser("design-find", help="designs by need, best rate per tile first")
    fd.add_argument("--item")
    fd.add_argument("--min-rate", type=float)
    fd.add_argument("--max-w", type=int)
    fd.add_argument("--max-h", type=int)
    fd.add_argument("--tech", help="comma-separated techs the designs may need")
    sh = sub.add_parser("design-show", help="the design.json of a design")
    sh.add_argument("design")

    def do_capture(a):
        got = capture(Lab(a.name), ((a.x0, a.y0), (a.x1, a.y1)), surface=a.surface)
        if a.out:
            out = Path(a.out)
            out.mkdir(parents=True, exist_ok=True)
            (out / "blueprint.txt").write_text(got["blueprint"])
            (out / "ports.json").write_text(json.dumps({"ports": got["ports"], "area": got["area"]}, indent=1))
            got = {**got, "blueprint": f"{out / 'blueprint.txt'}"}
        print(json.dumps(got, indent=1))

    def do_admit(a):
        ports = json.loads(Path(a.ports).read_text())
        area = ports.get("area") if isinstance(ports, dict) else None
        got = admit(Path(a.bp).read_text().strip(), ports["ports"] if isinstance(ports, dict) else ports,
                    a.products.split(","), a.name, summary=a.summary, author=a.author, save=a.save,
                    minutes=a.minutes, warmup=a.warmup, area=area)
        print(json.dumps(got, indent=1))

    def do_find(a):
        print(json.dumps(find(a.item, a.min_rate, a.max_w, a.max_h, a.tech.split(",") if a.tech else None), indent=1))

    def do_show(a):
        print(json.dumps(show(a.design), indent=1))

    return {"design-capture": do_capture, "design-admit": do_admit, "design-find": do_find, "design-show": do_show}
