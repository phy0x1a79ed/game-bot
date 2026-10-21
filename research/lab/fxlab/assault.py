"""The assault bench: rate a combat tactic by how long it takes to clear a nest, what it loses and what it spends.

A tactic is a Lua file under research/lab/tactics/ (see its README). Each seed runs it from the same start state,
shifted by `seed` ticks, with every input landing at a fixed absolute tick. The driver is a console handler that
the run removes at the end. `where="world"` runs on the full nauvis, restarting the lab between seeds;
`where="slice"` runs on a cloned square and resets it between seeds.
"""

import json
import math
import shutil
import statistics
import subprocess
import time
from pathlib import Path

from .lab import SHARED, docker

TACTICS = Path(__file__).resolve().parents[1] / "tactics"
SAVE = "run4-closeout"
CLEAR_RADIUS = 40
SCAN_RADIUS = 70
LEAD = 300
STEP = 5
SPEED = 1000
POLL = 0.3
WALL_CAP = 1800

DRIVER = r"""
local cfg = helpers.json_to_table(%(cfg)s)
local surf = game.surfaces[cfg.surface]
local nest = {x = cfg.nest[1], y = cfg.nest[2]}
local A = {cfg = cfg, t0 = cfg.t0, given = {}, placed = {}, died = {}, kills = {}, lost_with = {}, tracked = {}}
assert(game.tick <= cfg.t0, "start tick " .. cfg.t0 .. " already passed at " .. game.tick)
if ASSAULT then script.on_nth_tick(1, nil) script.on_event(defines.events.on_entity_died, nil) end
ASSAULT = {A = A}

local function track(e)
  if e and e.valid and e.unit_number and not A.tracked[e.unit_number] then A.tracked[e.unit_number] = e end
end
local function entity_of(unit) return unit and game.get_entity_by_unit_number(unit) end

local ctx = {box = cfg.box, surface = surf, force = cfg.force, nest = nest, params = cfg.params, tick0 = cfg.t0,
             clear_radius = cfg.clear_radius, scan_radius = cfg.scan_radius}

function ctx.book(name, count) A.given[name] = (A.given[name] or 0) + count end

-- Items go in through the god `items` verb where it can address the entity, and by a plain insert elsewhere: the verb
-- finds an entity by unit number, which game.get_entity_by_unit_number gives for a character but not for a turret.
-- Returns how many fitted.
function ctx.give(e, name, count)
  if count <= 0 then return 0 end
  local n
  if e.unit_number and entity_of(e.unit_number) == e then
    local r = remote.call("sbx", "items", {name = cfg.box, target = "entity", entity = e.unit_number,
                                            items = {{name = name, count = count}}})
    if not r.ok then error("give " .. name .. ": " .. tostring(r.error) .. " " .. tostring(r.detail)) end
    n = r.inserted[name] or 0
  else
    n = e.insert{name = name, count = count}
  end
  ctx.book(name, n)
  track(e)
  return n
end

function ctx.place(name, pos, direction)
  local e = surf.create_entity{name = name, position = pos, force = cfg.force, direction = direction}
  if e then A.placed[name] = (A.placed[name] or 0) + 1 track(e) end
  return e
end

-- A body from the god `body` verb. Destructible unless opts.invulnerable.
function ctx.body(at, opts)
  opts = opts or {}
  local r = remote.call("sbx", "body", {name = cfg.box, at = at, reach = opts.reach or 1000,
                                         invulnerable = opts.invulnerable == true})
  if not r.ok then error("body: " .. tostring(r.error) .. " " .. tostring(r.detail)) end
  local e = entity_of(r.unit)
  A.placed.character = (A.placed.character or 0) + 1
  track(e)
  return e
end

function ctx.statics(radius)
  return surf.find_entities_filtered{force = "enemy", type = {"unit-spawner", "turret"}, position = nest,
                                     radius = radius or cfg.scan_radius}
end

local src = %(src)s
local chunk, lerr = load(src, "=tactic " .. cfg.tactic, "t", _ENV)
assert(chunk, lerr)
local T = chunk(ctx)
assert(type(T) == "table" and T.setup and T.step, "a tactic returns {setup, step}")
ASSAULT.T = T

local R2 = (cfg.scan_radius + 60) ^ 2
local function inventories(e, into)
  for i = 1, (e.get_max_inventory_index() or 0) do
    local inv = e.get_inventory(i)
    if inv then for _, it in pairs(inv.get_contents()) do into[it.name] = (into[it.name] or 0) + it.count end end
  end
end

script.on_event(defines.events.on_entity_died, function(ev)
  local e = ev.entity
  if not e.valid or e.surface.index ~= surf.index then return end
  local dx, dy = e.position.x - nest.x, e.position.y - nest.y
  if dx * dx + dy * dy > R2 then return end
  local f = e.force.name
  if f == cfg.force then
    A.died[e.name] = (A.died[e.name] or 0) + 1
    if e.unit_number and A.tracked[e.unit_number] then inventories(e, A.lost_with) end
  elseif f == "enemy" then
    A.kills[e.name] = (A.kills[e.name] or 0) + 1
  end
end)

local function finish(reason, err)
  A.finished, A.reason, A.err, A.end_tick = true, reason, err, game.tick
  game.tick_paused = true
end

script.on_nth_tick(1, function(e)
  if A.finished or e.tick < A.t0 then return end
  if not A.started then
    A.started = true
    local ok, err = pcall(T.setup)
    if not ok then finish("error", tostring(err)) end
    return
  end
  local rel = e.tick - A.t0
  if rel %% %(step)d ~= 0 then return end
  if surf.count_entities_filtered{force = "enemy", type = {"unit-spawner", "turret"}, position = nest,
                                  radius = cfg.clear_radius} == 0 then
    A.clear_tick = rel
    return finish("cleared")
  end
  if rel >= cfg.max_ticks then return finish("cap") end
  local ok, done = pcall(T.step, e.tick)
  if not ok then finish("error", tostring(done)) elseif done then finish("gave_up") end
end)
rcon.print("armed " .. cfg.t0)
"""

STATE = r"""
local A, T = ASSAULT.A, ASSAULT.T
local cfg = A.cfg
local surf = game.surfaces[cfg.surface]
local nest = {x = cfg.nest[1], y = cfg.nest[2]}
local held, fluid = {}, {}
local function put(into, name, n) into[name] = (into[name] or 0) + n end
for _, e in pairs(A.tracked) do
  if e.valid then
    for i = 1, (e.get_max_inventory_index() or 0) do
      local inv = e.get_inventory(i)
      if inv then for _, it in pairs(inv.get_contents()) do put(held, it.name, it.count) end end
    end
    if e.grid then
      for _, it in pairs(e.grid.get_contents()) do put(held, it.name, it.count or 1) end
    end
    local ok, fl = pcall(e.get_fluid_contents)
    if ok and fl then for n, amount in pairs(fl) do put(held, n, amount) end end
  end
end
local left = {spawners = 0, worms = 0, units = 0}
for _, e in pairs(surf.find_entities_filtered{force = "enemy", position = nest, radius = cfg.scan_radius}) do
  if e.type == "unit-spawner" then left.spawners = left.spawners + 1
  elseif e.type == "turret" then left.worms = left.worms + 1
  elseif e.type == "unit" then left.units = left.units + 1 end
end
local extra = T.report and select(2, pcall(T.report)) or nil
rcon.print(helpers.table_to_json({
  finished = A.finished or false, reason = A.reason, err = A.err, clear_tick = A.clear_tick,
  end_tick = A.end_tick, now = game.tick, t0 = A.t0, given = A.given, held = held, lost_with = A.lost_with,
  placed = A.placed, died = A.died, kills = A.kills, left = left, extra = extra,
  evo = game.forces.enemy.get_evolution_factor(surf)}))
"""

CENSUS = r"""
local s = game.surfaces["%(surface)s"]
local n = {%(x)s, %(y)s}
local out = {spawners = 0, worms = 0, units = 0}
for _, e in pairs(s.find_entities_filtered{force = "enemy", position = n, radius = 64}) do
  if e.type == "unit-spawner" then out.spawners = out.spawners + 1
  elseif e.type == "turret" then out.worms = out.worms + 1
  elseif e.type == "unit" then out.units = out.units + 1 end
end
out.evolution = game.forces.enemy.get_evolution_factor(s)
out.tick = game.tick
rcon.print(helpers.table_to_json(out))
"""

CLEANUP = r"""
script.on_nth_tick(1, nil)
script.on_event(defines.events.on_entity_died, nil)
ASSAULT = nil
game.speed = 1
game.tick_paused = true
rcon.print("clean")
"""


def lua_string(text):
    level = 2
    while f"]{'=' * level}]" in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[{text}]{eq}]"


def tactic_path(tactic):
    """A tactic name from research/lab/tactics, or a path to a Lua file."""
    p = Path(tactic)
    if p.suffix == ".lua" and p.exists():
        return p
    q = TACTICS / f"{tactic}.lua"
    if not q.exists():
        names = sorted(f.stem for f in TACTICS.glob("*.lua"))
        raise FileNotFoundError(f"no tactic {tactic!r}; have {', '.join(names)}")
    return q


def _area(nest_at, radius):
    x, y = nest_at
    return [[x - radius, y - radius], [x + radius, y + radius]]


def assault_open(lab, nest_at, where="world", radius=144, name="assault"):
    """Make the box a tactic runs in. Returns {box, where, area, census, base_tick, ...}; pass it to assault_run as `box`.

    `where="world"` adopts nauvis and the player force in place, so god calls act on the full world.
    `where="slice"` clones a square of `radius` around the nest onto its own surface, with the realm's research copied.
    A world box restarts the lab's server between seeds, which reloads the save the lab started from. The same
    restart gives a lab that an earlier run used back to its start state before this box opens.
    """
    nest_at = [float(nest_at[0]), float(nest_at[1])]
    if where not in ("world", "slice"):
        raise ValueError("where is 'world' or 'slice'")
    box = {"box": name, "where": where, "area": _area(nest_at, radius), "nest_at": nest_at, "base_tick": None}
    _make(lab, box, clean=True)
    box["census"] = json.loads(lab.lua(CENSUS % {"surface": box["surface"], "x": nest_at[0], "y": nest_at[1]}))
    return box


def _ingame(lab):
    res = subprocess.run(["docker", "logs", lab.container], capture_output=True, text=True)
    return (res.stdout + res.stderr).count("to(InGame)")


def _reload(lab, wait=180):
    """Restart the lab's server on a fresh copy of its save, keeping its lease slot, which a down and up would give away.

    The server saves its map over the lab's copy when it stops, so the copy is replaced from the cache first.
    """
    cached = [p for p in lab.saves.glob("*.zip") if (SHARED / "_saves" / p.name).exists()]
    if len(cached) != 1:
        raise RuntimeError(f"{lab.container}: cannot tell which save to reload from {[p.name for p in cached]}")
    seen = _ingame(lab)
    lab.close()
    docker("stop", "-t", "10", lab.container)
    shutil.copy(SHARED / "_saves" / cached[0].name, cached[0])
    docker("start", lab.container)
    deadline = time.time() + wait
    while _ingame(lab) <= seen:
        if time.time() > deadline or not lab.running():
            raise RuntimeError(f"{lab.container} did not come back:\n{lab.logs(20)}")
        time.sleep(0.3)
    for _ in range(3):
        if lab.lua("game.tick_paused = true rcon.print(tostring(game.tick_paused))").strip() == "true":
            return
    raise RuntimeError(f"{lab.container} would not pause")


def _state(lab):
    """What the bench knows of a lab: `epoch` counts reloads, `dirty` says a trial has run since the last one."""
    return lab.__dict__.setdefault("_assault", {"epoch": 0, "dirty": False, "boxes": {}})


def _make(lab, box, clean=False):
    """Make the box exist in the lab's current epoch. Returns the seconds spent reloading and building."""
    st = _state(lab)
    t0 = time.time()
    if st["dirty"] and (box["where"] == "world" or clean):
        _reload(lab)
        st["epoch"] += 1
        st["dirty"] = False
    if box.get("epoch") != st["epoch"]:
        if box["where"] == "world":
            rec = lab.sbx("sandbox_new", name=box["box"], inplace={"surface": "nauvis", "force": "player"})["sandbox"]
        else:
            lab.sbx("slice_build", name=box["box"], area=box["area"], source="nauvis", research="copy")
            rec = next(b for b in lab.sbx("sandbox_list")["sandboxes"] if b["name"] == box["box"])
        box.update(surface=rec["surface"], force=rec["force"], epoch=st["epoch"])
    return time.time() - t0


def _base_tick(lab, box):
    """The absolute tick every seed of this box starts from; a slice schedules its reset there."""
    now = lab.tick()
    if box["where"] == "world":
        if box["base_tick"] is None:
            box["base_tick"] = (now + LEAD) // 100 * 100 + 100
        return box["base_tick"]
    base = (now + LEAD) // 100 * 100 + 100
    lab.sbx("slice_reset_at", name=box["box"], tick=base)
    box["base_tick"] = base
    return base


def _drive(lab, speed=SPEED, cap=WALL_CAP):
    """Run until the driver pauses the game. Returns the wall seconds."""
    t0 = time.time()
    lab.lua(f"game.speed = {speed} game.tick_paused = false")
    while True:
        time.sleep(POLL)
        if lab.lua("rcon.print(tostring(ASSAULT and ASSAULT.A.finished or false))").strip() == "true":
            break
        if time.time() - t0 > cap:
            lab.lua("game.tick_paused = true")
            raise RuntimeError(f"assault run did not finish in {cap}s")
    lab.lua("game.speed = 1")
    return time.time() - t0


def _trial(lab, box, tactic, params, seed, max_ticks):
    restore_s = _make(lab, box)
    _state(lab)["dirty"] = True
    start = _base_tick(lab, box) + seed
    if box["where"] == "slice":
        start += 60
    cfg = {"box": box["box"], "surface": box["surface"], "force": box["force"], "nest": box["nest_at"],
           "params": params, "t0": start, "max_ticks": max_ticks, "tactic": Path(tactic).stem,
           "clear_radius": CLEAR_RADIUS, "scan_radius": SCAN_RADIUS}
    code = DRIVER % {"cfg": lua_string(json.dumps(cfg)), "src": lua_string(Path(tactic).read_text()), "step": STEP}
    t_wall = time.time()
    try:
        lab.lua(code)
        run_s = _drive(lab)
        raw = json.loads(lab.lua(STATE))
    finally:
        lab.lua(CLEANUP)
    return _record(raw, seed, start, run_s, restore_s, time.time() - t_wall)


def _record(raw, seed, start, run_s, restore_s, wall_s):
    def tally(m):
        return {k: v for k, v in (m or {}).items() if v}
    given, held, lost_with = raw["given"] or {}, raw["held"] or {}, raw["lost_with"] or {}
    spent = {n: round(g - held.get(n, 0), 1) for n, g in given.items()}
    spent = {n: v for n, v in spent.items() if v}
    return {
        "seed": seed, "t0": start, "cleared": raw["reason"] == "cleared", "reason": raw["reason"],
        "clear_tick": raw.get("clear_tick"), "ticks": (raw.get("end_tick") or raw["now"]) - start,
        "losses": tally(raw["died"]), "kills": tally(raw["kills"]), "placed": tally(raw["placed"]),
        "inserted": tally(given), "spent": spent,
        "lost_with_dead": {n: v for n, v in lost_with.items() if v},
        "fired": {n: round(v - lost_with.get(n, 0), 1) for n, v in spent.items()},
        "left": raw["left"], "evo": raw["evo"], "err": raw.get("err"), "extra": raw.get("extra"),
        "wall_s": round(wall_s, 1), "run_s": round(run_s, 1), "restore_s": round(restore_s, 1),
    }


def assault_run(lab, tactic, params=None, seeds=5, max_ticks=18000, nest_at=None, where="world", box=None,
                radius=144):
    """Run a tactic `seeds` times from the same start state. Returns one trial record per seed.

    A trial: cleared, clear_tick, losses and kills by entity name, items inserted and spent, entities placed,
    what is left of the nest. Reuses the lab's open box for the same nest and `where`, or pass `box`.
    """
    path = tactic_path(tactic)
    if box is None:
        boxes = _state(lab)["boxes"]
        key = (where, tuple(float(v) for v in nest_at) if nest_at else None)
        if key not in boxes:
            if nest_at is None:
                raise ValueError("nest_at is needed to open a box")
            boxes[key] = assault_open(lab, nest_at, where=where, radius=radius, name=f"assault-{where}")
        box = boxes[key]
    return [_trial(lab, box, path, params or {}, seed, max_ticks) for seed in range(1, seeds + 1)]


def _spread(values):
    values = list(values)
    return {"median": statistics.median(values), "min": min(values), "max": max(values)}


def _per_name(trials, key):
    names = sorted({n for t in trials for n in t[key]})
    return {n: _spread(t[key].get(n, 0) for t in trials) for n in names}


def assault_report(trials):
    """Median and min-max over seeds of clear time, losses, spend and kills, with the clear rate."""
    cleared = [t for t in trials if t["cleared"]]
    rep = {
        "seeds": len(trials), "clear_rate": len(cleared) / len(trials) if trials else 0.0,
        "clear_tick": _spread(t["clear_tick"] for t in cleared) if cleared else None,
        "losses": _per_name(trials, "losses"), "spent": _per_name(trials, "spent"),
        "kills": _per_name(trials, "kills"), "placed": _per_name(trials, "placed"),
        "lost_with_dead": _per_name(trials, "lost_with_dead"),
        "losses_total": _spread(sum(t["losses"].values()) for t in trials) if trials else None,
        "wall_s": _spread(t["wall_s"] for t in trials) if trials else None,
    }
    return rep


def _range(trials, metric):
    if metric == "clear_tick":
        vals = [t["clear_tick"] if t["cleared"] else math.inf for t in trials]
    elif metric == "losses":
        vals = [sum(t["losses"].values()) for t in trials]
    else:
        vals = [sum(t["spent"].values()) for t in trials]
    return min(vals), max(vals)


def _num(x):
    return None if x == math.inf else x


def assault_compare(a, b):
    """Say which tactic clears faster, and call the difference real only when the min-max ranges do not overlap.

    `a` and `b` are lists of trials. An uncleared trial counts as infinitely slow. Losses and spend get the same test.
    """
    out = {}
    for metric in ("clear_tick", "losses", "spent"):
        ra, rb = _range(a, metric), _range(b, metric)
        lower = "a" if ra[1] < rb[0] else "b" if rb[1] < ra[0] else None
        out[metric] = {"a": [_num(ra[0]), _num(ra[1])], "b": [_num(rb[0]), _num(rb[1])], "lower": lower,
                       "verdict": f"{lower} is lower" if lower else "within noise"}
    c = out["clear_tick"]
    better = c["lower"]
    out["better"] = better
    out["real"] = better is not None
    out["verdict"] = f"{better} clears faster" if better else "within noise"
    return out


def _cli(args):
    from .lab import Lab
    params = {}
    for pair in args.param or []:
        k, _, v = pair.partition("=")
        try:
            params[k] = json.loads(v)
        except json.JSONDecodeError:
            params[k] = v
    lab = Lab(args.lab)
    lab.down()
    lab.up(save=args.save, cpus=args.cpus)
    try:
        trials = assault_run(lab, args.tactic, params=params, seeds=args.seeds, max_ticks=args.max_ticks,
                             nest_at=args.nest, where=args.where)
    finally:
        lab.down()
    out = assault_report(trials)
    if args.trials:
        out["trials"] = trials
    print(json.dumps(out, indent=1))
    return 0


def register(sub):
    p = sub.add_parser("assault", help="rate a combat tactic on a nest: assault <tactic> --nest X Y")
    p.add_argument("tactic", help="a name under research/lab/tactics, or a path to a Lua file")
    p.add_argument("--nest", type=float, nargs=2, required=True, metavar=("X", "Y"))
    p.add_argument("--where", choices=("world", "slice"), default="world")
    p.add_argument("--seeds", type=int, default=5)
    p.add_argument("--param", action="append", metavar="K=V", help="a tactic parameter, value parsed as JSON")
    p.add_argument("--max-ticks", type=int, default=18000)
    p.add_argument("--save", default=SAVE)
    p.add_argument("--cpus", type=float, default=2.0)
    p.add_argument("--lab", default="assault", help="name of the lab to bring up and take down")
    p.add_argument("--trials", action="store_true", help="include every trial in the output")
    return {"assault": _cli}
