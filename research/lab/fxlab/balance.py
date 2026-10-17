"""Balance gate: items that appeared or vanished without passing through the production statistics.

For each item, residual = (change in the world) - (made - used) over a window. Honest play leaves every
residual near zero, because every legal way an item enters or leaves the world is a craft, a mine, a
burn or a placement, and placements are counted as the placing item. A positive residual is an item
created from nothing. A negative residual is an item deleted, which only enemy kills, or use for an
item that is spent in use (ammo, repair packs, capsules), may explain.
"""

import json
from dataclasses import dataclass, field
from pathlib import Path

CENSUS = Path(__file__).resolve().parent / "lua" / "census.lua"


def snapshot(lab):
    return json.loads(lab.lua_file(CENSUS))


def _delta(a, b, key):
    names = set(a[key]) | set(b[key])
    return {n: b[key].get(n, 0) - a[key].get(n, 0) for n in names}


@dataclass
class Verdict:
    ok: bool
    created: dict = field(default_factory=dict)
    deleted: dict = field(default_factory=dict)
    explained_by_losses: dict = field(default_factory=dict)
    ticks: int = 0

    def summary(self):
        if self.ok:
            return f"balance OK over {self.ticks} ticks"
        parts = [f"+{n:g} {k}" for k, n in sorted(self.created.items(), key=lambda kv: -kv[1])]
        parts += [f"{n:g} {k}" for k, n in sorted(self.deleted.items(), key=lambda kv: kv[1])]
        return f"balance FAIL over {self.ticks} ticks: " + ", ".join(parts)


def residuals(before, after):
    world = _delta(before, after, "world")
    made = _delta(before, after, "made")
    used = _delta(before, after, "used")
    names = set(world) | set(made) | set(used)
    return {n: world.get(n, 0) - (made.get(n, 0) - used.get(n, 0)) for n in names}


def tolerance_for(name, before, after, absolute=3.0, relative=0.01):
    """In-progress crafts and burners hold a few items outside every inventory, in proportion to flow."""
    flow = sum(abs(after[k].get(name, 0) - before[k].get(name, 0)) for k in ("made", "used"))
    return absolute + relative * flow


def judge(before, after):
    """Gate a window. Deletions up to the placing items of entities enemies killed are excused."""
    res = residuals(before, after)
    spent = set(before.get("spent", {})) | set(after.get("spent", {}))
    lost = _delta(before, after, "lost")
    loss_allowance = {}
    for entity, n in lost.items():
        item = after.get("placers", {}).get(entity, entity)
        loss_allowance[item] = loss_allowance.get(item, 0) + n
    created, deleted, excused = {}, {}, {}
    for name, r in res.items():
        tolerance = tolerance_for(name, before, after)
        if r > tolerance:
            created[name] = r
        elif r < -tolerance:
            allowed = loss_allowance.get(name, 0)
            if name in spent or -r <= allowed + tolerance:
                excused[name] = r
            else:
                deleted[name] = r
    return Verdict(ok=not created and not deleted, created=created, deleted=deleted,
                   explained_by_losses=excused, ticks=after["tick"] - before["tick"])
