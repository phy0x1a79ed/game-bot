# automated-power — offshore pump → boiler → steam engine → poles

Recipe proven live on session `rlm-factorio-9c922f51ef6a`, world `railworld-218`,
building on `tech/manual-basics.md` and `tech/automated-smelting.md`. Builds a
full steam-power plant at the map's one lake, wires it into an electric
network, runs a pole line ~56 tiles to a chosen main-base point, and proves
real power consumption with a working `inserter`.

## 1. Site: the lake is the constraint, not the coal

`lib/find-resources.sh` found exactly one water body, `~(-47.5,2.5)`, `d=114.6`
from the coal patch `(59.5,-38.5)` — an exec-lua sweep (radius 350 around
coal) confirmed no closer lake exists. But the lake is only **~56 tiles from
the iron cluster** `(-7,-35)` (automated-smelting furnaces), so: **build the
plant at the shoreline, carry coal in** (same pattern as furnace fueling),
run the pole line toward the iron cluster instead of piping water 114 tiles.

Shoreline scan (`get_tile` grid dump) found a straight N–S shoreline at
`x=-48/-47`, water west, land east; used `y=8` as the build row. Wood (for
poles) is scarce — trees are sparse "dead-*" desert decorations, 2 wood each
on `body-mine`; nearest usable cluster was 5 trees near `(-60,-100)`, worth
one detour (12 wood from 6 trees, enough for 6-8 poles).

## 2. Fluid-connection geometry — the actual finding

`entity.fluidbox` and `entity.neighbours` both **error** in this realm's
exec-lua RCON context (sandbox restriction, not a bug). Verify fluid state
with `entity.get_fluid_contents()` and network wiring with
`entity.electric_network_id` (same id across pump→boiler→engine→every pole
confirms one network). Derive placement geometry from **prototype** data
instead: `prototypes.entity[name].fluidbox_prototypes[i].pipe_connections[j]`
gives a `direction` (outward-facing when unrotated/north) and `positions[1..4]`
(offset from center for direction=north/east/south/west respectively — same
4-way order as the drill `drop_position` table). The connecting neighbor tile
= `position + unit_vector(direction rotated 90°×variant_index)` — one full
tile beyond the printed position, which sits *inside* the entity's own box.

**Surprising part**: a `boiler`'s two water inputs are on its **left/right
sides** when unrotated (north), not the back: `(-1.0,+0.5)` west,
`(+1.0,+0.5)` east. Output (steam) is front-center `(0,-0.5)`, north.
Leaving the boiler at default north direction and stacking the plant
vertically (pump west→boiler, boiler north→engine) needs exactly **2 bridge
pipes total**. Steam-engine has one fluidbox with two connections, at both
long-axis ends (`(0,±2.0)`) — either end accepts steam. Offshore pump's
single connection position is always `(0,0)` (= its own placed position);
only its `direction` rotates.

## 3. Built layout (all positions as placed/snapped, read back — never trust the request)

| entity | pos | dir | note |
|---|---|---|---|
| offshore-pump | (-46.5, 8.5) | west | intake into lake at x≤-48 |
| pipe | (-45.5, 8.5) | — | pump-output ↔ boiler west-input bridge |
| boiler | (-43.5, 8) | north (default) | |
| pipe | (-43.5, 6.5) | — | boiler north-output ↔ engine south-end bridge |
| steam-engine | (-43.5, 3.5) | north (default) | |
| small-electric-pole | (-41.5, 4.5) | — | joins engine to network id 1 |
| iron-chest (coal stock) | (-43.5, 10.5) | — | refill here, not the boiler by hand |
| burner-inserter | (-43.5, 9.5) | **south** | pickup=chest(south), drop=boiler(north) |
| 2×iron-chest + inserter | (-40.5,4.5) / (-39.5,4.5 dir west) / (-38.5,4.5) | — | proof-of-load consumer |
| pole line | (-36.5,-0.5),(-31.5,-5.5),(-26.5,-10.5),(-21.5,-15.5),(-16.5,-20.5),(-11.5,-25.5),(-6.5,-29.5) | — | ~7.07-tile spacing, all network_id=1 |

**Main-base point: `(-6.5,-29.5)`**, network-connected, ~5 tiles north of the
iron furnace cluster. Continuous power draws (labs/assemblers) benefit more
from proximity to generation than to smelting — plates are already
hand-carried across the map as inventory, same as coal.

Recipe chain (all pre-unlocked, no `research` used):
```
pipe=1 iron-plate   offshore-pump=2 gear+3 pipe   boiler=4 pipe+1 stone-furnace
steam-engine=10 iron-plate+8 gear+5 pipe   copper-cable=1 copper-plate→2
small-electric-pole=1 wood+2 cable→2 poles   electronic-circuit=1 iron-plate+3 cable
inserter=1 iron-plate+1 gear+1 circuit   burner-inserter=1 iron-plate+1 gear
```
Craft order matters (cable→circuit→inserter); `body-craft` queues fine while
`body-move` is in flight.

## 4. Verified live (`lib/power-status.sh`)

```
pump    status=1(working)  fluid=water:100
boiler  status=1(working)  fuel=5  fluid=water:200,steam:200
engine  status=1(working)  energy_last_tick=76.7  network=1  fluid=steam:200
inserter status=1(working) energy=268
pole × 8, all network=1
```
`energy_generated_last_tick`: **0** with no consumer, **6.7** idle baseline
once plugged into a network, **76.7** while the proof-inserter actively
moved plates — the engine tracks real demand, not a scripted value.
`defines.entity_status` codes used: 1=working, 5=not_plugged_in_electric_
network, 26=no_input_fluid, 34=waiting_for_source_items,
36=waiting_for_space_in_destination, 57=no_fuel, 29=full_output (look up via
`defines.entity_status` reverse-map — the numeric code alone isn't obvious).

## 5. Fuel upkeep — chest + burner-inserter, mostly self-running

Chest `(-43.5,10.5)` stocked with coal → burner-inserter `(-43.5,9.5)` feeds
the boiler. **Direction is the pickup side, not facing/output** —
`--direction south` gave pickup=south(chest)/drop=north(boiler); `north`
(first guess) was backwards. Verify with the entity's own
`pickup_position`/`drop_position` (exec-lua), don't guess — true for the
plain `inserter` too (hit the identical backwards guess on the proof
consumer). **Boiler's fuel slot caps around 5 coal** — burner-inserter tops
it off then sits `waiting_for_space_in_destination` until it burns down, a
clean self-throttling loop closing automated-smelting's "not self-fueling"
gap. Burner-inserter needs its **own** fuel too (separate pool) — gave it 10
coal once; at light load it hadn't touched the boiler/chest again after
~15s. Coal chest: 40→39 over the whole session's demo load — **upkeep here
tracks consumer load, not boiler idle burn.** Refill from the existing coal
stockpile `(61.5,-44.5)`, ~114 tiles away (180 coal banked at session end).

## 6. Proof-of-load consumer

A real (non-burner) `inserter` draws electricity, unlike `burner-inserter`;
moved `iron-plate` between two chests (§3 row 9) to prove real consumption.
Chosen because it's already unlocked (`recipes --search inserter` shows it
`enabled`) — `electric-mining-drill` needs `automation-science-pack`
(unresearched, and `research` is off-limits per the rules).

## 7. Gotchas

- **Your own body blocks builds** — `body-build` within ~1 tile of the
  body's stand point fails `"collision or invalid"` silently; move away
  first (confirmed via `can_place_entity` + a `find_entities_filtered` scan
  showing the `character` entity itself in range).
- **Long `body-move` (~100+ tiles) sometimes returns `path_blocked{no_path}`**
  on the first try to plainly-open land; retrying with the target nudged
  ~1 tile succeeded both times seen. Cheap to retry, cause unclear.
- **Fluidbox/neighbours introspection is blocked** — use
  `get_fluid_contents()`, `.status`, `.electric_network_id`,
  `.bounding_box`/`.position`/`.direction`, and prototype
  `fluidbox_prototypes` dumps instead (§2) — reuse §2/§3, don't re-derive.
- Small entities (pipe/pole/chest) snap to half-integer centers; boiler/
  steam-engine snap to whatever aligns their long axis — always read back
  `built.position`, never trust the request, for downstream placement.

## Realm gaps

None new. The `no_path` blips and blocked `fluidbox`/`neighbours` keys are
workarounds (§7, §2), not realm bugs.

## Final state (this session)

Full chain running unattended: pump→boiler→engine→8-pole line→main-base
`(-6.5,-29.5)`, network id 1 throughout, proof-inserter showed real load
response (0→6.7→76.7 energy/tick). Iron furnace cluster harvested (+200
iron-plate) in passing; iron drills left low on fuel (4/1, no coal on hand
at session end). Copper site and coal-drill→chest site not revisited
(78+/120+ tiles away) — refuel next visit from `(61.5,-44.5)` (180 coal
banked). World saved as `basic-automated-power`.
