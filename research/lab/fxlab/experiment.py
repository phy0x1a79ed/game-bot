"""Play-level experiment: a model plays a lab through one arm's command set, then the run is scored.

Each arm gets its own lab and a scratch directory holding `fx`, the only command its agent may run. The lab
stays paused except under `fx advance`, which stops at the game-time budget. The score is what the factory
makes of the target item per minute over a fixed window after the agent stops, against an untouched copy of
the save advanced by the same game time. The balance gate runs over the whole session.

A scenario prepares each lab after it loads. The default, calm, removes enemies: on run 4 with enemies, one
empty chest ghost moved the 10-minute score by 7% and the 60-minute score by half, because battles and
trains amplify any perturbation. `--noise N` measures a scenario's floor before its scores are trusted.
"""

import argparse
import json
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import balance
from .lab import ROOT, Lab

HERE = Path(__file__).resolve().parent
FXLAB = HERE.parent / "fxlab.sh"
EXPERIMENTS = ROOT / "experiments"
TICKS_PER_MIN = 3600
SCENARIOS = {"calm": HERE / "lua" / "scenario-calm.lua", "as-saved": None}

COMMON = """\
You are playing Factorio 2.1 (base game, no Space Age content) on a headless server, through the `./fx` \
command. There is no player character. The factory is a mid-game base with a construction-robot network. \
Enemies are switched off.

Goal: raise the factory's sustained {item} output, measured as {item} made per minute.

Rules:
- The game is paused except while you run `./fx advance <ticks>` (60 ticks = 1 second). You have {budget} \
game minutes in total. `./fx time` shows how much is left.
- When you stop, the score is the {item} made per minute over the next {window} game minutes, compared with \
the same factory left untouched for the same game time. So finished builds count. Half-built ones do not.
- Every item must come from production. A check over the whole session compares the items in the world \
with the production statistics. An item created or deleted by script disqualifies the run.
- Construction robots build ghosts from the robot network's storage, and deconstruct what is marked.
- Only the `./fx` command is available. Run exactly one `./fx` command per Bash call: a command chained \
with `;`, `&&` or a pipe, or any other program, is refused and wastes a turn.

You decide what to build and where. Stop when you are satisfied or the game time is spent, then reply \
with a short summary of what you changed and why.

Commands:
  ./fx time                      game time used and left
  ./fx advance <ticks>           run the game
"""

ARMS = {
    "raw": COMMON + """\
  ./fx lua - <<'EOF'             run Factorio Lua as a server command; print results with rcon.print(...)
  ...lua...                      (the full runtime API: game, prototypes, helpers, defines)
  EOF
""",
    "tools": COMMON + """\
  ./fx waits [-n N] [--area X0 Y0 X1 Y1]
        what the factory waits for, per item, largest first: machines short of it, inserters waiting on
        it, belts empty at the consumer, ghosts the robots cannot cover. Also output-blocked machines.
  ./fx tools                     the library tools: name, summary and args
  ./fx tool <name> key=value ... run one library tool; JSON values are parsed (e.g. items='["coal"]')
""",
}

WRAPPER = """#!/usr/bin/env bash
# fx: this experiment's only door into its lab.
lab={lab} arm={arm} cap={cap} state="$(dirname "$0")/.ticks"
fxlab={fxlab}
used=$(cat "$state" 2>/dev/null || echo 0)
cmd=${{1:-}}; shift || true
case "$cmd" in
  time) echo "used $((used / 3600)) of $((cap / 3600)) game minutes ($used of $cap ticks)" ;;
  advance)
    n=${{1:-0}}
    [[ "$n" =~ ^[0-9]+$ ]] || {{ echo "advance takes a tick count"; exit 2; }}
    left=$((cap - used))
    [ "$left" -le 0 ] && {{ echo "game time spent"; exit 2; }}
    [ "$n" -gt "$left" ] && n=$left
    "$fxlab" advance "$lab" "$n" >/dev/null || exit 1
    echo $((used + n)) > "$state"
    echo "advanced $n ticks; $(((cap - used - n) / 3600)) game minutes left" ;;
  lua) [ "$arm" = raw ] || {{ echo "no such command"; exit 2; }}; exec "$fxlab" lua "$lab" "$@" ;;
  tool|tools|waits) [ "$arm" = tools ] || {{ echo "no such command"; exit 2; }}; exec "$fxlab" "$cmd" "$lab" "$@" ;;
  *) echo "commands: time, advance$( [ "$arm" = raw ] && echo ", lua" || echo ", tools, tool, waits")"; exit 2 ;;
esac
"""


def made_per_min(lab, item, ticks):
    """Advance ticks and return item made per minute over them."""
    q = f'rcon.print(game.forces.player.get_item_production_statistics(game.surfaces.nauvis).get_input_count("{item}"))'
    first = float(lab.lua(q))
    t0 = lab.tick()
    lab.advance(ticks)
    return (float(lab.lua(q)) - first) / ((lab.tick() - t0) / TICKS_PER_MIN)


def start(lab, save, scenario):
    lab.up(save=save)
    if SCENARIOS[scenario]:
        lab.lua_file(SCENARIOS[scenario])


def run_arm(arm, out, save, item, budget_min, window_min, model, max_turns, scenario="calm"):
    d = out / arm
    d.mkdir(parents=True)
    lab = Lab(f"ex-{out.name[-6:]}-{arm}")
    cap = budget_min * TICKS_PER_MIN
    (d / "fx").write_text(WRAPPER.format(lab=lab.name, arm=arm, cap=cap, fxlab=FXLAB))
    (d / "fx").chmod(0o755)
    prompt = ARMS[arm].format(item=item, budget=budget_min, window=window_min)
    (d / "prompt.txt").write_text(prompt)
    rec = {"arm": arm, "model": model, "save": save, "scenario": scenario, "item": item, "budget_min": budget_min,
           "clock": "paused except under fx advance"}
    try:
        start(lab, save, scenario)
        if arm == "tools":
            from . import tools
            tools.sync(lab)
        before = balance.snapshot(lab)
        tick0 = lab.tick()
        t0 = time.time()
        with open(d / "agent.json", "w") as fh, open(d / "agent.err", "w") as err:
            subprocess.run(["claude", "-p", prompt, "--model", model, "--safe-mode", "--strict-mcp-config",
                            "--setting-sources", "project", "--permission-mode", "default",
                            "--allowedTools", "Bash(./fx:*)",
                            "--disallowedTools", "Write Edit NotebookEdit WebFetch WebSearch Agent Task",
                            "--max-turns", str(max_turns), "--output-format", "json"],
                           cwd=d, stdin=subprocess.DEVNULL, stdout=fh, stderr=err)
        rec["agent_wall_s"] = round(time.time() - t0, 1)
        try:
            agent = json.loads((d / "agent.json").read_text())
            rec["agent"] = {k: agent.get(k) for k in ("num_turns", "total_cost_usd", "duration_ms", "is_error",
                                                       "subtype", "result", "usage")}
            rec["agent"]["denials"] = len(agent.get("permission_denials") or [])
        except ValueError:
            rec["agent"] = {"error": (d / "agent.err").read_text()[-2000:]}
        rec["game_ticks"] = lab.tick() - tick0
        after = balance.snapshot(lab)
        (d / "census.json").write_text(json.dumps({"before": before, "after": after}))
        v = balance.judge(before, after)
        rec["balance"] = {"ok": v.ok, "summary": v.summary(), "created": v.created, "deleted": v.deleted}
        rec["score"] = round(made_per_min(lab, item, window_min * TICKS_PER_MIN), 1)
    finally:
        lab.down()
    (d / "record.json").write_text(json.dumps(rec, indent=1))
    return rec


def run_baseline(out, save, item, ticks, window_min, scenario="calm"):
    lab = Lab(f"ex-{out.name[-6:]}-base{ticks}")
    try:
        start(lab, save, scenario)
        if ticks:
            lab.advance(ticks)
        return round(made_per_min(lab, item, window_min * TICKS_PER_MIN), 1)
    finally:
        lab.down()


NUDGE = """local s = game.surfaces.nauvis
local r = s.find_entities_filtered{type = "roboport", force = "player"}
local e = r[%d %% #r + 1]
local at = e and s.find_non_colliding_position("iron-chest", e.position, 10, 1, true)
local g = at and s.create_entity{name = "entity-ghost", inner_name = "iron-chest", position = at, force = "player"}
rcon.print(tostring(g ~= nil))"""


def nudge(lab, i):
    """The smallest real change: one iron-chest ghost beside the i-th roboport, for robots to build."""
    return lab.lua(NUDGE % i).strip() == "true"


def noise(save, item, window_min, n, scenario, ticks=8400):
    """Score n labs that each differ by one nudge: the spread is the floor a gain must clear."""
    def one(i):
        lab = Lab(f"noise-{i}")
        try:
            start(lab, save, scenario)
            nudged = nudge(lab, 7 * i)
            lab.advance(ticks)
            return round(made_per_min(lab, item, window_min * TICKS_PER_MIN), 1), nudged
        finally:
            lab.down()
    with ThreadPoolExecutor(max_workers=min(n, 4)) as pool:
        runs = list(pool.map(one, range(n)))
    scores = [s for s, _ in runs]
    return {"scores": scores, "nudged": [k for _, k in runs], "spread": round(max(scores) - min(scores), 1)}


def main(argv=None):
    p = argparse.ArgumentParser(prog="fxlab.experiment")
    p.add_argument("--save", default="run4-closeout")
    p.add_argument("--item", default="iron-plate")
    p.add_argument("--arms", nargs="+", default=list(ARMS))
    p.add_argument("--budget", type=int, default=60, help="game minutes the agent may advance")
    p.add_argument("--window", type=int, default=10, help="game minutes the score is measured over")
    p.add_argument("--model", default="sonnet")
    p.add_argument("--max-turns", type=int, default=80)
    p.add_argument("--scenario", choices=list(SCENARIOS), default="calm")
    p.add_argument("--noise", type=int, metavar="N", help="only measure the scenario's noise floor over N labs")
    a = p.parse_args(argv)
    if a.noise:
        print(json.dumps(noise(a.save, a.item, a.window, a.noise, a.scenario)))
        return
    out = EXPERIMENTS / time.strftime("%Y%m%d-%H%M%S")
    out.mkdir(parents=True)
    with ThreadPoolExecutor(max_workers=len(a.arms)) as pool:
        recs = list(pool.map(lambda arm: run_arm(arm, out, a.save, a.item, a.budget, a.window, a.model,
                                                 a.max_turns, a.scenario), a.arms))
    ticks = sorted({r.get("game_ticks", 0) for r in recs})
    with ThreadPoolExecutor(max_workers=len(ticks)) as pool:
        base = dict(zip(ticks, pool.map(lambda t: run_baseline(out, a.save, a.item, t, a.window, a.scenario), ticks)))
    for r in recs:
        r["baseline"] = base[r.get("game_ticks", 0)]
        r["gain"] = round(r["score"] - r["baseline"], 1) if "score" in r else None
        ag = r.get("agent", {})
        print(f"{r['arm']}: score {r.get('score')} vs untouched {r['baseline']} (gain {r['gain']}), "
              f"{r['balance']['summary'] if 'balance' in r else 'no balance'}, {r.get('game_ticks', 0) // 3600} game min, "
              f"{ag.get('num_turns')} turns, ${ag.get('total_cost_usd')}")
    (out / "summary.json").write_text(json.dumps(recs, indent=1))
    print(out)


if __name__ == "__main__":
    main()
