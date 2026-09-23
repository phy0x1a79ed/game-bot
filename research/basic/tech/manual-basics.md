# manual-basics — find ore, walk, hand-mine, hand-craft, hand-smelt

Recipe proven live on session `rlm-factorio-9c922f51ef6a`, world `railworld-218`,
body spawned at (0,0). Confirms the primitive loop the rest of the tech ladder
builds on: locate resources beyond `observe`'s cap, walk there, hand-mine bulk
ore in one call, hand-craft a furnace, place it, fuel + feed it, collect plates.

## 1. Finding patches — `observe`'s cap bites fast, use exec-lua instead

`./rlm.sh observe --radius 40` returns a `nearby` list capped at 50 entities
(`NEARBY_CAP` in control.lua) and **does not sort by distance** — it's
iteration order over `find_entities_filtered`. A single big ore field (this
map has iron/copper/coal/stone patches thousands of tiles deep) fills the cap
with one resource type before the scan ever reaches the others. At radius 40
from spawn (0,0) the entire 50-slot list was iron-ore.

Use `lib/find-resources.sh [radius]` instead (default radius 200): a
read-only `exec-lua` query that finds the nearest tile of each of
iron-ore/copper-ore/coal/stone (+ nearest water tile) independently, with
total patch size. Output for this world from spawn:

```
iron-ore:   nearest(-3.5,-31.5) d=31.7  amount=155   tiles=2154 total=22,386,022
copper-ore: nearest(6.5,42.5)   d=43.0  amount=1077  tiles=1046 total=8,982,627
coal:       nearest(59.5,-38.5) d=70.9  amount=3148  tiles=856  total=6,987,500
stone:      nearest(47.5,-17.5) d=50.6  amount=389   tiles=375  total=2,297,194
water:      nearest(-47.5,2.5)  d=47.6  tiles=2295
```

Gotcha: `storage.bot` (the mod's saved state) is **not visible** from
`exec-lua` — RCON `/silent-command` runs in its own script context with its
own `storage`, separate from the `game-bot-control` mod's. Find the body via
`game.surfaces["nauvis"].find_entities_filtered{type="character"}[1]`
instead of trying to reach into `storage.bot.body`.

## 2. Walking — async, poll for `arrived`

`./rlm.sh body-move --x X --y Y` returns immediately (`{ok, target,
pathfinding:true}`); the body paths there over subsequent ticks. Poll with
`./lib/wait-arrive.sh [timeout_s] [poll_s]` (default 60/2), which drains
`observe-events` until an `arrived` or `path_blocked` event appears (exit 0 /
2 / 1=timeout). Measured: ~9 tiles/sec effective walking speed once en route
(matches the code comment's ~0.15 tiles/tick); a 31-tile walk arrived inside
one poll interval, a 71-tile walk took ~4 polls. `arrived` position is only
accurate to `ARRIVE_DIST` (0.2 tiles) or `WP_ARRIVE`/stuck fallback (up to
1.5 tiles on a wedge), so don't assume exact coordinates after arrival.

## 3. Hand-mining — scripted, instant, bulk in one call

`./rlm.sh body-mine --x X --y Y --count N` mines an ore tile within reach
(10.5 with the +0.5 fudge in `check_reach`). **Mining is not animated or
timed** — it's a scripted insert+decrement (see control.lua `mine`), so one
call with `count=80` yields 80 ore immediately, no need to call it once per
unit or to hop between adjacent tiles. `--name` is optional (nearest minable
non-character entity within 1.5 tiles of x,y wins); omit it unless multiple
resource types overlap at that point. `remaining` in the response is the
patch's leftover amount, not your inventory.

Observed: `body-mine --x -3.5 --y -31.5 --count 80` → `{mined:{iron-ore:80},
remaining:75}` from a tile that started at amount 155.

Gotcha: mining more than the inventory can hold does NOT destroy ore — the
lua only consumes what actually fit (see the `insert`-then-consume-only-fit
logic), but it still errors `"inventory full"` if literally nothing fit.

## 4. Hand-crafting — real crafting-queue, ~0.5s/unit for stone-furnace

`./rlm.sh body-craft --recipe stone-furnace --count 2` queues on the engine's
real crafting queue (`begin_crafting`) — ingredients are consumed up front,
items land in inventory as each unit completes. `recipes --search X` lists
ingredients (stone-furnace: 5 stone → 1 furnace). Poll `observe`'s
`crafting: [{recipe,count}]` list (empty once done) or just check inventory.
Measured: 2 furnaces from `count=2` — 1 already in inventory ~1.6s after
issuing the call, both done by ~2.7s (i.e. ~0.5s/unit — matches vanilla craft
time, unaffected by anything scripted). **`iron-plate`/`copper-plate` are
NOT hand-craftable** — force.recipes lists them (category "smelting"), but
`begin_crafting` on a bare character only works for the ordinary
"crafting"-category chain; plates must go through a furnace (step 5).

## 5. Placing, fueling, and running a furnace

`body-build --name stone-furnace --x X --y Y [--direction north|...]` places
from inventory. **Gotcha: placement snaps to the entity's collision grid** —
requested (61.5,-38.5) landed at (62,-38); requested (63.5,-38.5) landed at
(64,-38). Don't assume the built entity sits exactly at your requested (x,y);
read `built`/`position` from the response (or `observe`) for the real anchor
and use that for `insert`/`take`.

`body-insert --x X --y Y --name coal --count 15` and `... --name iron-ore
--count 50` route automatically to the right slot (fuel vs. smelt input) —
no need for a `--target` filter unless two entity types are adjacent.
`body-take --x X --y Y --name iron-plate` (default count = all available)
pulls plates back out.

Smelting is real-time, not scripted: stone furnace = 1 ore → 1 plate, ~3.2s
each (vanilla rate, confirmed via exec-lua polling `crafting_progress` /
`get_output_inventory()` on the furnace entities — read-only inspection, not
used to cheat). 50 iron ore + 15 coal in one furnace and 30 copper ore + 15
coal in a second, built 2 tiles apart, ran in parallel with no interference.

## Proven end state (this session)

Two `stone-furnace` built at (62,-38) [iron] and (64,-38) [copper] (2 tiles
apart, ran in parallel with no interference), fed from ore/fuel gathered
along route spawn(0,0)→copper(6.5,42.5)→iron(-3.5,-31.5)→stone(47.5,-17.5)→
coal(59.5,-38.5), ~195 tiles total, ~4 body-move legs. Fed 50 iron-ore + 15
coal into furnace 1, 30 copper-ore + 15 coal into furnace 2; both smelted to
completion (iron capped by ore fed, copper likewise) and `body-take` pulled
the plates (+ leftover coal) back into the body inventory. Final inventory
(body stayed at ~(59.4,-38.4) the whole smelt+take sequence, everything
within reach 10.5 of both furnaces):

```
iron-plate:  50
copper-plate: 30
coal:        12   (spare, pulled back from both furnaces' fuel slots)
stone:       10   (spare, left over after 2x stone-furnace @ 5 each)
iron-ore:    30   (spare, unsmelted)
copper-ore:  10   (spare, unsmelted)
```

Meets the ≥50 iron plate / ≥20 copper plate / spare coal+stone target.

## Realm gaps / error messages observed

- `body-mine` out of reach: `"out of reach: (200.0,200.0) is 276.8 tiles away (reach 10.5) -- move closer"`.
- `body-craft` unknown recipe: `"unknown recipe: totally-not-a-recipe"`.
- `body-build` without the item in inventory: `"no stone-furnace in inventory"` (checked before the collision check, so a collision-only probe needs the item on hand first).
- `body-insert` out of reach: same reach message as mine (`check_reach` is shared).
- No gaps found in the verbs needed for this tech — `observe`'s uncapped/unsorted `nearby` list is a real limitation for resource-finding at scale, worked around with `lib/find-resources.sh`, not a bug to fix here.
