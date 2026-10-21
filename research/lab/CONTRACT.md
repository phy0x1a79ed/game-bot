# fxlab contract

## Purpose & Contents

This file fixes the interfaces that parallel scopes build against: who owns which file, the `sbx` remote interface of the lab mod, the tool library format and its game and realm verbs, the fixture rules, and the shared data formats. Change an interface here first, in the hub, before any scope codes against the change. Behaviour that the code shows on its own stays out of this file.

## Ownership

Each scope edits only the files it owns. A scope that needs a change in another scope's file states the change in its report instead.

| Scope | Owns |
|---|---|
| `fxlab` (hub) | this file, `lab.py`, `__main__.py`, `tools.py`, `ratchet.py`, `fixtures/__init__.py`, `fixtures/registry.py`, `mods/fxlab-sbx/control.lua`, `mods/fxlab-sbx/sbx.lua` |
| `fxlab-slice` | `mods/fxlab-sbx/slice.lua`, `fixtures/slice.py` |
| `fxlab-god` | `mods/fxlab-sbx/god.lua`, `fixtures/god.py` |
| `fxlab-cam` | `camera.py`, `mods/fxlab-sbx/view.lua`, `fixtures/cam.py` |
| `fxlab-fid` | `fixtures/fidelity.py`, `research/lab/fidelity/` |
| `fxlab-tools-read` | `research/tools/read/`, the read section of `fixtures/tools.py` |
| `fxlab-tools-build` | `research/tools/build/`, the build section of `fixtures/tools.py` |
| `fxlab-bench` | `bench.py`, `fixtures/bench.py` |
| `fxlab-assault` | `assault.py`, `research/lab/tactics/`, `fixtures/assault.py` |
| `fxlab-render` | `render.py`, `fixtures/render.py`, new verbs appended to `view.lua` |
| `fxlab-designs` | `designs.py`, `research/designs/`, `fixtures/designs.py` |
| `rlm-factorio` (awm) | `appliance/mods/game-bot-control/` |
| `rlm-factorio-lab` (awm) | `awm/rlm_factorio/hub_adapter.py`, `validate.py`, `tests/`, `appliance/seat.sh` |

Paths without a directory are under `research/lab/fxlab/`.

## Labs

**WARNING** Never touch the live realm. Do not `docker exec` into an `rlm-factorio` container, do not write to the `rlm-factorio_factorio-saves` volume and do not take a seat. Reach the game only through `fxlab` labs.

- Run the CLI with `research/lab/fxlab.sh`. It uses the `game-bot` env's interpreter.
- Each worktree gets its own container prefix (`fxlab-<scope>-`) and lab root (`~/.cache/fxlab/scopes/<scope>/`). `FXLAB_PREFIX` and `FXLAB_ROOT` override them. Realm saves are cached once, in `~/.cache/fxlab/_saves/`.
- A lease caps the box at `FXLAB_MAX_LABS` lab servers (default 3), counted across every worktree. `Lab.up` waits for a free slot. Keep your labs few and take them down when done: `fxlab.sh down --all` removes this worktree's labs.
- `Lab.up(live=True)` leaves the game running. The default pauses it, and existing fixtures rely on that.
- `FXLAB_GBC_MOD` points labs at another copy of `game-bot-control`. Set it to the `rlm-factorio` scope's `appliance/mods/game-bot-control` to test mod 0.6 before it deploys.
- An RCON call costs one game frame (16.7 ms at speed 1). Batch work into one call.

## sbx: the lab mod

`mods/fxlab-sbx` is mounted into every lab, never into the realm. It owns sandboxes: a sandbox is a named pair of a surface (`sbx-<name>`) and a force (`sbx-<name>`), friends and at cease-fire with `player`. Sandbox surfaces are hidden from every other force.

### Calling convention

- Call `remote.call("sbx", verb, args)` with one args table. From Python, call `lab.sbx(verb, **args)` or `fxlab.sh sbx <lab> <verb> key=value ...`.
- Every verb returns a table with `ok`. A failure returns `{ok = false, error = <code>, detail = <text>}`, and `lab.sbx` raises `SbxError` with `.code`.
- Fail with `sbx.fail(code, detail)` inside a verb. Any other raised error becomes `error = "lua_error"`.
- **CAUTION** Lua encodes an empty list and an empty map the same way. Python sees `{}` for an empty list. Coerce with `list(x) if x else []`.

Error codes: `bad_args`, `no_sandbox`, `exists`, `force_cap`, `standard_mode`, `unhandled_ports`, `not_found`, `lua_error`. Add a code here before you use a new one.

### Modules

- `control.lua` is the dispatcher. It alone registers event handlers, because Factorio keeps one handler per event per mod and a second registration silently replaces the first.
- A module returns a table with optional hooks: `on_init`, `on_configuration_changed`, `on_load`, `on_tick(ev)`, `nth = {[n] = fn}`, `events = {[defines.events.x] = fn}`, and `on_drop(name, box)`, which runs before any sandbox is dropped, whichever verb drops it. A hook that raises aborts the drop. It exports verbs as `remote = {verb = fn}`. A verb name defined twice stops the mod from loading.
- A module keeps its state under its own key: `storage.sbx` (core), `storage.slice`, `storage.god`, `storage.view`.
- **WARNING** `on_load` must not write `storage`. A save whose `on_load` changes `storage` does not load.
- **CAUTION** Every peer runs the mod, the camera client included. Keep every state change deterministic. Use no `math.random` outside `game.create_random_generator`, and no state kept in Lua locals across ticks that a joining peer would not have.

### Core (`sbx.lua`, hub)

| Verb | Args | Returns |
|---|---|---|
| `sandbox_new` | `name`, `research = "copy" \| "none"` (default copy), or `inplace = {surface, force}` | `sandbox` record |
| `sandbox_drop` | `name` | |
| `sandbox_list` | | `sandboxes`: name, surface, force, mode, created, inplace, ledger (entry count) |
| `verbs` | | every verb name |

Module functions for the other modules: `sbx.get(name)`, `sbx.new(args)`, `sbx.drop(name)`, `sbx.own_surface(name, surface)` (a further surface deleted with the box; `sbx-<name>-snap` is always deleted), `sbx.surface(box)`, `sbx.force(box)`, `sbx.require_god(name)`, `sbx.ledger_add(name, entry)`, `sbx.ledger(name)`, `sbx.fail(code, detail)`.

An in-place box adopts an existing surface and force, for example `nauvis` and `player`. Dropping it only removes the record. Its owner removes what it placed first.

A new sandbox starts in `god` mode. **CAUTION** The game allows 64 forces, so about 60 sandboxes fit in a world. Dropping a sandbox deletes its surfaces and merges its force into `neutral` at the end of the tick, so do not recreate the same name in the same tick.

### The god ledger and modes

Every god call records what it did with `sbx.ledger_add(name, entry)`. `entry.kind` is one of:

- `entity`: `entity = <LuaEntity>`. A spawned infinity chest, loader, pipe, void, power interface, nest, unit or body. Slice port closers count too.
- `bonus`: `field`, `before`, `after`. A force bonus that a god call set.
- `research`: `tech`, `before = {researched, level}`, `after`. Or `recipe`, with `before` and `after` as the enabled flag.
- `body`: `entity`, `before = {reach, build, mine, destructible}`.

`sbx_mode{name, mode = "standard", research = "copy" | "keep"}` walks the ledger backwards and undoes each entry. It skips an entity that is no longer valid. In standard mode every god verb fails with `standard_mode`, and reads still work. `sbx_mode{name, mode = "god"}` enables god verbs again. The ledger keeps growing across switches: an undone entry stays, flagged `undone`, so a second switch skips it. `research = "copy"` always ends with `copy_from(player)`, because standard rules mean the player's research. `slice_reset` prunes entity entries whose entity is gone.

### Slicing (`slice.lua`, fxlab-slice)

The slice is cloned to the same coordinates on the sandbox surface, so positions compare one to one with the source.

| Verb | Args | Returns |
|---|---|---|
| `slice_build` | `name`, `area = {{x0, y0}, {x1, y1}}`, `source = "nauvis"`, `research` | `sandbox`, `area`, `entities`, `ports`, `unhandled`, `rails` (those near the edge), `rail_count` |
| `slice_inplace` | `name`, `area`, `source = "nauvis"` | the same shape, for the in-place arm on the source surface |
| `slice_reset` | `name`, `trains_auto = true` | `entities` |
| `slice_timing` | | the last slice verb's phase timings, in ms |
| `slice_reset_at` | `name`, `tick` | |
| `slice_drop` | `name` | |
| `slice_list` | | `slices`: name, area, entities, ports, unhandled counts, `reset_at`, `last_error` |
| `slice_ports` | `name` | `ports`, `unhandled`, `rails` in full |
| `slice_area_of_base` | `surface = "nauvis"`, `force = "player"`, `pad = 32` | `area` |
| `slice_fingerprint` | `name`, `which = "play" \| "snapshot" \| "source"`, `detail = false`, or `area` and `surface` instead of `name` | `digest`, `entities`, and with `detail` the per-entity records |

`slice_fingerprint` hashes the slice's entities in a fixed order, excluding port closers: name, position, direction, inventories, belt line items, crafting progress, inserter hand, and fluids rounded to 1e-6. `snapshot` is the record taken on the play surface right after `slice_build`, because a force change empties fluids and the snapshot surface's own fluids never match. Fidelity F3 compares `play` after `slice_reset` with `snapshot`.

- A port is `{position, kind = "belt" | "pipe" | "inserter" | "splitter" | "tank" | "power", role = "feed" | "drain", items | fluid, closer = <unit_number>}`, plus `how`, `tee`, `load`, `starved` and `scripted` that say how it is closed. An inserter or drill outside the rectangle that reaches into it is a port with `kind = "inserter"` and `how = "ext-inserter" | "ext-drill"`. An outside drill is replaced by an inserter fed from an infinity chest, so its rate is the inserter's, not the drill's. An unhandled port is `{position, name, reason}`.
- A `LuaProfiler` cannot be read as a number inside the game, so no reply carries timings. Call `slice_timing` after the verb, or use `fixtures.slice.timed(lab, verb, **args)`, which does both.
- `slice_inplace` cuts the rectangle out of its surroundings on the source surface: it removes each connection that crosses the edge, places the same closers as `slice_build` and an electric energy interface for power, and records every removed entity so `slice_drop` restores it.
- `slice_reset` on a standard-mode sandbox restores the snapshot without port closers and without the global electric network. `sbx_mode` to standard destroys that network too.
- A failed scheduled reset never raises from `on_tick`. It shows up as `last_error` in `slice_list`.
- A slice with unhandled ports stays playable. The bench refuses to rate it with `unhandled_ports`.

### God mode (`god.lua`, fxlab-god)

Each verb takes `name`, the sandbox.

| Verb | Args | Returns |
|---|---|---|
| `research` | `mode = "copy" \| "list" \| "levels" \| "all" \| "none"`, `techs`, `levels = {tech = N}`, `recipes` | changed techs. An in-place box refuses `all` and `none`, and its switch to standard replays each entry's `before` |
| `bonuses` | | every bonus field of the sandbox force (a read) |
| `items` | `at`, `items = {{name, count, quality}}`, `target = "chest" \| "infinity" \| "belt" \| "entity" \| "ground"`, `entity` | spawned unit numbers |
| `evo` | `set` | evolution factor of the sandbox surface |
| `nest` | `at`, `names`, `evo` | unit numbers |
| `wave` | `from`, `target`, `units = {name = count}`, `radius` | `group` |
| `wave_status` | `group` or `name` | alive, killed, state (a read) |
| `body` | `at`, `reach = 1000`, `invulnerable = true` | unit number |
| `body_tp` | `at`, `surface`, `unit` (default: the newest body) | `unit`, `old_unit`. A move to another surface clones the body, so its unit number changes |
| `sbx_mode` | `mode`, `research` | counts undone and skipped |
| `ledger` | | the entries (a read) |

**CAUTION** God powers come from script only. Never give the camera player `cheat_mode` or the editor, because that moves it out of its booth and changes the simulation.

### View (`view.lua`, fxlab-cam)

| Verb | Args | Returns |
|---|---|---|
| `view_booth` | `player` | parks the camera player on the `cam-booth` surface |
| `view_shot` | `surface`, `area` or `position` with `resolution`, `zoom`, `info`, `path` | `path` under `script-output`, `resolution`, `position` |

`fxlab-render` may append verbs such as `view_stamp` for blueprints.

### Camera (`camera.py`, fxlab-cam)

- `attach(lab)` and `detach(lab, missing_ok=False)`. `Lab.up(camera=True)` and `Lab.down` call them. The camera container is `<lab container>-cam` with labels `fxlab=1` and `fxlab.role=camera`. The lease does not count it.
- `render(lab, area=None, position=None, zoom=1, surface="nauvis", info=False, resolution=None) -> Path`: a PNG under the lab's `script-output`, returned once the file stops growing. `frame(area, zoom)` gives the position and pixel size `render` will use.
- `attach` writes `camera.marker` in the lab dir. `render` re-attaches a lost camera only when the marker names the running lab container, and otherwise raises, so a render never adds a camera to a run that had none.
- `desyncs(lab)` lists desync lines in the camera and server logs. A fidelity arm with a camera must check it, and must check that `fxcam` is still connected.
- **CAUTION** Files the game writes into `script-output` are owned by root on the host. Delete them with `docker exec <lab> rm`.
- The sprite atlas caches mount read-only into every camera, so cameras can run side by side.
- A fixture that needs the seeded save takes `source = "run4-closeout"`, takes that lab down, and brings it up again on `run4-closeout+cam`. It holds one lease slot at a time.
- `seed(save) -> str`: writes `<save>+cam` into `~/.cache/fxlab/_saves/`, with the camera player already in the save and parked in its booth. Start every arm of a fidelity comparison from the seeded save.
- CLI: `fxlab.sh seed-camera <save>` and `fxlab.sh shot <lab> ...`, registered through `camera.register(sub)`.

## Tools

A tool is one Lua file under `research/tools/<group>/<name>.lua`. The library is what agents call instead of writing one-off Lua. Groups are folders only: names are unique across the library.

### Header

The file starts with `--- key: value` lines. The first other line ends the header.

> `--- tool: look` (equals the file name)
> `--- kind: call` (`call` or `lib`)
> `--- effect: read` (`read`, `act` or `cheat`)
> `--- summary: one line, for tool_list`
> `--- args: x0, y0, x1, y1 (numbers); surface (default nauvis)`
> `--- returns: {entities = {{name, x, y}, ...}}`
> `--- uses: geom` (optional, the libs it calls)

- `read` changes nothing. `act` changes the world as a player could: ghosts, deconstruction orders, recipes, filters. `cheat` does anything a player cannot, such as `create_entity` of a built entity or inserting items from nothing. The realm refuses `cheat` tools for crew roles.
- A `call` tool is a function body. Its arguments arrive as `...` (`local args = ...`). It returns one table, never printed text.
- A `lib` tool returns a table of functions. Another tool gets it with `use("name")`. A peer caches a lib for one tick only, so every peer runs lib bodies at the same tick and no lib keeps state across ticks. **WARNING** A lib body must not change the game. It sees `storage` write-blocked. The guard stops accidents only: `remote.call` can still reach the game.
- In a tool, `_G` is the tool's own env and `getmetatable(_ENV)` is hidden, so no tool reaches the mod's real `storage`.
- A tool may not register event handlers.

### Game verbs (game-bot-control 0.6.1, rlm-factorio)

Called as `remote.call("game_bot", verb, args)`. They run the same in a lab and on the realm.

| Verb | Args | Returns |
|---|---|---|
| `tool_define` | `name`, `code`, `kind`, `effect`, `summary` | `name`, `size`. Raises on a bad name, a compile error or a lib that writes `storage` |
| `tool_call` | `name`, `args`, `deny` (a list of effects) | `{ok = true, r = <value>}` or `{ok = false, error = "no_tool" \| "tool_error" \| "denied", detail}` |
| `blueprint_stamp` | without `seat`: `surface`, `force = "player"` and the usual args | as with a seat |
| `tool_list` | | `tools`: name, kind, effect, summary, size, calls, errors, last_error, defined |
| `tool_drop` | `name` | |

Check the mod version with `script.active_mods["game-bot-control"]`. A mod without a data stage never appears in the server log's "Loading mod" lines.

- Tools live in `storage.tools`, apart from the stored scripts, so the script LRU never evicts them. The cap is 256 tools.
- A `call` tool sees the game's globals, `use`, its own persistent table as `storage` (`storage.tool_data[name]`) and the restricted `script` of stored scripts.
- `tool_call` counts calls and errors per tool. `deny` covers the tool, every lib it uses and every tool it calls through `remote.call`, for the whole call. A nested call can widen `deny` but never narrow it. A denied call counts as neither a call nor an error.
- From Python: `fxlab.tools.sync(lab)`, `fxlab.tools.call(lab, name, **args)`, `fxlab.tools.listing(lab)`. From the shell: `fxlab.sh tool-sync <lab>` and `fxlab.sh tool <lab> <name> key=value ...`.

### Realm verbs (rlm-factorio-lab)

- `session_id = "lab:<container>"` addresses a lab, for example `lab:fxlab-hub-trial`. The service refuses a container without the label `fxlab=1`. Seat verbs on a lab fail with "no seat in a lab".
- `tool{name, args}`, `tool_list{}` and `tool_sync{names}` need mod 0.6. `tool_sync` reads `RLM_FACTORIO_TOOLS`, by default `~/agentic_workspace/projects/game-bot/factorio/research/tools`, the checkout the deploy updates. An empty `tools` list arrives as a list.
- `sbx{verb, args}` forwards to the lab mod and works on lab targets only.
- Rules: the realm runs `realm` rules. A lab runs `sandbox` rules unless the call passes `rules = "realm"`. Under realm rules the service refuses `teleport`, `research`, `blueprint_stamp` with `build = true` or `build_mode = "built"`, every `sbx` verb outside a read allowlist (`sandbox_list`, `verbs`, `slice_list`, `slice_ports`, `slice_fingerprint`, `slice_area_of_base`, `slice_timing`, `bonuses`, `wave_status`, `ledger`, `view_shot`, `view_booth`, and `sbx_mode` with `mode = "standard"`), and every `cheat` tool, through `tool_call{deny = {"cheat"}}`. The refusal names the rule. Under realm rules the service refuses `tool` on a mod older than 0.6.1, because an older mod ignores `deny`.
- Lab targets refuse every verb that uses the realm supervisor or the session DAO: pause, world verbs, reset, release, join. Lab calls have their own throttle keys and never feed the realm's events.
- `tool_sync` defines libs in `uses:` order and refuses a non-cheat tool whose `uses:` chain reaches a cheat lib.
- The admin override is an `admin_token` argument that matches `RLM_FACTORIO_ADMIN_TOKEN_FILE`, by default `~/.config/rlm-factorio/admin-token`. It lifts every realm-rules refusal. A missing file means no override. It is for Tony. It guards against accidents, not against an agent that reads the file. Crew briefs never mention it.
- `exec_lua` stays allowed under realm rules. The service logs each call as one JSON line: time, session, seat, code size, code hash and the first 200 characters. The log is `RLM_FACTORIO_EXEC_LOG`, by default `~/.local/state/rlm-factorio/exec-lua.jsonl`. The toolsmith team mines this log.

## Fixtures

- Register a fixture in your own module under `fixtures/` with `@fixture(source, tags, live=False, camera=False)`. `source` is `"create"` or a realm save name such as `run4-closeout`. The function takes a started `Lab` and returns `Result(ok, detail, score, data)`.
- A module that fails to import shows up as the failing fixture `import_<module>`. Every other fixture still runs.
- Run fixtures with `python -m fxlab.ratchet --no-advance <names>` or `--tag <tag>`. Pass `--no-advance` in a peripheral scope. Only the hub advances `best.json`.
- Put noise in `data`, never in `score`. A noisy score makes the ratchet reject good runs.
- Tag slow fixtures `slow`. Tag tool fixtures `tools` and run them with `camera=True` once the camera exists, because the camera is a real peer and shows a desync.

## Shared formats

### Module corpus (`research/lab/fidelity/modules.json`, fxlab-fid)

A JSON list. Each entry: `id`, `save`, `area` as `[[x0, y0], [x1, y1]]`, `products` (the item names that count as output), `notes`. Every entry slices with no unhandled ports.

### Bench record (`bench.py`, fxlab-bench)

`bench()` returns, and the design library stores, one JSON object:

- `subject`: `{area, save}` or `{blueprint}`.
- `mode`: `god` or `standard`.
- `warmup_min`, `minutes`, `ticks`.
- `rates`: net items per minute. Positive is output and negative is input.
- `utilisation`: per recipe, 0 to 1.
- `ceiling`: per item, the recipe ceiling per minute.
- `starved`: the ports that ran empty.
- `unhandled`: always empty, because the bench refuses a slice with unhandled ports.
- `fidelity`: the corpus id and F1 result of the setup it ran on.
- `commit`, `stamp`.
