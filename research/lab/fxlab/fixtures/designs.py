"""Fixtures for the design library. Owned by scope fxlab-designs (T19). Every fixture writes to a temporary root."""

import copy
import json
import tempfile
import time
from pathlib import Path

from .. import bench, camera, designs, render
from ..lab import SbxError
from .registry import Result, fixture
from .slice import RED_GREEN

PRODUCTS = ["automation-science-pack", "logistic-science-pack"]
HEAT_CUT = [[792, 792], [801, 809]]
GOOD_RECORD = {
    "subject": {"blueprint": "stub"}, "mode": "god", "power": "keep", "warmup_min": 8, "minutes": 10, "ticks": 36000,
    "rates": {"automation-science-pack": 20.0, "logistic-science-pack": 12.0, "iron-plate": -80.0},
    "utilisation": {}, "ceiling": {}, "starved": [], "unhandled": [],
    "fidelity": {"corpus": None, "f1": {"ok": True, "commit": "stub", "stamp": "stub"}},
    "commit": "stub", "stamp": "stub",
}
GOOD_SHOT = {"path": None, "area": [[0, 0], [4, 4]], "position": [2, 2], "resolution": [128, 128], "zoom": 1,
             "surface": "bp-view", "built": 3, "tiles": 0, "left": []}


def _png(path, w, h):
    """The smallest valid PNG header and IEND at size w x h, enough for camera.png_size."""
    import struct
    import zlib
    chunk = lambda kind, body: struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IEND", b""))


class _StubLab:
    output = Path(tempfile.gettempdir())
    container = "stub"

    def __init__(self, name):
        self.name = name

    def up(self, **kw):
        return self

    def down(self):
        pass


class _Stubbed:
    """Replace the lab, the bench, the render and the blueprint reader of `designs` for one with-block."""

    def __init__(self, record, shot=None, png=(128, 128)):
        self.record, self.shot, self.png = record, shot, png

    def __enter__(self):
        self.saved = (designs.Lab, designs.bench.bench, designs.render.render_blueprint, designs.facts, designs._seeded)
        self.tmp = tempfile.TemporaryDirectory()

        def shoot(lab, blueprint):
            shot = copy.deepcopy(self.shot or GOOD_SHOT)
            shot["path"] = str(Path(self.tmp.name) / "shot.png")
            if self.png:
                _png(shot["path"], *self.png)
            return shot

        designs.Lab = _StubLab
        designs.bench.bench = lambda lab, area=None, **kw: copy.deepcopy(self.record)
        designs.render.render_blueprint = shoot
        designs.facts = lambda lab, bp: {"entities": 3, "w": 4, "h": 4, "tech": ["automation"]}
        designs._seeded = lambda save: save
        return self

    def __exit__(self, *exc):
        designs.Lab, designs.bench.bench, designs.render.render_blueprint, designs.facts, designs._seeded = self.saved
        self.tmp.cleanup()


def _leftovers(root):
    return sorted(p.name for p in Path(root).iterdir())


@fixture(source="run4-closeout", tags={"designs", "slow"})
def designs_admit_redgreen(lab):
    """The red/green rect captured and admitted: three files, red and green positive, F1 ok, a real render."""
    with tempfile.TemporaryDirectory() as root:
        t0 = time.time()
        got = designs.capture(lab, RED_GREEN)
        capture_s = round(time.time() - t0, 1)
        lab.down()
        t1 = time.time()
        design = designs.admit(got["blueprint"], got["ports"], PRODUCTS, "red-green", summary="red and green science",
                               author="fxlab fixture", root=root, area=got["area"])
        admit_s = round(time.time() - t1, 1)
        folder = Path(root) / "red-green"
        files = _leftovers(folder)
        shown = designs.show("red-green", root=root)
        png = camera.png_size(folder / "render.png")
        rates = shown["bench"]["rates"]
        want = tuple(shown["render"]["resolution"])
        found = designs.find("logistic-science-pack", root=root)
        problems = []
        if files != ["blueprint.txt", "design.json", "render.png"]:
            problems.append(f"files {files}")
        if any(rates.get(p, 0) <= 0 for p in PRODUCTS):
            problems.append(f"rates {rates}")
        if not (shown["bench"]["fidelity"]["f1"] or {}).get("ok"):
            problems.append(f"f1 {shown['bench']['fidelity']['f1']}")
        if png != want:
            problems.append(f"render.png is {png}, the record says {want}")
        if (folder / "render.png").stat().st_size < 50_000:
            problems.append("render.png is small")
        if [r["name"] for r in found] != ["red-green"]:
            problems.append(f"find returned {found}")
        if (folder / "blueprint.txt").read_text().strip() != got["blueprint"].strip():
            problems.append("blueprint.txt differs from the capture")
    data = {"capture": {k: v for k, v in got.items() if k != "blueprint"}, "rates": rates, "ceiling": shown["bench"]["ceiling"],
            "utilisation": shown["bench"]["utilisation"], "footprint": shown["footprint"], "tags": shown["tags"],
            "render": shown["render"], "png": png, "capture_s": capture_s, "admit_s": admit_s,
            "starved": shown["bench"]["starved"], "design_wall_s": design["wall_s"]}
    return Result(not problems, "; ".join(problems) or
                  f"red {rates[PRODUCTS[0]]}/min green {rates[PRODUCTS[1]]}/min, footprint {shown['footprint']}, "
                  f"png {png}, admit {admit_s}s, capture {capture_s}s", data=data)


def _refusal(run, rule=None):
    """The exception `run` raises, or None; a ValueError that names `rule` when given."""
    try:
        run()
    except designs.Refused as exc:
        return exc.rule if rule is None or exc.rule == rule else f"wrong rule {exc.rule}"
    except ValueError:
        return "ValueError"
    return None


@fixture(source="create", tags={"designs"})
def designs_gate(lab):
    """The gate refuses a missing or failed F1, an unhandled port, a dead product, a bad render, a bad name and a taken name.

    Each refusal names its rule and leaves nothing in the library. A rect that cuts a heat pipe makes capture raise
    unhandled_ports.
    """
    results, bad = {}, []
    with tempfile.TemporaryDirectory() as root:
        def attempt(label, record, rule, name="gate-test", shot=None, png=(128, 128), products=PRODUCTS):
            with _Stubbed(record, shot, png):
                got = _refusal(lambda: designs.admit("bp", [], products, name, root=root), rule)
            results[label] = got
            if got != (rule or "ValueError"):
                bad.append(f"{label}: {got}")

        no_f1 = copy.deepcopy(GOOD_RECORD)
        no_f1["fidelity"]["f1"] = None
        failed_f1 = copy.deepcopy(GOOD_RECORD)
        failed_f1["fidelity"]["f1"]["ok"] = False
        unhandled = copy.deepcopy(GOOD_RECORD)
        unhandled["unhandled"] = [{"position": {"x": 1, "y": 2}, "name": "rail", "reason": "stub"}]
        dead = copy.deepcopy(GOOD_RECORD)
        dead["rates"]["logistic-science-pack"] = 0
        absent = copy.deepcopy(GOOD_RECORD)
        del absent["rates"]["logistic-science-pack"]
        attempt("f1 missing", no_f1, "f1")
        attempt("f1 not ok", failed_f1, "f1")
        attempt("unhandled port", unhandled, "unhandled")
        attempt("product at 0", dead, "products")
        attempt("product absent", absent, "products")
        attempt("render wrong size", GOOD_RECORD, "render", png=(64, 64))
        attempt("render with ghosts left", GOOD_RECORD, "render", shot={**GOOD_SHOT, "left": [{"name": "x"}]})
        attempt("render missing", GOOD_RECORD, "render", png=None)
        for label, name in (("name upper case", "Bad"), ("name with space", "a b"), ("name empty", ""),
                            ("name too long", "a" * 49), ("name path", "../x")):
            attempt(label, GOOD_RECORD, None, name=name)
        attempt("no products", GOOD_RECORD, None, products=[])
        with _Stubbed(GOOD_RECORD):
            designs.admit("bp", [], PRODUCTS, "taken", root=root)
        before = _leftovers(root)
        attempt("name exists", GOOD_RECORD, None, name="taken")
        after = _leftovers(root)
        if before != ["taken"] or after != before:
            bad.append(f"library holds {before} then {after}, expected only the one admitted design")
        shown = designs.show("taken", root=root)
        if shown["tags"] != {"items": PRODUCTS, "tech": ["automation"]} or shown["footprint"] != {"w": 4, "h": 4}:
            bad.append(f"admitted stub design reads {shown['tags']} {shown['footprint']}")

    lab.lua('local s = game.surfaces.nauvis s.request_to_generate_chunks({800, 800}, 2) s.force_generate_chunk_requests() '
            'for _, x in ipairs{800.5, 801.5} do s.create_entity{name = "heat-pipe", position = {x, 800.5}, force = "player"} end')
    try:
        designs.capture(lab, HEAT_CUT)
    except SbxError as exc:
        results["capture unhandled"] = exc.code
        left = lab.sbx("sandbox_list")["sandboxes"]
        if exc.code != "unhandled_ports" or left:
            bad.append(f"capture raised {exc.code} and left sandboxes {left}")
    else:
        bad.append("capture took a rect with an unhandled port")
    return Result(not bad, "; ".join(bad) or f"{len(results)} refusals, none wrote a folder", data={"results": results})


def _write(root, name, rates, w, h, tech, summary=""):
    folder = Path(root) / name
    folder.mkdir(parents=True)
    (folder / "design.json").write_text(json.dumps({
        "name": name, "summary": summary or name, "products": sorted(rates), "ports": [], "footprint": {"w": w, "h": h},
        "tags": {"items": sorted(rates), "tech": tech}, "bench": {"rates": rates}, "render": {"file": "render.png"},
        "admitted": "2026-01-01T00:00:00+00:00", "author": "fixture"}))


@fixture(source="create", tags={"designs"})
def designs_find(lab):
    """find filters by item, min_rate, footprint and tech, ranks by rate per tile, and show returns the record."""
    problems = []
    with tempfile.TemporaryDirectory() as root:
        _write(root, "big-green", {"logistic-science-pack": 60.0, "iron-plate": -100.0}, 10, 10, ["logistic-science-pack"])
        _write(root, "tight-green", {"logistic-science-pack": 30.0}, 5, 4, ["logistic-science-pack", "fast-inserter"])
        _write(root, "plain-red", {"automation-science-pack": 45.0}, 6, 5, ["automation-science-pack"])
        (Path(root) / ".half-written.tmp").mkdir()
        (Path(root) / "no-design-json").mkdir()

        def names(*args, **kw):
            return [r["name"] for r in designs.find(*args, root=root, **kw)]

        checks = {
            "by item": (names("logistic-science-pack"), ["tight-green", "big-green"]),
            "by other item": (names("automation-science-pack"), ["plain-red"]),
            "an input is not a product": (names("iron-plate"), []),
            "unknown item": (names("rocket-part"), []),
            "min_rate": (names("logistic-science-pack", min_rate=40), ["big-green"]),
            "min_rate on the line": (names("logistic-science-pack", min_rate=30), ["tight-green", "big-green"]),
            "max_w": (names("logistic-science-pack", max_w=6), ["tight-green"]),
            "max_h": (names("logistic-science-pack", max_h=9), ["tight-green"]),
            "both sides": (names("logistic-science-pack", max_w=10, max_h=10), ["tight-green", "big-green"]),
            "too small": (names("logistic-science-pack", max_w=4, max_h=4), []),
            "tech without fast-inserter": (names("logistic-science-pack", tech=["logistic-science-pack"]), ["big-green"]),
            "tech with both": (names("logistic-science-pack", tech=["logistic-science-pack", "fast-inserter"]),
                               ["tight-green", "big-green"]),
            "tech empty": (names("logistic-science-pack", tech=[]), []),
            "no item lists all by name": (names(), ["big-green", "plain-red", "tight-green"]),
            "no item, small": (names(max_h=4), ["tight-green"]),
        }
        for label, (got, want) in checks.items():
            if got != want:
                problems.append(f"{label}: {got}, expected {want}")
        rows = designs.find("logistic-science-pack", root=root)
        top = rows[0]
        if (top["rate"], top["footprint"], Path(top["path"]).name, top["summary"]) != (30.0, {"w": 5, "h": 4}, "tight-green", "tight-green"):
            problems.append(f"row shape {top}")
        if rows[0]["rate_per_tile"] <= rows[1]["rate_per_tile"]:
            problems.append(f"not sorted by rate per tile: {[r['rate_per_tile'] for r in rows]}")
        if _refusal(lambda: designs.find(min_rate=5, root=root)) != "ValueError":
            problems.append("min_rate without an item was accepted")
        if designs.show("plain-red", root=root)["bench"]["rates"] != {"automation-science-pack": 45.0}:
            problems.append("show returned another record")
        try:
            designs.show("nope", root=root)
        except KeyError:
            pass
        else:
            problems.append("show of a missing design returned")
        if designs.find("anything", root=Path(root) / "missing"):
            problems.append("a missing root found something")
    return Result(not problems, "; ".join(problems) or f"{len(checks)} lookups and the sort order hold")
