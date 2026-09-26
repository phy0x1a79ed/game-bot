# diary — playing Factorio through the realm

## Purpose & Contents

This is the only doc for playing Factorio. It holds two things:

- **How we play** — the standing method: watching the game, the tool, the crew
  rules and the speed rules. Edit it in place when the method changes.
- **Entries** — dated findings, newest first: measurements, geometry, failure
  modes, designs and plans. Each finding lives in exactly one entry. Correct a
  wrong finding in place and date the correction. Delete a finding that no
  longer holds.

A finding belongs here when the realm's `describe` output and the Factorio wiki
would not tell a player. The realm itself is the **rlm-factorio** awm service
(`awm/services/rlm-factorio`, MCP domain `rlm`). The awm project owns it. Never
modify it from here. Scripts live beside this file: `rlm.sh` and `lib/`.

## How we play

### Watch the game

- Connect a Factorio client to `localhost:12140` through *Multiplayer →
  Connect to address*. From another LAN machine, use the Windows host's LAN IP
  with UDP allowed. The LAN-games browser never lists this world.
- Match the realm's pinned Factorio version exactly (2.1.20 as of 2026-09-23).
  Set it under Steam → Factorio → Properties → Betas. Own Space Age.
- Copy `game-bot-control_<ver>.zip` from the realm's `appliance/dist/` into
  `%APPDATA%\Factorio\mods`. Enable it. Restart the client.
- **CAUTION** Edit `mod-list.json` only while Factorio is closed. The game
  rewrites that file on exit and reverts the change.

### Drive a seat

1. Acquire the session with `rlm(verb="factorio_acquire", args={game:"factorio"})`.
2. Join a seat with `factorio_join`. A seat is a real multiplayer player.
3. Pass the seat id explicitly on every call. In a crew, never rely on
   `research/.seat`: agents share that file, and one agent's write silently
   sends another agent's calls to the wrong seat.
4. Run `./rlm.sh <verb> [--flag value ...]`, or call the MCP tool with
   `verb="factorio_<verb>"` and `args={seat_id: ...}`. Call
   `rlm(verb="describe")` for the live verb list.

### Crew

A supervisor holds the objectives and watches from its own seat. It owns the
world's lifecycle, the session event inbox and this diary. It saves the world
under a named milestone (`run2-green-science`) the moment a milestone lands, so
a collapse reloads to the last milestone instead of the start. Each builder holds
one seat and one lane, and works through a standing queue of objectives
without returning between items. Builders coordinate through an append-only
board file named in their prompt. A builder posts a durable finding on the
board. The supervisor folds it in here the moment it lands.

A researcher holds its own seat and builds nothing in the base. It audits every
machine, measures bottlenecks, maps pollution against turret cover, tests one
improvement per cycle at an isolated test site, and returns a ranked list of
proposals. It works in cycles of about 100 tool calls. The supervisor turns
accepted proposals into builder orders.

Agents relay instead of compacting. A subagent cannot compact itself, and the
`reflection` tool resolves to the supervisor's session. At every task seam,
and past about 200k tokens of context, an agent writes its lane's handoff file,
posts a SEAM line on the board and stops. The supervisor then starts a fresh
agent on the same seat from that handoff.

Builder rules:

- Never cheat. Never call `teleport`, `research`, or `blueprint_stamp` with
  `build=true`. Never run `exec_lua` that creates items or entities, moves a
  character or edits an inventory.
- Use `exec_lua` to read state, and for player-interface actions: the research
  queue, `set_recipe` on your own assembler, rotating your own entity.
- Never call `world_new`, `world_load`, `world_save`, `reset`, `release`,
  `leave`, `pause` or `observe_events`.
- Never dismantle another lane's module or take its fuel. Take plates from any
  furnace's result slot. Furnace output is shared.
- Leave at least 20 coal in every coal ring chest. Never walk into a ring's
  centre.
- Put surplus for other lanes in the shared depot chest at (0.5,-19.5).
- A service pass that loads coal once runs dry before its last stop. The iron
  column alone took 240 coal a pass, so the copper modules after it starved.
  Refill coal before each section of a route.
- Give every fuelled machine an owner lane. The boiler belonged to no lane and
  ran dry at tick 640000 with its feed chest empty. The supervisor assigns each
  new machine to a lane's service script when it is built.
- Defend before you pollute. Research `gun-turret` right after the first lab.
  Place 2 gun turrets with 20 magazines at every polluting site before the
  base passes about 10 burner drills. See the 2026-09-26 enemies finding.
- Read enemy positions before every move: one `exec_lua` query for
  `force="enemy", type="unit"` within 40 tiles of the destination. Never walk
  toward a group, and never walk back to a corpse in enemy range.

### Work fast

Never spend one tool call per game action. Write a script that operates the
game and run it in one Bash call. A realm call costs about 0.4 seconds at the
gateway. The `awm` CLI adds 0.55 seconds of startup to every call. Six calls in
parallel took 2.7 seconds against 6.6 in series.

1. Call the realm from scripts with `lib/act.sh VERB SEAT key=value ...`. It
   posts to the gateway's `/invoke` and skips the CLI startup. Keep each routine
   in `lib/`. Run `ls lib` before writing a new one.
2. Batch every action at one stop into one `exec_lua` call. Each verb is a
   function of the mod's `game_bot` remote interface, so
   `remote.call('game_bot', 'insert', {seat=seat, x=..., y=..., name=..., count=...})`
   runs the same reach and legality checks as the verb. A script of such calls
   runs in one tick for one round trip. Wrap each call in `pcall` so one
   failure does not abort the rest.
   **CAUTION** Everything in one `exec_lua` runs within a single tick. It cannot
   wait for a walk, a mining order or a craft to finish. Walk between stops
   from the outer script. Reach is 10.5 tiles, so one stop covers several
   modules.
3. Walk with `lib/walk.sh SEAT X Y [TOL]`. It blocks until arrival and retries
   a blocked path.
4. Read many entities with one `exec_lua` query. `lib/status.lua` summarises
   the whole base.
5. Issue independent calls in parallel: several tool calls in one turn, or `&`
   and `wait` in Bash.

## Entries

### 2026-09-26 — a crew of three builders under a supervisor

World seed 1234567, save lineage `red-ladder-coal-ring`. Started at tick 396724
with only `steam-power` researched. Builder lanes: iron, copper and stone,
power and science.

**Run 2 against run 1.** Run 1 ended in a biter collapse at tick 560000. Run 2
reloaded tick 415000 and played defense-first with scripted actions.

| Milestone | Run 1 tick | Run 2 tick |
|---|---|---|
| `electronics` | ~435000 | ~435000 |
| `automation` | ~489000 | ~485000 |
| `gun-turret` | ~555000 | ~484000 |
| Every polluter under turret cover | never | ~572000 |
| Red science automated, labs unattended | never | ~585000 |
| `logistic-science-pack` researched | never | ~640000 |
| Green packs made unattended, not yet belted to the labs | never | ~792000 |
| Iron column on 7 electric drills, no drill fuel | never | ~811000 |

Since tick 641000 a belt carries iron from the 5 self-fed iron rows to the gear
assembler. Copper still arrives by hand, through `lib/service-copper.sh`.

**Strategy from tick 725000.** The supervisor set these after the user's review.

- Recurring upkeep has one owner. Refuelling, hauling, ammo and repair ate
  every builder's time. One upkeep lane now runs every service script in one
  loop and reacts to `lib/alerts.sh`. Builders only build.
- Automation removes upkeep. The target is zero hand-fed machines: electric
  drills on ore, a coal belt to the boilers and the furnaces, and belts or
  inserters on every output.
- Plates travel on a main bus. Smelting stays at each ore field. Plate belts
  run to one bus corridor beside the power block. The mall, the science lines
  and the intermediate blocks tap the bus. A bus concentrates the defense
  perimeter and makes a starved lane visible. Its cost is one shared
  bottleneck per lane, fixed by adding a lane.
- The bus corridor runs north-south along the iron belt, x=-19.5, from the iron
  field (y=-63) to the mall and green blocks (y=0..15). Lanes, west to east:
  iron A (the existing belt), iron B (x=-18.5, feeds the mall row's iron
  chests), copper (x=-16.5, from the copper field), gears (x=-15.5), circuits
  (x=-13.5). Poles and walking gaps sit at x=-17.5 and x=-14.5. x=-11.5 and
  -10.5 stay free for widening. The coal belt runs east-west along y=-27 and
  crosses the bus once, underground. The only water within 300 tiles is the
  lake at (-104..-48, -31..34), so power grows along its shore.
- Intermediates are central. One gear block and one circuit block feed the
  bus. Consumers never make their own gears or circuits.
- A mall on the bus makes the building materials: belts, inserters, poles,
  assemblers, drills, furnaces, magazines, walls and repair packs. Seats pick
  up from the mall instead of hand-crafting.
- Coal reaches the boiler by belt from burner feeder chains at the coal patch.
  Each chain's last drill drops onto one belt. One electric inserter at the
  powered boiler end lifts coal into the boiler. The patch end needs no power.
  A boiler at full load (1.8 MW for 2 engines) burns 27 coal/min, so 2 chains
  cover it. A power plant at the patch saves nothing: the nearest water lies
  127 tiles away, as far as the existing boiler.
- Green science unlocks `electric-energy-distribution-1`. Medium poles end the
  wood shortage that blocks every power extension.
- Research keeps every red-only tech queued ahead of green techs. Red packs
  idle while a queue waits on green.

**Crew**

- A builder that issued one tool call per game action spent 170 to 190 calls
  and 12 to 20 minutes on its first objective. The first batched script
  refuelled and swept all 8 iron modules in one call.
- A builder that returned after each objective sat idle until the supervisor
  answered. Standing queues fixed it.
- A builder waiting for another lane's copper sat blocked while 128 plates sat
  in that lane's furnaces. Sharing furnace output fixed it.
- Seats in one force share research and recipes.

**Seats**

- A newly joined seat spawns with the freeplay kit: 1 burner mining drill, 1
  stone furnace, 1 wood, 8 iron plate. Each new seat is one free ore module.
- A disconnected seat's player has no character. Nothing a seat carried
  survives into a later session.

**Enemies — the run ended in a biter collapse**

- This world has biters and enemy expansion enabled. It is not a peaceful map.
  Nests sit about 220 to 250 tiles out: north near (42,-248) and (-17,-237),
  south-west near (-190,130). Evolution was 0.04.
- The base grew to 22 burner drills and 11 furnaces in 35 minutes of play.
  Its pollution reached the nests. The first attack group arrived at tick
  about 538000, 40 minutes after the session started.
- The attack groups destroyed coal ring 1, half of ring 2 and 3 iron modules.
  Within 6 minutes they camped spawn. Every seat died, several of them 3 times.
  A respawned seat died again within seconds.
- A seat that dies drops its whole inventory in a corpse at the death spot.
  Walking back to the corpse killed a builder twice more.
- A seat carries a pistol, and crafted magazines load into its ammo slot. No
  verb aims or fires, so a seat cannot fight. Gun turrets are the only defense.
- `insert` reads only the main inventory. A crafted magazine lands in the gun's
  ammo slot first, which holds 100. Craft past 100 so the rest lands in the main
  inventory, where `insert` can load it into a turret.
- A gun turret without ammo does nothing. Load 20 magazines as it is placed.
- Run 2 at tick 650000: pollution peaked about 50 at the iron column and fell
  to 19 to 25 at 130 tiles, well short of the nests. 76 enemy units sat within
  300 tiles, none in a unit group. Two more nest clusters lie west at
  (-255,11) and far south-west at (-297,-50).

**Other surveys from this run**

- A second coal patch lies at (204,-67), 902k coal, clear of enemies. A larger
  one lies at (360,-147), 3.6M.
- Real trees grow at (-157,-315) and (-181,-255), 4 wood each. The desert trees
  near the base yield 1 to 2.
- The copper field's rich core lies at x=12..24, y=54..66, about 1500 ore per
  tile. Its edges hold 300 to 700. The first copper module sat on the edge at
  (20,50) and ran dry by tick 596000. No coal lies within the field, so every
  burner module there runs on hauled coal. Survey 6x6 cells for average ore per
  tile before placing a drill.

**Research**

- Producing copper plates fired `electronics` within minutes.
- Building a lab fired `automation-science-pack`.
- Set an ordered queue with `player.force.research_queue = {"a", "b", ...}`.
  The engine moves to the next entry by itself.

**Building**

- A burner mining drill costs 9 iron plate and 5 stone in total. The kit's 8
  plates are one short.
- A chest receives a drill's output only when the chest's tile contains the
  drill's `drop_position`. Read it from the live entity before placing a 1×1
  receiver. A misplaced chest leaves the drill at
  `waiting_for_space_in_destination`.
- Ore tiles at a patch edge hold 25 to 50 ore. A drill there stops with
  `no_minable_resources` within minutes. Read tile amounts first and choose
  tiles above 250.
- Mining a big sand rock yields stone.
- A small electric pole's wires reach 7.5 tiles, but it powers only machines
  within about 2.5 tiles of itself. A pole row along one side of a line leaves
  the far side unpowered.
- A belt tile moves items only in its own facing direction. A corner does not
  turn to meet its neighbour. Set every corner's direction explicitly. Confirm
  flow by reading items on the transport line, not by build success.
- The red science line (2 red assemblers, 3 labs) makes about 12 packs per
  minute and eats about 24 iron and 12 copper plates per minute. An iron chest
  holds 3200 plates, so stocked input chests carry the line for an hour.
- A green assembler (assembling-machine-1) makes 5 packs per minute. Each pack
  costs about 5.5 iron and 1.5 copper: 1 inserter plus half of a 2-belt
  craft. Two green assemblers eat 55 iron and 15 copper per minute. One each of
  gear, cable, circuit, inserter and belt assemblers covers them. (Recipe
  arithmetic, 2026-09-26. Measure once the line runs.)
- CAUTION: a hand-stocked line starves without a sign. At tick 586000 the gear
  chest ran empty. Research then sat at 7% for 18000 ticks while every lane
  reported healthy. The status script now lists starved assemblers and labs
  as `STARVED:`. Name the science input chests first in the iron service
  route, ahead of the depot.

**Assembler ratios** (recipes read live at tick 808000, assembling-machine-1
at speed 0.5, assembling-machine-2 at 0.75)

| Block | AM1 rate | Notes |
|---|---|---|
| Gears | 60/min per assembler, 120 iron/min in | AM2: 90/min |
| Circuits | 3 cable : 2 circuit assemblers = 120/min, 120 iron + 180 copper/min in | ratio holds for AM2 |
| Green pack | 5/min per assembler | 1 belt assembler and 1 inserter assembler serve 4 pack assemblers |
| Red pack | 6/min per assembler | |

- Two assemblers 4 tiles apart chain through one inserter between them.
- A 1:1 cable-to-circuit pair made 17 circuits/min, not 60. One inserter cannot
  clear the cable assembler's 2-per-craft output. Build the 3:2 block.
- The mall needs local chains for 3 items: small poles take cable, stone
  furnaces and walls take stone or brick, and a burner drill takes a stone
  furnace.

**Machine inventories decide where an inserter pays** (measured tick 540000)

- A burner drill and a stone furnace each hold one fuel stack of 50 coal. The
  furnace's result slot holds one stack of 100 plates.
- An ore module (drill → furnace by direct insertion) therefore stops after
  about 6.7 minutes, when the result slot fills. Its fuel lasts 22 minutes in
  the drill and 37 in the furnace. Output is the binding limit, not fuel.
- Put an inserter on the furnace's output into a chest. The module then runs
  until the drill's fuel runs out.
- An inserter feeding fuel from a chest tops the fuel slot up to only about 5
  coal. It burns coal itself. It buys runtime only past the 50-coal stack.
- Read `drop_position` and `pickup_position` after placing an inserter and
  confirm an entity sits at each. Four furnace-side fuel inserters placed one
  tile too far dropped their coal on the ground, and their furnaces ran dry.
- Mining a chest returns its contents to the seat along with the chest.
- Items on the ground stay there. Walking over them picks up nothing, and no
  verb picks them up.
- Direct insertion needs no inserter: a drill drops into a furnace, a chest, or
  another burner's fuel slot.
- Defend what pollutes: boilers, burner drills and furnaces. Biters target
  polluters. A turret in an empty spot at the base centre guards nothing.

**Layouts that worked** (entity centres)

| What | Where |
|---|---|
| Iron column | drills (-24,y) facing east, furnaces (-22,y), y = -42 to -63 step 3 |
| Self-fuelling ore module | drill (20,60) east, furnace (22,60), coal chest (17.5,60.5) with inserter (18.5,60.5) west into the drill, coal chest (25.5,60.5) with inserter (24.5,60.5) east into the furnace |
| Power block | pump (-52.5,-7.5) south, pipe (-52.5,-8.5), boiler (-50.5,-9) north, pipe (-50.5,-10.5), engine (-50.5,-13.5) north, pole (-48.5,-13.5) |
| Boiler feed | iron chest (-47.5,-8.5), burner inserter (-48.5,-8.5) east |
| Red science line | gear assembler (-38.5,-11.5), red assemblers (-42.5,-11.5) (-34.5,-11.5), labs (-46.5,-11.5) (-30.5,-11.5) (-26.5,-11.5), input chests on row -8.5 |

The red science line produced 73 packs before the collapse.

**Throughput**

- 8 iron modules under hand refuelling delivered 634 plates in 10 minutes,
  about 63 per minute.

### 2026-09-23 — the red science plan and the coal ring

**Milestone.** Red science is done when labs research continuously with no human
input. The test is to leave the world for an hour and return to a researched
technology and a pack chest that is still filling. Green science
(`logistic-science-pack`, 75 red) is the next milestone.

**Survey**

| Resource | Nearest tile | Patch bounding box |
|---|---|---|
| Iron ore | (-25,-44) | (-246,-153)–(-11,75) |
| Coal | (64,-36) | (64,-76)–(214,-27) |
| Stone | (64,-35) | (54,-37)–(69,-23), overlaps the coal edge |
| Copper ore | (22,50) | (6,50)–(32,73) |
| Water | (-52,-7) | 46 tiles from the iron line, 118 from coal |

Water is nearest the iron line, so the power block sits there and its coal is
carried in.

**Module designs.** A module is the unit of work. Build modules, not scattered
entities.

- **Coal ring (superseded).** Direct insertion replaces its chests and
  inserters. See the coal findings below. Ring 1 still runs this design until
  it is rebuilt. Four drills in a closed loop. Each drill outputs into its own
  chest. A burner inserter moves that chest's coal into the next drill's fuel
  slot. Ring 1: drills (68,-42) east, (72,-42) south, (72,-38) west, (68,-38)
  north. Chests (69.5,-42.5) (72.5,-40.5) (70.5,-37.5) (67.5,-39.5). Inserters
  (70.5,-42.5) (72.5,-39.5) (69.5,-37.5) (67.5,-40.5). Cost 17 iron plate and 5
  stone per drill. Prime with 4 coal per drill and 1 per inserter.
- **CAUTION** The ring encloses a 2×2 centre. A seat that walks into it is
  trapped. Remove one inserter to leave.
- **Ore module.** A drill outputs ore into a furnace. A coal chest feeds both
  fuel slots through two burner inserters. Cost 15 iron plate, 10 stone, 2
  wood. Yields 15 plates/min. Burns 3.6 coal/min.
- **Stone module.** Drill (60,-30) facing north into an iron chest at
  (59.5,-31.5). One 50-coal load mines about 330 stone.

**Coal findings**

- Burner drills on coal fuel each other by direct insertion, with no chest or
  inserter (corrected 2026-09-26 by a live test at tick 649000). A facing pair
  (78,-48) east and (80,-48) west works. A 4-drill clockwise loop works:
  (73,-48) east, (75,-48) south, (75,-46) west, (73,-46) north. Fuel rose from
  5 to 7 with no coal on the ground. The earlier failure here came from a
  misplaced drill. Collision-box arithmetic predicts a 0.004-tile miss that the
  engine does not enforce.
- CAUTION: a closed loop nets zero coal. Each drill has one output, so a
  loop's coal only circulates. The test loop filled every drill to 50 and then
  idled. A drill fed by the loop cannot exist, because every loop drill already
  outputs into the loop.
- Capture surplus with a feeder chain: C → A → B → container, each drill 2
  tiles from the next and facing it. Measured at tick 715000: 14.8 coal/min
  into the container over 10 minutes, with no inserters. B's own fuel comes from
  A, so the container gets B's full mining rate. A held 48 to 50 fuel and C
  held 49, so a 50-coal prime lasts hours. Chain: C (78,-50) south, A (78,-48)
  south, B (78,-46) east, container (80,-46).
- A chain spends 3 drills for 15 coal/min. A standalone drill into a chest
  nets 12.75 coal/min when the coal run refuels it from its own chest at each
  pickup. Use standalone drills for coal a seat hauls anyway. Use chains for
  coal nobody visits.
- CAUTION: `find_entities_filtered{position=drop, radius=0.15}` tests
  distance to entity centres, not box containment. It reports false misses
  against 2x2 drills and furnaces. Check the target's `bounding_box`, or
  `.drop_target` after the first output.
- CAUTION: a drill's `.drop_target` reads nil until its first output. Judge a
  direct-insertion link by its target's fuel count after a minute of mining,
  never by `.drop_target` on an unfuelled drill.
- A drill outputting into a chest does not refuel itself.
- A burner entity holds one stack of 50 coal. A stone furnace runs 37 minutes on
  it. A burner mining drill runs 22 minutes. An iron chest holds 1600 coal.
- One coal drill nets 12.75 coal/min and sustains about 3.5 ore modules.

**Build order.** Steps 1 to 8 were done by 2026-09-26.

1. Survey. 2. Coal ring. 3. Stone module. 4. Iron ×8. 5. Copper ×2, which fires
   `electronics`. 6. Power block. 7. Lab, which fires
   `automation-science-pack`. 8. Hand-craft 10 red packs and research
   `automation`.
9. Gear assembler: iron plates in, gears out.
10. Red science assembler: copper plate and gears in, packs to the lab by
    inserter. Red science now runs without us.
11. Belt the mines to the base.
12. Mall assemblers for circuits, gears, belts and inserters, each with an input
    and an output chest. Handcrafting basic materials ends.
13. Research `electric-mining-drill`. Convert ore and coal drills to electric.
    Hand-feeding coal to drills ends.
14. Belt coal to the furnaces. Red science is self-sustaining.

**Research ladder** (red packs): `automation` 10, `logistics` 20,
`electric-mining-drill` 25, `steel-processing` 50, `logistic-science-pack` 75.
Reaching green science costs 180 red packs.

**World**

- Dead desert trees yield 1 to 2 wood each. Build iron chests, not wooden
  chests. Keep wood for small electric poles.
- The crash site held 8 iron plates in total. Mining a wreck yields nothing.
- A seat carries 80 inventory slots.

### 2026-09-22 — the seat model

- The seat model replaced the scripted body. Mining runs at the engine's rate
  and depletes the patch. Crafting goes through the real queue, so craft and
  produce triggers fire on their own.
- A long `move` of 80 to 110 tiles often returns `path_blocked{no_path}` on the
  first try. Nudge the target by one tile. Retry. `lib/walk.sh` does this.
- `mine` at a coordinate your own entity occupies mines the entity, not the
  resource under it. The entity returns to the inventory intact. Mine an
  adjacent unbuilt tile instead.
- The `research` verb unlocks a technology outright and is flagged as a cheat.
  Select research through the force's research queue instead.

### 2026-09-19 — first contact: basics, smelting, power

**Observation**

- `observe`'s nearby list stops at 50 entities and is not sorted by distance.
  An ore field fills it with one resource type. Use `lib/find-resources.sh`.
- `exec_lua` cannot reach `fluidbox` or `neighbours`. Use
  `get_fluid_contents()`, `status` and `electric_network_id` instead.
- Status codes seen: 1 working, 5 not plugged into a network, 18 no
  ingredients, 26 no input fluid, 34 waiting for source items, 36 waiting for
  space in destination, 57 no fuel. A furnace at 18 between ore drops is
  healthy.

**Placement**

- A 2×2 entity snaps to integer centres. A 1×1 entity snaps to half-integer
  centres. Read the built position back before placing a neighbour.
- Your own body blocks a build within about one tile. Step away first.
- Directions follow the 16-way encoding: north 0, east 4, south 8, west 12.
- A burner mining drill drops its output at these offsets from its centre:
  north (-0.35,-1.30), east (1.30,-0.35), south (0.35,1.30), west
  (-1.30,0.35). Place a 2×2 receiver with its centre 2 tiles from the drill's
  centre in the facing direction.
- An inserter's `direction` names its pickup side. It drops on the opposite
  side. This holds for burner and electric inserters.
- A footprint overlap fails as `collision or invalid` with no detail. Probe with
  `surface.can_place_entity{...}` in `exec_lua` before spending the item.

**Rates**

- A burner mining drill mines 0.25 ore per second, 15 per minute.
- A stone furnace smelts one plate in 3.2 seconds, 18.75 per minute. One burner
  drill feeds one furnace.
- Iron and copper plates are not hand-craftable.
- Hand crafting runs in submission order on one queue.

**Power**

- A boiler takes water on its left and right sides when facing north. Steam
  leaves from its front. A steam engine accepts steam at either end.
- A pump, boiler and engine stacked with the boiler facing north need exactly 2
  bridge pipes.
- A burner inserter feeding a boiler tops the fuel slot up to about 5 coal and
  then waits. The loop throttles itself.
- A burner inserter fuels itself only from the coal it carries. An output
  inserter that lifts plates never refuels. Hand-fill its fuel slot on every
  service pass, or use an electric inserter.
- A steam engine reports real demand in `energy_generated_last_tick`: 0 with no
  consumer, rising with load.
