"""Wait census: what the factory waits for, per item, largest first. The top entry is the next project."""

import json
from pathlib import Path

from .bench import lua_value

LUA = Path(__file__).resolve().parent / "lua"


def census(lab, surface="nauvis", area=None):
    """Return {waits, blocked, other}. area is ((x0, y0), (x1, y1)) or None for the whole surface."""
    prelude = f"WAITS = {{surface = {json.dumps(surface)}, area = {lua_value([list(p) for p in area]) if area else 'nil'}}}\n"
    out = json.loads(lab.lua_file(LUA / "waits.lua", prelude=prelude))
    return {k: out.get(k) or ([] if k != "other" else {}) for k in ("waits", "blocked", "other")}


def top(result, n=10):
    lines = []
    for e in result["waits"][:n]:
        parts = [f"{e[k]} {k}" for k in ("machines", "inserters", "belts", "ghosts") if e[k]]
        made = f" (made here by {e['made_here']}{', all short' if e['derived'] else ''})" if e["made_here"] else ""
        lines.append(f"{e['item']}: {', '.join(parts)}{made}")
    return lines
