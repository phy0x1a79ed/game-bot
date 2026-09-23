# red-science-ladder — from hand-mining to self-sustaining automation science

## Purpose & Contents

This is the execution plan for the **red science milestone**: automation science
packs produced by assemblers and consumed by labs with no human input. It holds
the module designs, the sizing arithmetic, the build order, and the gotchas that
cost time. It supersedes `stage-one.md`, which sized a build by feel rather than
by consumption rate.

Record measured results here as each step lands. Replace an estimate with the
measurement the moment one exists.

Science packs are the milestone series. Red is the first. Green
(`logistic-science-pack`, 75 red) is the next.

## Milestone definition

Red science is done when labs research continuously with no human input. The
test is to leave the world for an hour and return to a researched technology and
a pack chest that is still filling.

## Starting state (2026-09-23, tick 279785, 1.3 h played)

Session `rlm-factorio-679df923d70e`, world seed `railworld-218`, seat
`seat-2c90e31d`.

| What | Where | State |
|---|---|---|
| Iron module ×2 | drills (-24,-45) (-24,-42), furnaces (-22,-45) (-22,-42) | run dry of fuel unattended |
| Coal drill ×2 | (64,-35) (66,-35) | mutual-feed, jams — see below |
| Iron chest ×2 | (56,-24) (56,-23) | stone stock |
| Stone drill | — | gone |

Researched: `steam-power` only. `electronics` is one trigger away and blocks
every electrical recipe.

**CAUTION** The coal pair self-terminates. Drill B feeds drill A's fuel slot.
Drill A's output lands 0.004 tiles outside B's collision box, a snap-grid
rounding artifact, so A jams on output. B then jams once A's fuel slot caps at
50 coal. Net unattended coal production is one stack, then zero. A coal module
needs a chest to accumulate into.

## Module designs

A module is the unit of work. Build modules, not scattered entities.

**Coal module** — drill outputs into a chest. A burner inserter returns coal
from that chest to the drill's fuel slot. Cost 12 iron plate, 5 stone, 2 wood.
Yields 12.75 coal/min net of its own burn.

**Ore module** — drill outputs ore into a furnace. One chest holds coal. Two
burner inserters feed the drill's fuel slot and the furnace's fuel slot. Cost 15
iron plate, 10 stone, 2 wood. Yields 15 plates/min. Burns 3.6 coal/min.

**Stone module** — drill outputs into a chest. A burner inserter returns coal to
the drill. Cost 12 iron plate, 5 stone, 2 wood. Yields 15 stone/min.

The drill is the limit in an ore module. A burner mining drill mines 0.25/s = 15
ore/min. A stone furnace smelts an iron plate in 3.2 s = 18.75 plates/min.

## Sizing

Target 8 iron modules. The coal budget follows from that, not from preference.

| Consumer | Count | Coal/min |
|---|---|---|
| Iron module | 8 | 28.8 |
| Copper module | 2 | 7.2 |
| Stone module | 1 | 2.25 |
| Burner inserters | ~15 | ~7 |
| **Total draw** | | **~45** |

A coal drill nets 12.75 coal/min. **Build 4 coal modules.** They net 51 coal/min.

The sizing rule to reuse: **one coal drill sustains 3.5 ore modules.**

## Build order

Stone comes second, ahead of iron. Eight iron modules need 80 stone. Automating
stone first costs 5 stone and avoids hand-mining about 75.

1. **Survey.** Run `lib/find-resources.sh`. Record the copper patch, the stone
   patch, and the nearest water to the coal patch. Water position decides where
   the power block goes.
2. **Coal ×4.** Retrofit the two existing drills with a chest and a burner
   inserter each. Add two drills. Cost 30 iron plate, 10 stone, 8 wood.
3. **Stone ×1.** Cost 12 iron plate, 5 stone, 2 wood. Manual stone mining ends.
4. **Iron ×8.** Retrofit the two existing modules with a coal chest and two
   burner inserters. Add six modules. Cost 102 iron plate, 60 stone, 16 wood.
   Iron rises from 30 to 120 plates/min.
5. **Copper ×2.** Cost 30 iron plate, 20 stone, 4 wood. Producing 10 copper
   plates fires `electronics`, which unlocks copper cable, electronic circuit,
   lab, assembling machine, inserter, and electric pole.
6. **Power block.** Offshore pump, boiler, steam engine, poles. Cost 42 iron
   plate, 5 copper plate, 5 stone, 5 wood. A steam engine produces 900 kW.
7. **Lab.** Cost 36 iron plate, 15 copper plate. Placing it fires
   `automation-science-pack`, which unlocks the red pack recipe.
8. **Handcraft 10 red packs.** Cost 20 iron plate, 10 copper plate. Research
   `automation`. This is the only research paid for by hand. Every later
   technology is paid for by the line.
9. **Gear assembler.** Iron plates in, gears to a chest. Cost 28 iron plate, 8
   copper plate, 4 wood.
10. **Red science assembler.** Copper plate and gears in, packs to a chest. An
    inserter feeds the lab. Cost 28 iron plate, 8 copper plate, 4 wood.
    **Red science is produced and consumed without us.**
11. **Belts.** Connect the mines to the base.
12. **Mall assemblers** for circuits, gears, belts, and inserters. Give every
    assembler an input chest and an output chest so it keeps working while we
    handcraft elsewhere. Handcrafting basic materials ends.
13. **Research `electric-mining-drill` (25 red).** Connect the coal mine to
    power. Convert ore drills to electric. Hand-feeding coal to drills ends.
14. **Belt coal to the furnace arrays.** Furnaces burn coal at every tech level.
    Hand-feeding coal ends. Red science is self-sustaining.

## Total materials

Steps 2 to 10 cost about 328 iron plate, 100 stone, 43 wood, and 46 copper
plate. Step 4 pays for the rest at 120 plates/min.

## Research ladder

| Technology | Cost | Unlocks |
|---|---|---|
| `electronics` | trigger: 10 copper plates | cable, circuit, lab, assembler, inserter, pole |
| `automation-science-pack` | trigger: craft 1 lab | the red pack recipe |
| `automation` | 10 red | assembling-machine-1, long-handed inserter |
| `logistics` | 20 red | underground belt, splitter |
| `electric-mining-drill` | 25 red | electric mining drill |
| `steel-processing` | 50 red | steel plate, steel chest |
| `logistic-science-pack` | 75 red | green science |

Reaching green science costs 180 red packs in total.

**CAUTION** No verb selects a technology to research. The `research` verb
unlocks one outright and is flagged `cheated:true`. Select research with
`exec-lua` calling `force.add_research(...)`, which is the interface action a
player takes, not a cheat.

## Gotchas

- A long `move` of 80 to 110 tiles returns `path_blocked{no_path}` on the first
  try. Nudge the target by one tile. Retry.
- `mine` at a coordinate your own entity occupies mines the entity, not the
  resource under it. The entity returns to inventory intact. Mine from an
  adjacent unbuilt tile instead.
- A burner entity holds one fuel stack of 50 coal. A stone furnace runs 37
  minutes on it. A burner mining drill runs 22 minutes. A wooden chest holds 800
  coal, which is why every module carries one.
- A seat carries 80 inventory slots.

## References

Module geometry and throughput measurements come from
`../basic/tech/automated-smelting.md`. Power geometry comes from
`../basic/tech/automated-power.md`. Verb names come from `rlm(verb="describe")`,
never from the recipes in `../basic/tech/`, which predate the seat model.
