# stage-one — bulk iron/copper via drill-fed furnace lines (superseded)

**Superseded by `red-science-ladder.md`**, which sizes the build from measured
consumption rates instead of by feel. Keep this file for the coordinates and the
gotchas recorded below.

## Status (session 2026-09-22, world seed 1234567)

Build started, not yet at target scale. Live on session
`rlm-factorio-679df923d70e`, seat `seat-2c90e31d`:

- Iron: 2 drill→furnace pairs running at ~(-24,-42)/(-22,-42) and
  ~(-24,-45)/(-22,-45) (one 2-tile-spaced row each — not yet the "2
  parallel rows per line" target). Both have run dry of fuel at least once;
  fuel upkeep is still manual per visit, not yet solved.
- Coal: 2 drills at (64,-35)/(66,-35), facing each other — see the
  mutual-feed gotcha below. Plan text updated to match (no chest).
- Stone: 1 drill+chest at (54,-23)/(55.5,-23.5), producing but not yet
  connected to anything — stone is hand-carried from the chest.
- Copper: not started.

Gotchas hit this session, worth knowing before continuing:

- **Long `move` (~80-110 tiles) reliably returns `path_blocked{no_path}`
  on the first try in this world**, same as the prior session's finding —
  nudge the target by ~1 tile and retry.
- **`mine` at a coordinate your own placed entity occupies mines the
  entity, not the resource beneath it** — it picked the burner-mining-drill
  over the stone tile it sits on. The entity comes back into inventory
  intact (not destroyed), but re-place it afterward. Mine from an
  adjacent, unbuilt resource tile instead.
- **Two drills facing each other for mutual coal-feed only closes the
  loop in one direction reliably.** Built at (64,-35) facing east and
  (66,-35) facing west, 2 tiles apart (the same spacing that works for
  drill→furnace): drill B's output into drill A worked, but drill A's
  reciprocal drop landed ~0.004 tiles outside drill B's collision box —
  a snap-grid rounding artifact, not a modeling error. Net effect: drill B
  mines and feeds both itself and drill A; drill A idles once its output
  buffer fills but stays fuelled indefinitely from B. The drills' own fuel
  inventories become a harvestable coal buffer (`take` a chunk, hand-carry
  it to the iron lines) — no separate chest needed, matching the
  low-effort intent below.

## Goal

Stage 1 is resource bulk, not production automation. No belts, assemblers,
or science packs yet (that's `lab-research` / `red-science-line` in
`research/basic/tech/INDEX.md`, later stages) — just a self-feeding
ore→plate pipeline sized iron-first, copper-least.

## Target / acceptance criteria

- **Iron** — the priority. Lines of furnaces running continuously off a
  drill loop (burner-mining-drill → furnace, per `research/basic/tech/automated-smelting.md`).
  No hand-mining or hand-carrying ore once built.
- **Copper** — last priority, only as much as needed to unlock copper-gated
  tech. Up to 4 furnaces.
- **Furnace lines are 2 parallel rows of furnaces**, each row drill-fed —
  not single drill→furnace pairs scattered around the patch.
- **Coal miners feed the lines** — dedicated burner-mining-drills on the
  coal patch. Instead of a drill→chest (`automated-smelting.md` §6's
  unclosed "not self-fueling" gap), pair drills facing each other so each
  feeds the other's fuel slot directly — no chest or inserter needed, and
  their own fuel inventories double as a harvestable buffer to hand-carry
  to the iron lines. See the mutual-feed gotcha in Status above.
- **A stone miner too** — every new furnace costs 5 stone, and stage 1 is
  meant to keep adding furnace lines, so hand-mining stone per furnace
  doesn't scale. A drill→chest at the stone patch (same pattern as
  `research/basic/tech/automated-smelting.md`'s coal-drill→chest demo) keeps a standing stock
  to draw from.

## Layout plan

- Iron: however many 2-row furnace lines the patch supports (size the line
  count off `research/basic/lib/find-resources.sh`'s patch measurement, not a guess).
- Copper: one line, capped at 4 furnaces total.
- Coal: drills at the coal patch paired to feed each other (mutual-feed
  loop, see Status), harvested and hand-carried to whichever line needs
  fuel — not routed via chest or inserter.
- Stone: one drill→chest at the stone patch, hand-carried to whichever
  line is next to expand — no inserter needed, it's a standing stockpile
  rather than a continuous feed.

## Open questions to resolve during the build

- Furnace count per line — set by patch depth and desired throughput.
  `research/basic/tech/automated-smelting.md` measured ~16.8–18.75 plates/min per drill+furnace
  pair, so line count times that is the achievable rate.
- Whether coal reaches every line via a real inserter/belt chain, or some
  lines stay chest-fed. `research/basic/tech/automated-power.md` found the coal patch
  ~60–95 tiles from both ore patches, which is why this was left as
  hand-carry last time.

## References

Builds on `research/basic/tech/manual-basics.md` (hand-mine/craft primitives) and
`research/basic/tech/automated-smelting.md` (the drill→furnace pattern and its unclosed
coal-feed gap this stage exists to close). Power (`research/basic/tech/automated-power.md`) is
not required for stage 1 — furnaces need no electricity.
