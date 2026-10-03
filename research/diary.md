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
- A background service loop dies without a sign. `upkeep.sh` stopped at
  14:09 and 14 machines ran dry before the alerts showed it. Run every loop
  under a restart wrapper. `lib/alerts.sh` flags `UPKEEP-STALE` when the
  upkeep log is 15 minutes old.
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
   **CAUTION** `mine` picks its target by radius. Read the neighbour's
   `bounding_box` before mining near it. A lab spans 3 tiles, and a point that
   looked outside it mined the lab.
   **CAUTION** `mine` does not batch. Each call clears the previous mining
   order in the same tick, so only the last `mine` in one `exec_lua` runs.
   Mine one entity per call, about 3 seconds apart. `build`, `insert`, `take`
   and `craft` batch fine.
3. Walk with `lib/walk.sh SEAT X Y [TOL]`. It blocks until arrival and retries
   a blocked path.
4. Read many entities with one `exec_lua` query. `lib/status.lua` summarises
   the whole base.
5. Issue independent calls in parallel: several tool calls in one turn, or `&`
   and `wait` in Bash.

## Entries

### 2026-10-02 — run 4: oil, blue science and the road to the rocket

Unpaused the run 3 end save at tick 1225470. Space Age 2.1.20 is active, so the
game is won at the solar system edge; this run aims at the first rocket. Plan:
`~/.claude/plans/factorio-run4.md`. Saves: `run4-oil-processing`,
`run4-oil-park`, `run4-first-blue`, `run4-n-field`.

**Seats**

- A seat is a lease reclaimed after one hour idle, and a paused world does not
  hold it. Every run 3 seat except one was reclaimed during the pause, body and
  inventory included. Join a fresh seat per lane with `factorio-join
  --session-id <s> --owner <lane>` and record it in `crew/SEATS.md`. Restart
  the upkeep loop on its new seat.

**Rocket path (live tech tree)**

- `rocket-silo` costs red, green and blue only (1000 × 60 s). Its closure is
  concrete, rocket-fuel, processing-unit, logistic-robotics,
  low-density-structure and advanced-material-processing-2: about 2650 blue
  units. Purple and yellow science are not on the first-rocket path.
- `oil-processing` is a trigger tech: it completes when a pumpjack first mines
  crude. The pumpjack unlocks with `oil-gathering`. It unlocks the refinery,
  the chemical plant and basic oil processing.
- The silo needs 1000 steel, 200 processing units, 200 electric engines and
  1000 concrete. One rocket is 50 rocket parts.

**Oil**

- 11 crude wells lie within 512 tiles. South: one well (-56.5,177.5), 330k,
  about 11 crude/s. North: 7 wells at (-220..-241,-300..-312), 3.6M, about
  120 crude/s, 382 tiles out, spawners 89-101 tiles from it. A pumpjack makes
  10 crude/s × amount/300000. The south well alone cannot carry the rocket
  (about 125k petroleum gas needed, 79k from its life on basic oil); the north
  field is stage 2.
- Built: pole line of big poles (18,72) (2,94) (-13,116) (-29,138) (-44,160)
  (-50,171) to the south well; pumpjack into tank (-53.5,181.5); 3 turrets.
  Crude pipeline north on x=-54.5, east on y=76.5, north on x=66.5, west on
  y=-8.5 into refinery R1 (46.5,-4.5), 29 underground pairs. R2 stub at
  (53.5,-7.5). Plastic plant (34.5,2.5) → chest (34.5,5.5), about 20/min.
  Sulfur plant (38.5,2.5) → chest (38.5,5.5), about 22/min. Water: offshore
  pump (-63.5,29.5), pipe y=30.5, then x=36.5 north.
- Pipe-to-ground: the build direction is the side of the surface opening. For
  flow direction D, build the entrance facing opposite(D) and the exit facing
  D. The exit may sit up to 10 tiles from the entrance. A turn needs one plain
  pipe at the corner.
- Offshore pump: the build direction is the water side. `can_place_entity`
  reads true everywhere for pumps; try `build` positions and directions until
  one lands.
- A connected fluid system of more than about 110-120 fluidbox entities
  freezes in this build: readings stay constant and nothing flows, with the
  pipe full. Every pipe-to-ground counts. Split a long line into separate
  systems with pumps; a pump is a system boundary.
- N field (tick 1645k): pumpjacks W1-W4 at (-224.5,-307.5) (-232.5,-302.5)
  (-221.5,-300.5) (-232.5,-307.5), about 87 crude/s. 8 turrets and a wall at
  y=-315.5. Pipeline about 580 tiles: y=-296.5 east, x=-113.5 south, y=-80.5
  east, x=53.5 south to (53.5,-8.5). Pumps P1 (-113.5,-174) and P2 (55,-8.5).
  Power: 12 big poles on the diagonal from (-37,-67) to (-221,-297). R2
  (54.5,-4.5). Crude is no longer the cap; PG use is.
- A mass of about 80 small biters stages at (-48,-211). Seats died twice near
  (-57,-80) on the way north.
- Engine units cannot be hand-crafted; they need an assembling machine 2.

**Power**

- Power block 4: boilers (-44.5,-29), (-41.5,-29), 4 engines, own offshore
  pump (-74.5,-29.5) and pipe y=-29.5, coal off belt y=-26.5. Capacity 9.0 MW.

**Iron**

- Any consumer on the iron trunk x=-19.5 above y=-30 takes iron before
  science does. Three magazine assemblers there, filling 1400 magazines of
  chest, starved 7 of 8 labs at tick 1373k. Put new iron consumers downstream
  of science or on their own supply, and bar their chests to 1 slot.
- Furnace result slots read 0 on the column: their output inserters empty
  them at once. Take plates from a belt or the depot.
- Iron bank 1 (tick 1416k, +186/min, total about 600/min): 6 electric drills
  at (-29.5,-63.5..-46.5) drop ore on belt O x=-27.5. A coal feeder side-loads
  O's other lane, so 5 steel furnaces at (-30,-38..-30) fuel themselves from
  the same belt. Plates run on belt P. A splitter (-22.5,-30) with left
  priority fills the trunk first and sends the rest east to (38.5,-20.5).
- The home patch is nearly tapped out (350k, the rich core is drilled). The
  next iron is the NW patch (-144..-129,-160..-129), 640k, 104 tiles from the
  nearest spawner, or mining productivity.
- All 8 copper furnaces are steel furnaces now (+90/min once demand draws it).

**Defense**

- North wall now runs to x=-8.5 and turns south; turrets (-14,-68),
  (-12,-66). A wave of about 120 small biters died there with no loss.
- Pump wall: y=-30.5 from x=-74.5 to -47.5, then south 2 tiles.
- A pair of turrets at a field's edge dies to about 50 small biters. Use a row
  of 4 or a group of 3 overlapping.
- Spawners within 330 tiles rose from 19 to 23 by tick 1340k: nests expand.
- Hand-crafted magazines fill the pistol ammo slot first (100); `insert`
  reads only the main inventory.
- Waves reach 120-130 small biters by evolution 0.14. Four turrets with no wall
  at the oil water pump died to one. Six turrets behind a wall 3-4 tiles out
  then held a 120-biter wave with no loss and 6 magazines spent each. Defend
  an exposed site with 6 turrets and a wall.
- Damage tech past level 2 needs military science. Piercing magazines are
  unlocked with military-2: 2 yellow + 1 steel + 2 copper make 2. Hand-crafted
  piercing lands in the main inventory, so `insert` works. A turret holds one
  ammo kind: take its yellow out before inserting piercing.
- An inserter's build direction names its pickup side.
- A pipe one tile inside a wall dies with the wall: block 4's water pipe was
  cut twice. Run pipes behind a wall underground.
- The north wall's east corner and the iron column's NW flank lose a turret to
  most waves; both are now walled groups of six.

**Science**

- 8 labs; green assemblers swapped to AM2 (18/min); third red module at
  (-25.5,0.5)/(-25.5,4.5) on its own belt x=-22.5. The lab belt's east end is
  a side-load: everything on the pack belt lands on one lane, so red feeds
  through the stub on the other lane.
- First blue packs reached the labs at tick 1455k: pack AM2 (38.5,8.5),
  engine AM2 (42.5,8.5), belt north on x=41.5 and west on y=-24.5 to lab
  (-44.5,-21.5). Labs research only the current tech, so a blue tech with one
  pack assembler (3.75/min) idles 6 of 8 labs. Run red+green techs while blue
  buffers on the belt, and put blue techs first once blue passes 10/min.
- A fast tech (10 s per unit) empties green: 8 labs want about 48 green/min
  against 22 made. Long techs (30-60 s) do not.
- Blue module 2 (tick 1618k) mirrors module 1 about y=18.5 with its own
  plastic and sulfur plants: two modules make 7.6 packs/min. The pack
  assembler caps each module at about 3.75/min. Iron comes off belt P, and
  coal rides P's free lane to self-fuel the module's steel furnace.
- Lab-belt tail trap: when the research needs a pack the tail lacks, the tail
  fills with the other pack on both lanes and the missing one never arrives.
  A long-handed inserter over a one-tile underground gap hands packs lab to
  lab across a belt. 10 labs read fully fed at tick 1671k.

### 2026-10-02 — run 3: the same crew, from the run 2 end save

Reloaded `shutdown-2026-09-26` at tick 919759. Lanes: upkeep and defense,
coal, science, bus, and a researcher. Crew files live in `research/crew/`
(gitignored), so handoffs survive the supervisor's job.

**End state** (tick 1225113, save `run3-session-end-t1225113`, paused)

- Iron: 13 steel furnaces on electric drills, about 420 plates/min, more
  than the base uses. Copper: 8 electric modules, 150/min, self-fuelling.
  Coal: 6 electric drills on a belt to every boiler. Steel: 2 furnaces.
- Power: 3 boilers, 6 engines, 5.4 MW capacity, about 2.3 MW drawn.
- Science: 6 labs at 14.4 units/min, red 18 and green 15.4 packs/min, all
  by belt. 25 techs researched; the queue holds weapon-shooting-speed-2,
  toolbelt, research-speed-2, stronger-explosives-1, military-science-pack
  and engine.
- Mall: 2 rows run unattended. Circuit block idle on a capped stock.
- Defense: 43 turrets, evolution 0.115, small biters only. N1 waves of
  about 90 every ~9 game minutes; SW and W groups of 40-77.

**Next, in order.** Handoffs in `research/crew/HANDOFF-<lane>.md` hold the
coordinates.

1. Extend the north wall east from x=-14.5 to about x=-8.5 and turn it
   south, then rebuild (-14,-68). The outermost turret at the open end dies
   every wave.
2. Wall west of the pump (-69.5,-21.5); the power-block corner has 3
   overlapping turrets (-66,-25), (-63,-28), (-66,-21). Repair (-16,-66) and
   (-40,-60), and bring the ~20-magazine turrets (mall south and east,
   copper field, coal patch) to 30+.
3. Feed the ammo assembler (-37.5,-4.5) with electric inserters; burner
   inserters cap it at 9 magazines/min.
4. Spend the iron surplus: a 4th green assembler (AM2), a 7th lab, fast
   inserters on the circuit block outputs (-7.5,9.5),(0.5,9.5).
5. Chemical science (oil) is the next milestone.

**Base**

- Iron is limited by demand, not supply. At tick 950000 the iron belt at
  x=-19.5 was full from y=-63 to y=-7.5, every column furnace read
  `full_output` and the electric drills waited for space. The column can make
  about 131 plates/min (7 stone furnaces at 18.75), about 161 with the two
  field modules. Science alone wants about 79.
- A crash-site wreck sits on iron A at (-20.5,0.4), another on the circuit
  lane at (-12.8,-1.0), and the spaceship (-13.7..1.9, -9.3..-1.5) clips the
  circuit lane at y=-9..-2. Mine them before laying bus lanes south of
  y=-10.
- The upkeep loop burns more coal than coal ring 1 nets: its chests fell from
  about 1100 to 740 in one cycle, while the feeder chains' belt sat backed up.
- CAUTION: never remove a machine's feed before its replacement carries
  items. The coal builder swapped the boiler's feed chest for the end of the
  coal belt while the belt was still empty, and the base blacked out within
  minutes (tick 969000). A boiler's fuel slot holds 50 coal, about 2 minutes
  at 1.5 MW, so a 10-minute upkeep cycle cannot cover a boiler by hand.
- Iron turned supply-limited at tick ~1035000, once the circuit block and the
  mall drew on it. The two circuit assemblers (up to 120 iron/min) filled
  uncapped chests with 190 circuits, and the splitter (-19,-8.5) gives iron B
  only what row y=-7.5 leaves. Bar every output chest (3 slots) so a block
  idles when stocked.
- Coal is solved by electric drills (tick 1060000): 6 drills at
  (81.5,-45.5/-42.5/-39.5/-36.5/-33.5/-30.5) facing west drop on the east
  lane of the coal belt x=79.5, powered by a small-pole line along y=-27.5
  from (-20.5,-27.5). The belt then backs up to the boiler end. A hand-coal
  tap beside the depot feeds the upkeep loop: inserters (1.5,-27.5) and
  (2.5,-27.5) lift coal off the belt into iron chests (1.5,-28.5) and
  (2.5,-28.5), about 50 coal/min each; stand at (3.5,-30.5).
- Coal ring 1's drill (68,-42) ran out of ore at tick ~1035000, so the drill
  it fed, (72,-42), lost fuel.
- Wood runs out: the trees by the copper field are gone, and the nearest
  stand at x>=120. A small pole costs half a wood. Keep spare poles in the
  depot. Medium poles need steel.
- The west iron column (tick 1083000) adds 113 plates/min: 6 modules at
  y=-63,-60,-57,-54,-51,-48, each an electric drill (-36.5,y-0.5) facing
  east, a stone furnace (-34,y) and an electric inserter (-32.5,y+0.5)
  facing west. Its belt runs north on x=-31.5 from y=-47.5, east on
  y=-66.5 and south on x=-19.5 into the head of iron A. Poles
  (-34.5,-61.5/-55.5/-49.5) join the grid at (-27.5,-62.5). One stand,
  (-30.5,-55.5), reaches all six furnaces.
- A stone furnace is the limit of every electric-drill module: the drill
  mines 30 ore/min and the furnace smelts 18.75. Steel furnaces (after
  `advanced-material-processing`, 6 steel and 10 bricks each) swap in place
  and add 11.25/min per module.
- Power block 3 (tick 1087000) brings the cap to 5.4 MW: boiler (-52,-24.5)
  facing west, steam pipe (-53.5,-24.5), engines (-56.5,-24.5) and
  (-61.5,-24.5), electric inserter (-50.5,-24.5) off the coal belt's x=-49.5
  leg. It needs no pump: a west-facing boiler passes water through its north
  and south end tiles, so it chains off block 2's pipe end (-51.5,-22.5).
- An uncapped output chest starves everything downstream of it. At tick
  1117000 the gear assembler (-10.5,17.5), the first consumer on F, put 34
  gears/min into the chest (-11.5,20.5) (674 gears) and took 68 of the 83
  iron/min that reached F, so the mall, the steel line and the circuit block
  sat idle. A 3-slot bar returned the iron. Iron at that point: 274
  plates/min made, green line 93, gear hoard 68, magazines 47, steel 24, red
  20.
- The steel line (tick 1106000): stone furnaces (-4,17) and (-1,17) south of
  F, input inserters (-4.5,15.5),(-1.5,15.5) and output inserters
  (-4.5,18.5),(-1.5,18.5) built facing north, chests (-4.5,19.5) and
  (-1.5,19.5), pole (-2.5,16.5). A furnace inserter loads iron plates and
  skips copper, so it works off the mixed F row. Two furnaces cap at 7.5
  steel/min.
- The depot (0.5,-19.5) filled with 2.5k copper plates and refused
  deposits; a second chest at (2.5,-19.5) holds copper.
- All 13 column furnaces are steel furnaces (tick 1172000). They made 402
  plates/min while their ore buffers drained; sustained, each is
  drill-limited at 30/min, about 420/min with the field modules. Iron then
  outran every consumer: all iron belts sat full and the east furnaces
  buffered plates. The next gain is consumers (green packs, labs, the
  circuit block), not smelting. `lib/swap-furnace.sh` swaps one furnace in
  place; `lib/steel-column-status.lua` reads all 13.
- The upkeep loop must look a furnace up by type, not by name, or a swap
  silently drops it from the fuel round.
- The coal leg x=-49.5 feeds power blocks 1, 2 and the main boiler. A west
  group broke one tile of it and one water pipe (-64.5,-22.5) at tick
  1176000, and block 2 stopped within a minute. Both are single points of
  failure for the grid.

**Coal belt and copper collector** (both built by tick 990000)

- Coal rides 168 tiles from the feeder chains to the boiler with nobody
  hand-feeding: south on x=79.5 from y=-46.5 to y=-26.5, west on y=-26.5 to
  x=-49.5, south to y=-16.5, east to x=-48.5, south down the gap to y=-9.5,
  then east to the belt end (-47.5,-8.5), where the burner inserter
  (-48.5,-8.5) lifts coal into the boiler. The boiler holds only 4 to 5 coal
  that way, so supply must stay ahead of burn: 2 chains make about 30
  coal/min, and the boiler burned 18/min while the base restarted.
- The coal belt crosses the bus underground from (-17.5,-26.5) to
  (-20.5,-26.5), under iron A and the iron B slot. It occupies y=-26.5 on the
  surface at x=-16.5..-9.5, so the copper, gear and circuit lanes must end
  south of y=-26 or cross it underground.
- The only way into the boiler pocket is the x=-48.5 gap between engine 2 and
  lab 1. The turret at (-48,-18) blocks it at y=-19..-17, hence the jog.
- Power block 2 sits on the north shore, fed straight off the coal belt's
  x=-49.5 leg: offshore pump (-69.5,-21.5) facing west, pipes along y=-22.5,
  boiler (-52,-20.5) facing west, steam pipe (-53.5,-20.5), engines
  (-56.5,-20.5) and (-61.5,-20.5), electric inserter (-50.5,-20.5). A boiler
  facing west takes water at its north and south ends and puts steam out at
  its west end. Engines chain end to end with no pipe between them.
- Each feeder chain's head drill is never refuelled by the chain. Its 50-coal
  prime lasts hours, but a head found at 2 coal would have starved its chain.
  Three chains (heads at (78,-50), (78,-42), (78,-30)) make about 44
  coal/min; two boilers at full load burn 54. The coal east of the belt is
  too thin for a fourth chain.
- `act.sh craft` counts crafts, not items: 190 belt crafts made 380 belts.
- The copper collector: 8 electric drills on the rich core feed 8 stone
  furnaces, whose 8 electric inserters drop onto a belt north on x=18.5 from
  y=65.5 to 52.5, west on y=51.5 to x=-16.5, then north on x=-16.5 to
  (-16.5,-5.5), side-loading row y=-6.5. Row y=-6.5 is copper only; iron must
  not re-enter it.
- Iron C feeds the green line: a splitter at (-20,-12.5) on iron A, a belt
  down x=-20.5, under rows -7.5 and -6.5 to (-20.5,-5.5), west along y=-2.5,
  under the green belt from (-27.5,-2.5) to (-29.5,-2.5), then on y=-2.5 from
  x=-30.5 to -42.5. The green line's inserters at y=-1.5 take iron from it
  directly.

- Iron B leaves the splitter at (-19,-8.5) by its east output, passes under
  row y=-6.5 from (-18.5,-7.5) to (-18.5,-5.5), runs south on x=-18.5 to
  y=12.5, and crosses under the copper lane from (-17.5,12.5) to
  (-15.5,12.5) into the feed row F at (-14.5,14.5).
- Feed row F (y=14.5) carries iron on its north lane and copper on its
  south lane. A side-load lands on one lane only when a belt sits behind
  the receiving tile: F's first tile has an empty dummy belt at
  (-15.5,14.5). Without it the same layout forms a curve and fills both
  lanes.
- The 3:2 circuit block north of F: cable assemblers at x=-11.5, -3.5 and
  4.5, circuit assemblers at x=-7.5 and 0.5, all at y=11.5. It made about 85
  circuits/min. A gear assembler at (-10.5,17.5) makes about 60 gears/min
  into the chest (-11.5,20.5).
- A small pole in the 1-tile gap between two assemblers, on their centre
  row, powers both assemblers, the gap inserters on the rows above and
  below, the output inserter and the feed inserters. An inserter 1 tile past
  the pole's 5x5 square reads `no_power`.
- 21 trees stand just south of the copper field (x=-2..19, y=72..89), 1 wood
  each. `lib/mine-trees.sh` took 9 wood in under a minute.
- `lib/walk.sh` retries forever when the target tile lies inside a
  machine's footprint. Walk to a tile outside it.
- A furnace's result inventory is `defines.inventory.crafter_output`, its
  source `defines.inventory.crafter_input` (`furnace_source` is nil in this
  build).
- Entity status codes seen: 1 working, 14 low_power, 21
  no_minable_resources, 28 item_ingredient_shortage, 29 full_output, 33/34
  waiting_for_source_items, 36 waiting_for_space_in_destination, 58
  no_power.
- The copper furnaces fuel themselves off their own plate belt (tick
  1095000). A splitter (32.5,-26) on the coal main feeds a spur south on
  x=31.5 to y=55.5 into a return belt that ends at (18.5,67.5). The inserter
  (18.5,66.5) lifts coal from that end onto the plate belt's start, sparse
  (about 50/min). Each furnace's fuel inserter tops it to 5 coal and takes no
  plates. At the field end, a splitter (19,52.5) with `splitter_filter=coal`
  sends coal east back into the return loop and copper on west. Because the
  return belt dead-ends and backs up, supply equals burn. Splitter filter
  and priority are entity settings, set through `exec_lua`. The same pattern
  fits any furnace row with an output belt.

**Science** (tick 1016000)

- The green line runs with no hand stocking: iron by the iron C belt,
  intermediates between its assemblers by belt, copper by the row y=-6.5
  stub, and packs by belt along y=9.5 to x=-28.5 and on to the labs. Every
  lab takes red and green by inserter off a belt.
- Labs are the limit, not packs. 3 labs at 30 s per unit eat 6 of each pack
  a minute. Green makes 10 a minute and red can make 12, so green sat 40%
  idle.
- No red-only tech is left after `logistic-science-pack`: every ready tech
  needs green too, so the red-first rule waits for chemical science. The
  research queue takes at most 7 entries; `add_research` errors past that.
- At 5 labs, red becomes the limit (tick 1065000). Red asm (-42.5,-11.5)
  reads `full_output` because its packs reach only lab 1, so asm
  (-34.5,-11.5) alone fed three labs. The fix is assembling-machine-2 for
  both red asms (after `automation-2`), which needs steel.
- With both red asms on assembling-machine-2 (tick 1087000), red makes 18
  packs/min and green 10, so green is the limit. 5 labs: (-46.5,-11.5),
  (-30.5,-11.5), (-26.5,-11.5) south of belt y=-14.5, and (-44.5,-17.5),
  (-36.5,-17.5) north of it with inserters picking south. They researched
  about 9.6 units/min of 30-second techs. A stub belt at (-23.5,-14.5) makes
  the green feed a side-load, so red and green ride separate lanes.
- A third green asm at (-34.5,16.5) and a sixth lab at (-32.5,-17.5)
  (tick 1130000) brought green to 15.4 packs/min and research to 12
  units/min. The asm takes both feed belts (x=-35.5, x=-33.5) through
  undergrounds from y=8.5 to 13.5, under the pack belt and the turret
  (-35,12), and returns packs by an underground from (-34.5,13.5) that
  side-loads the pack belt at (-34.5,9.5). A lab chained by inserter from
  its neighbour gets both packs, so it needs no belt access.
- `steel-axe` is a trigger tech with no pack cost; `add_research` refuses
  it, so it cannot fill a queue slot.
- Traps: a seat mines a big rock only from within about 3 tiles; an
  inserter set before its target exists drops its item on the ground; the
  lanes of an underground exit read swapped, so identify a lane by its
  items.

**Mall** (tick 1068000, rows built, waiting on iron)

- Row 1 at y=5.5, outputs to a chest 3 tiles east of each: gear (-12.5),
  belt (-6.5), underground (-0.5), magazine (5.5), electric drill (11.5),
  assembler-1 (17.5). Row 2 at y=11.5 east of the circuit block: inserter
  (9.5), repair pack (15.5), gun turret (21.5). Iron reaches row 1 by
  extending F east to x=26.5, north, then west along y=2.5. Circuits ride
  the belt y=8.5 east to a capped stock chest (24.5,8.5).
- The mall ran unattended from tick 1068000 to 1130000 (gears +13, belts
  +6, undergrounds +4, magazines +22, one each of drill, assembler-1,
  inserter and turret), but iron-starved: every assembler read
  `item_ingredient_shortage`. An assembler-1 crafts 3-ingredient recipes.

**Defense**

- A seat repairs through the player interface. `repair_state` is per-tick
  input like `mining_state`, so a one-shot `exec_lua` does nothing.
  `lib/repair.sh` puts a repair pack on the cursor and re-asserts the
  selection and `repair_state` every tick until the entity is whole. A
  furnace at 46 of 200 health took 78 of a pack's 300 durability.
  `lib/ammo.sh SEAT [TARGET]` tops turrets up from the seat's inventory.
- At tick 1009000 the pollution cloud reached the nests: spawners absorbed
  12.6 of 286 pollution/min, and the cloud's edge sat 16 tiles from the
  north nest at (-17,-237). Evolution rose about 0.02 an hour (0.077 at tick
  920000, 0.086 at 1004000), so medium biters (0.2) are hours away and
  yellow ammo holds.
- Turret gaps at tick 1010000: the mall and circuit block had none within
  33 tiles, the copper field's south edge none, power block 2 one.
- The north line is a segment, not a perimeter. Expansion can place a new
  nest as close as y=-77, on it.
- The north wall at y=-71.5 is continuous from x=-33.5 to -14.5. The run 2
  note of a gap at x=-34..-30 was wrong by tick 919759.
- The first attack came at tick ~1034000 on the north iron field, 25 minutes
  after the cloud touched the nests. It destroyed one electric drill at
  (-24,-70) and grazed a turret and a wall tile.
- Put turrets behind the wall, overlapping. A lone turret placed outside it
  at (-23,-74) died in the next wave; its replacement stands at (-23,-69).
- Attacks come as waves, and no `unit_group` ever shows: groups form,
  launch and die between polls. The leading indicator is the count of
  units within 60 tiles of a nest. The north nest N1 (-17,-237) masses to
  40-57 small biters and launches every ~9 game minutes. Its waves stage
  near x=-30 and hit the north wall x=-30..-17. Groups from the west and
  south-west nests come along the shore to power block 2 and the green
  line. A small biter covers the 165 tiles in about 15 s, so there is no
  warning to act on. `lib/attack-watch.lua` reads the counts.
- From the first attack to tick 1117000, six waves were repelled with one
  turret and one drill lost. Evolution was 0.10 then (small biters only).
- N1's waves grow as the cloud spreads: 40, 30, then 79 small biters at
  tick 1131000, which came down at x=-4..7 and destroyed the inside turret
  (-18,-68). Spawner absorption rose from 44 to 84 pollution/min in 15
  minutes. Plan the north line for the next wave's size, not the last
  one's: about 30 magazines and 4-5 overlapping turrets per 100 small
  biters.
- The end turret of a line dies first when the line stops where the wall
  stops: the 90-biter wave at tick 1165000 rounded the wall's east end
  (x=-14.5) and killed (-18,-68) a second time. The line now carries on
  past the end: (-16,-66) and (-14,-68).
- The ammo assembler (-37.5,-4.5) is fed by burner inserters at about 36
  iron/min, so it makes about 9 magazines/min, not its 30. Insert iron
  straight into the assembler when waves grow.
- A seat can die. It respawns empty at (-0.6,-0.6), and its corpse keeps
  the inventory: `take target=character-corpse`, one item name per call.
  From the respawn point `walk.sh` jams on the crash wreck (-12.8,-1.0);
  walk to (-9,1) and (-14.4,1.8) first.
- `lib/repair.sh` walks to the nearest damaged entity anywhere on the map,
  not only near the seat.
- Both radars are mined (300 kW each, and no script reads them).
- Turrets added by tick 1065000: mall (-22,10), (-22,17), (-2,25), (12,25),
  (29,16); green science (-27,9); copper field south (17,69), (24,69); power
  block 2 (-66,-25), (-58,-29); stone drill (57,-30). Added by tick
  1120000: west flank (-40,-60), (-40,-48); coal patch (75,-55); south-west
  of the green line (-43,11), (-35,12); mall centre (-6,21), (10,21).
- Magazines come from the ammo assembler (-37.5,-4.5): `lib/feed-ammo.sh
  SEAT` moves iron into its input chest (-40.5,-4.5) and collects magazines
  from (-34.5,-4.5).

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
| Labs research on green packs (`electric-energy-distribution-1`) | never | ~893000 |

**State at tick 919000** (save `run2-session-end-t919k`, world paused):

- Iron: 7 electric drills on the column, all rows dropping onto the iron belt.
  A splitter at (-19,-8.5) sends overflow to the future iron B lane.
- Copper: 8 burner modules on the rich core, each into its own chest. The
  copper lane's base end feeds both red copper chests and the mall row's
  copper chest. Its collector through the copper field is not built, so
  `lib/upkeep.sh` still hauls copper.
- Power: 1 boiler, 2 engines, 664 kW of 1800 kW used.
- Science: red runs unattended. The green line makes packs, but two of its
  feed chests are hand-stocked. Only lab 3 receives green.
  `electric-energy-distribution-1` is under way.
- Coal: 2 feeder chains drop coal onto a belt stub at (79.5,-46.5). The belt
  to the boiler is not built.
- Defense: 17 turrets, a stone wall at y=-71.5 with a 5-tile gap at
  x=-34..-30. Evolution about 0.06.

**Next, in order.** All five items (coal belt, green to every lab, copper
collector and iron B, repairs, mall) landed in run 3. The current list is in
the 2026-10-02 entry.

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
- A splitter's `splitter_output_priority` names a side relative to its
  facing. A splitter facing south with priority `right` fills its west output
  first. Test the side on a small rig before relying on it.
- An underground belt reaches 5 tiles here (`max_underground_distance`).
- CAUTION: build an underground exit with the direction opposite to the
  flow: entrance north, exit south. The engine then makes the exit an output
  that reads north, and a live pair reads input D + output D. Never
  `.rotate()` the exit afterwards: rotating flips the output to the wrong
  direction. An exit built with the flow's direction becomes a second input.
  Both mistakes form a dead pair that holds items forever without an error.
  Check `belt_to_ground_type` and `direction` on both ends. (Corrected
  2026-10-02: the earlier advice to rotate left three dead pairs on the
  science rows, and iron stalled there.)
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
| Iron column | electric drills (-24.5,y-0.5) facing east, steel furnaces (-22,y), y = -45 to -63 step 3; west column drills (-36.5,y-0.5), steel furnaces (-34,y), inserters (-32.5,y+0.5), y = -48 to -63 step 3 |
| Power blocks 2 and 3 | pump (-69.5,-21.5) west, pipe y=-22.5, boilers (-52,-20.5) and (-52,-24.5) west, engines (-56.5/-61.5,-20.5) and (-56.5/-61.5,-24.5), electric inserters (-50.5,-20.5/-24.5) off the coal leg x=-49.5 |
| Self-fuelling furnace row | coal injected sparse onto the plate belt, fuel inserters per furnace, filter splitter at the field end returning coal to a dead-ended loop (copper field, 2026-10-02) |
| Steel line | stone furnaces (-4,17),(-1,17), inserters north at y=15.5 and y=18.5, chests y=19.5 |
| Brick line | stone chest (59.5,-31.5), inserter (59.5,-32.5) south, furnace (59,-34), inserter (57.5,-34.5) east, chest (56.5,-34.5) |
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
- A chain's last drill drops straight onto a belt tile. Two chains run at
  the ring-1 patch since tick 860000: C (78,-50) south, A (78,-48) south,
  B (78,-46) east onto belt (79.5,-46.5). C2 (78,-42) south, A2 (78,-40) south,
  B2 (78,-38) east onto belt (79.5,-38.5). Together they make about 30
  coal/min, enough for 2 engines at full load.
- At tick 860000 the 2 engines supplied 664 kW of 1800 kW. The boiler burned
  7.2 coal/min, measured from its feed chest over 24 minutes. Read
  `energy_generated_last_tick` as joules per tick: multiply by 60 for watts.
- The power block's interior is a sealed pocket. No new belt reaches the
  boiler until poles (-37.5,-6.5) and (-48.5,-13.5) move 1 tile each. Leave a
  belt-wide gap into every block you build.
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
