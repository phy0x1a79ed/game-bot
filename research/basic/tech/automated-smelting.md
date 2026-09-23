# automated-smelting — burner drills feeding furnaces, fuel upkeep

Recipe proven live on session `rlm-factorio-9c922f51ef6a`, world `railworld-218`,
building on `tech/manual-basics.md` (walking, hand-mine/craft, hand-smelt).
Builds and runs 3 drill→furnace pairs (2 iron, 1 copper) plus a coal
drill→chest demo, all self-running once fueled.

## 1. Recipe chain

```
iron-gear-wheel     = 2 iron-plate                                    (0.5s)
stone-furnace       = 5 stone                                         (0.5s)
burner-mining-drill = 3 iron-plate + 3 iron-gear-wheel + 1 stone-furnace (~2s)
iron-chest          = 8 iron-plate
```
**1 drill = 9 iron-plate + 5 stone** (the furnace ingredient is consumed,
not placed). Each drill+furnace *pair* you place costs 2 furnaces worth of
stone (10 total) — one eaten by the drill recipe, one placed as the smelter.

## 2. Placement geometry (the actual finding)

`burner-mining-drill` and `stone-furnace` both have `collision_box`
(-0.7,-0.7)-(0.7,0.7) → 1.4×1.4, **snap to a 2×2-tile footprint centered on
integer coords** (request (61.5,-38.5), get (62,-38), same as manual-basics'
furnace snap). `iron-chest` is 1×1 and snaps to **half-integer** centers
instead — mixing the two trips you up (see gotchas).

`body-build --name burner-mining-drill --x X --y Y --direction
north|east|south|west` places facing that direction (defaults north).
Read the live entity's `drop_position` (exec-lua, read-only) to see exactly
where mined output lands, relative to the drill's own snapped center:

| direction | drop offset (dx,dy) from drill center |
|---|---|
| north (dir=0)  | (-0.35, -1.30) — measured |
| east  (dir=4)  | (+1.30, -0.35) — measured |
| south (dir=8)  | (+0.35, +1.30) — derived by rotation, confirmed live |
| west  (dir=12) | (-1.30, +0.35) — derived by rotation, not separately tested |

Each is the previous rotated 90°: `(dx,dy) → (-dy,dx)` going N→E→S→W. The
practical rule: **place the receiving furnace/chest with its center exactly
2 tiles from the drill's center, in the drill's facing direction** (2×2
footprints touching edge-to-edge). The drop point (~1.3-1.5 tiles out,
~0.35 tile off-center) always lands inside that neighbor's footprint.

Confirmed live at (-6,-36)→east→furnace(-4,-36) and (-8,-34)→south→
furnace(-8,-32): furnace `ore_in` stayed ~0 (consumed as fast as delivered),
`plate_out` climbed with zero manual ore `body-insert`.

`body-insert --name coal` still auto-routes to fuel vs. input slot, same as
manual-basics documented for hand-fed furnaces.

## 3. The built line (layout, this session)

| entity | pos | dir | feeds |
|---|---|---|---|
| burner-mining-drill | (-6,-36) | east | furnace (-4,-36) — iron |
| burner-mining-drill | (-8,-34) | south | furnace (-8,-32) — iron |
| burner-mining-drill | (8,43) | east | furnace (10,43) — copper |
| burner-mining-drill | (62,-43) | north | iron-chest (61.5,-44.5) — coal |

Iron pairs sit inside the iron patch near (-7,-35); copper pair inside the
copper patch near (8,43); coal-drill→chest sits in the coal/stone patch near
(61-62,-43), ~65-95 tiles from the iron/copper sites — **too far to wire
directly**, so coal is hand-carried (§5). This demo proves the drill→chest
pattern (brief item 1) and gives a standing coal stockpile instead of
hand-mining coal on every trip.

**Searched for closer iron/coal overlap** (exec-lua, read-only, radius-400
`find_entities_filtered` from each patch anchor toward the others): none
found — the coal patch's nearest edge to iron is the same ~60-tile gap from
anywhere in either patch (both are single contiguous blobs thousands of
tiles deep, not scattered outcrops); copper is ~75-95 tiles from both.
Carrying fuel is the only real option here — also the option the brief allows.

## 4. Collection, fuel checks, throughput

- `body-take --x X --y Y --name iron-plate|copper-plate` pulls furnace
  output exactly like manual-basics' hand-smelt step. Collected **109
  iron-plate** (62+47, two furnaces) and **16 copper-plate** this way.
- `lib/smelting-status.sh` (new): read-only exec-lua scan of every
  `mining-drill`/`furnace`/`iron-chest` on the surface — position, `status`
  (`working=1`, `no_ingredients=18` = furnace ran dry between drops, normal
  and self-clearing, `no_fuel=57` = needs coal), fuel, ore-in, plate-out.
  Callable from anywhere (inspection, no reach check).
- `lib/harvest-plates.sh` (new): best-effort `body-take` at all 3 known
  furnace coords; only site(s) in reach of the current position succeed,
  others print their reach error and it continues.
- **Throughput measured** (copper pair, 2 samples 17.9s apart): 5 plates =
  **~16.8 plates/min** per pair — near stone-furnace's vanilla max
  (3.2s/plate = 18.75/min): one burner drill easily saturates one furnace,
  furnace smelt time is the bottleneck, not drill mining speed. Iron pair:
  109 plates across 2 furnaces over a ~5 min unattended stretch, same order.
- **Fuel burn measured**: drill fuel 20→16 coal in 99s (~1 coal/25s while
  mining); furnace fuel drains in bursts (one coal charge lasts several
  smelt cycles). 20 coal in drill + 20 in furnace ⇒ several minutes
  unattended. Rule of thumb: **~20-30 coal per slot per visit**, refuel on
  each supply run rather than pre-loading for long autonomy.

## 5. Upkeep routine (per visit)

1. `./lib/smelting-status.sh` — check for `no_fuel` or stalled `plate_out`.
2. Walk to the coal chest (61.5,-44.5), `body-take --name coal` to restock
   (or hand-mine more — coal patch is right there).
3. At each site: `body-insert --name coal --count 15-20` into the drill
   *and* the furnace separately (different entities, different fuel pools),
   `body-take --name iron-plate/copper-plate` before the furnace caps out.

## 6. Gotchas

- **Direction is a string**: `--direction north|northeast|east|southeast|
  south|southwest|west|northwest`; bad name errors `"bad direction: ..."`.
  Maps to 16-way `defines.direction` evens (north=0, east=4, south=8, west=12).
- **1×1 vs 2×2 snap mismatch bit us directly**: guessed chest position
  (62,-45) (reusing the 2×2 "+2 tiles" rule) snapped to (62.5,-44.5), 0.5
  tile off the drop point — chest stayed empty. Fix: rebuild at (61.5,-44.5),
  the tile cell actually containing the measured `drop_position`. For a 1×1
  receiver, verify the drop point's containing cell directly.
- **Footprint overlap** errors `"cannot place X ... collision or invalid"`
  with no further detail — hit placing a second iron drill's furnace 1 tile
  from the first drill's footprint. Fix: space clusters ≥3 tiles apart, or
  pre-check with a read-only `surface.can_place_entity{...}` exec-lua probe
  before spending the item on a `body-build` that might fail.
- **Coal-drill→chest is not self-fueling.** Nothing routes chest coal back
  into the drill's own burner slot — after its initial 20-coal charge burned
  out it sat at `no_fuel` until manually refueled, having produced only ~32
  coal in the gap. Closing that loop needs an inserter (not touched here).
  Treat it as a stockpile you refuel and draw from by hand, not perpetual motion.
- `body-craft` queues sequentially on one crafting queue — furnaces, then
  gears, then drills finish in submission order (~0.5s/furnace, ~0.5s/gear,
  ~2s/drill); sleep the sum or poll `observe`'s `crafting` list before reading.

## Realm gaps

None new — `body-build`, `body-insert`, `body-take`, `body-mine`,
`body-craft`, `exec-lua` (read-only) all behaved as manual-basics
documented. `exec-lua` reading `LuaEntityPrototype` fields is inconsistent
(`mining_speed` exists, `mining_drop_position`/`resource_searching_radius`
don't) — use the **live entity's** `drop_position` instead, always present,
reflects actual placed direction.

## Final state (this session)

3 drill→furnace pairs running unattended, plus 1 coal-drill→chest.
`lib/smelting-status.sh` at session end: all pairs `working` or
`no_ingredients` (both healthy), fuel 20-36 per slot. Body inventory: 115
iron-plate, 46 copper-plate, 35 stone, 30 iron-ore, 10 copper-ore, 0 coal
(spent on refuels — restock from the coal chest first on next visit). World
saved as `basic-automated-smelting`.
