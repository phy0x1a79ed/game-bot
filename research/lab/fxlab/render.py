"""Slice and blueprint renders: a PNG of a sandbox slice, a blueprint string or any rectangle, taken by the lab camera.

Every render goes through `camera.render`, so the lab needs a camera (`Lab.up(camera=True)`). A blueprint is
stamped by the `view_stamp` verb on the hidden `bp-view` surface and the render frames what was built.
"""

import argparse
import json
import math
from pathlib import Path

from . import camera
from .lab import Lab

PAD = 1.0
MAX_ZOOM = 4.0
STAMP_SURFACE = "bp-view"


def _listing(x):
    return list(x) if x else []


def fit_zoom(area):
    """The largest zoom, to 1/100 and at most MAX_ZOOM, whose frame stays within the camera's side limit."""
    (x0, y0), (x1, y1) = area
    span = max(abs(x1 - x0), abs(y1 - y0), 1.0)
    return min(MAX_ZOOM, math.floor(camera.MAX_SIDE / (span * camera.PX_PER_TILE) * 100) / 100)


def _area(area):
    (x0, y0), (x1, y1) = area
    return ((float(x0), float(y0)), (float(x1), float(y1)))


def render_area(lab, area, surface="nauvis", zoom=None, info=False):
    """Render a rectangle `((x0, y0), (x1, y1))` of `surface`. Returns {path, area, position, resolution, zoom, surface}."""
    area = _area(area)
    zoom = fit_zoom(area) if zoom is None else zoom
    position, resolution = camera.frame(area, zoom)
    path = camera.render(lab, area=area, zoom=zoom, surface=surface, info=info)
    return {"path": str(path), "area": [list(area[0]), list(area[1])], "position": list(position),
            "resolution": list(resolution), "zoom": zoom, "surface": surface}


def render_slice(lab, name, zoom=None, info=False):
    """Render the area of slice `name` on its sandbox surface `sbx-<name>`."""
    found = {s["name"]: s for s in _listing(lab.sbx("slice_list")["slices"])}
    if name not in found:
        raise KeyError(f"no slice {name!r}; slices: {sorted(found)}")
    return render_area(lab, found[name]["area"], surface=f"sbx-{name}", zoom=zoom, info=info)


def render_blueprint(lab, blueprint, zoom=None, info=True):
    """Stamp a blueprint string on `bp-view` and render what was built, padded by a tile.

    Adds `built`, `tiles` and `left` (the ghosts that would not revive) to the render dict.
    """
    stamp = lab.sbx("view_stamp", blueprint=blueprint, surface=STAMP_SURFACE, clear=True)
    (x0, y0), (x1, y1) = stamp["area"]
    area = ((x0 - PAD, y0 - PAD), (x1 + PAD, y1 + PAD))
    out = render_area(lab, area, surface=stamp["surface"], zoom=zoom, info=info)
    out.update(built=stamp["built"], tiles=stamp.get("tiles", 0), left=_listing(stamp["left"]))
    return out


def register(sub):
    """CLI: `render-slice <lab> <name>` and `render-bp <lab> <file>`, each printing the render dict as JSON."""
    rs = sub.add_parser("render-slice", help="render a slice of a lab through its camera and print the result as JSON")
    rs.add_argument("name")
    rs.add_argument("slice")
    rb = sub.add_parser("render-bp", help="stamp a blueprint string from a file and render it")
    rb.add_argument("name")
    rb.add_argument("file")
    for p in (rs, rb):
        p.add_argument("--zoom", type=float)
        p.add_argument("--info", action=argparse.BooleanOptionalAction, default=None,
                       help="draw entity info (default: on for blueprints, off for slices)")

    def do_slice(a):
        print(json.dumps(render_slice(Lab(a.name), a.slice, zoom=a.zoom, info=bool(a.info))))

    def do_bp(a):
        info = True if a.info is None else a.info
        print(json.dumps(render_blueprint(Lab(a.name), Path(a.file).read_text().strip(), zoom=a.zoom, info=info)))

    return {"render-slice": do_slice, "render-bp": do_bp}
