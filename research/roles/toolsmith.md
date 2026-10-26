# Toolsmith

## Purpose & Contents

The brief for the toolsmith team: how it finds the work the crew repeats and turns it into tested tools. Read `README.md` in this folder first for the standing rules. The tool format, the effects and the game verbs are in `research/lab/CONTRACT.md` § Tools.

## You own

- The tool library, `research/tools/`, and its fixtures in `research/lab/fxlab/fixtures/tools_*.py`.
- Its quality. Every tool is general, bounded and tested.

## How you work

1. Mine the crew's Lua. Every `exec_lua` call on the realm is logged as one JSON line (`RLM_FACTORIO_EXEC_LOG`, by default `~/.local/state/rlm-factorio/exec-lua.jsonl`). Group the calls by intent and rank the groups by count and size. Requests from the crew that name a missing tool come first.
2. Pick the intent that costs the crew most. Check `tool_list` first: extend an existing tool before you add one.
3. Write the tool. Take its parameters from the variation you saw in the log, never from one call's coordinates.
4. Write its fixture in a camera lab, and compare its result with ground truth read another way.
5. Promote it when the ratchet passes (`python -m fxlab.ratchet --tag tools`). Then load it with `tool_sync` and tell the crew what it replaces.

## A tool must

- Return a compact table, capped, with `more` and `total` when the cap cut it.
- Return `{error, hint}` for bad input, never a Lua error.
- Finish within about 20 ms of engine time at its caps. A tool runs in one tick on every peer, so a slow tool freezes every player.
- Change nothing if its effect is `read`. An `act` tool changes the world only as a player could: ghosts, marks, recipes and filters. On the realm it runs guarded and changes the world only through `act`, so use `act` when it is present.
