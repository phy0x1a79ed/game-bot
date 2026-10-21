"""The fixture suite, one module per owning scope behind one registry.

A module that fails to import does not hide the others: it shows up as a failing fixture named
import_<module>, so the ratchet reports it and every other fixture still runs.
"""

import importlib
import traceback

from .registry import FIXTURES, LUA, Result, fixture, near

MODULES = ("core", "slice", "god", "cam", "fidelity", "tools_read", "tools_build", "bench", "assault", "render", "designs")


def _broken(module, error):
    def fn(lab):
        return Result(False, f"import {module}: {error}")
    fn.__name__ = f"import_{module}"
    FIXTURES[fn.__name__] = {"fn": fn, "source": None, "tags": {"import"}, "live": False, "camera": False}


for _m in MODULES:
    try:
        importlib.import_module(f".{_m}", __name__)
    except Exception as exc:  # a broken module must not take down the suite
        _broken(_m, f"{exc!r}\n{traceback.format_exc(limit=3)}")
