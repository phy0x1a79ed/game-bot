"""The fixture registry: each fixture builds a world in its own lab, exercises one tool, and reports pass or fail.

A fixture returns a Result. `score` is optional and higher is better; the ratchet compares scores across
tool versions only between fixtures of the same name.
"""

from dataclasses import dataclass, field
from pathlib import Path

LUA = Path(__file__).resolve().parents[1] / "lua"
FIXTURES = {}


@dataclass
class Result:
    ok: bool
    detail: str = ""
    score: float | None = None
    data: dict = field(default_factory=dict)


def fixture(source="create", tags=(), live=False, camera=False):
    """Register a fixture. `source` is "create" for a new world or the name of a realm save.

    live and camera are passed to Lab.up for the fixture's lab.
    """
    def wrap(fn):
        if fn.__name__ in FIXTURES:
            raise ValueError(f"fixture {fn.__name__} registered twice")
        FIXTURES[fn.__name__] = {"fn": fn, "source": source, "tags": set(tags), "live": live, "camera": camera}
        return fn
    return wrap


def near(value, target, slack=4):
    return abs(value - target) <= slack
