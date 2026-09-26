#!/usr/bin/env bash
# service-iron-column.sh SEAT [COAL_PER_BURNER] [SELF_CHEST_COAL] [--no-deposit]
# One sweep of the whole iron column + a depot drop. Safe to call repeatedly;
# insert/take just clip to whatever's available/needed. Needs coal on hand --
# run a coal-ring run first (see coal-run.sh), or call loop-service.sh which
# does that automatically.
#
# Topology as of 2026-09-26 (see diary "Machine inventories decide where an
# inserter pays" + the furnace-feed redesign + the belt hand-off):
#
# BELT_YS (drill x=-24, furnace x=-22, y in BELT_YS): output inserter
# (-20.5,y,dir=west) drops plates onto science's transport-belt trunk at
# x=-19.5 (runs y=-62.5..-7.5), which carries them straight to the gear
# assembler's input chest (-38.5,-8.5). NO plate collection happens here any
# more for these rows -- there's no chest, just fuel maintenance. y=-45/-48
# are hand-fed (drill+furnace fuelled directly); y=-51/-54/-57/-60/-63 have a
# self-fuelling drill (coal chest ~(-27,y) -> inserter ~(-26,y,west) -> drill)
# plus a hand-fed furnace. Every row's OUTPUT inserter burns fuel too (2026-
# 09-26: all 5 ran dry once already) -- keep it topped or the belt starves.
#
# EAST_YS (drill x=-15 facing WEST, furnace x=-17, y in EAST_YS): new modules
# on a separate rich ore lobe found east of the belt (2026-09-26 survey).
# Output inserter (-18.5,y,dir=east) picks up from the furnace on its east
# side and drops onto the SAME belt trunk at x=-19.5 from the other side.
# Hand-fed (drill+furnace), no self-fuel chest.
#
# OFFCOL modules (drill/furnace pairs not adjacent to the belt): each gets its
# own output inserter+chest instead of a belt tap. This script hand-feeds
# fuel and SWEEPS these chests into inventory for the depot drop -- they are
# now the main source of iron the depot sees from this column, since every
# belt-tapped row bypasses the depot entirely.
#   - RELOC ex-(-24,-42), moved to rich ore: drill(-32,-44)/furnace(-30,-44),
#     output inserter(-28.5,-44,west)+chest(-27.5,-44).
#   - Module A (pre-existing, adopted 2026-09-26): drill(-34,-42)/
#     furnace(-32,-42), output inserter(-30.5,-42,west)+chest(-29.5,-42).
#
# Then tops the gear assembler's input chest (-38.5,-8.5) to GEAR_TARGET
# (belt should mostly cover this now; kept as a backstop), then deposits
# everything collected above a small on-hand buffer to the depot chest
# (0.5,-19.5).
#
# Checks for enemies within 150 of the column before moving (diary rule:
# read enemy positions before every move); aborts the sweep if any are found.
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
coal=${2:-40}
self_coal=${3:-60}
deposit=1
[ "${4:-}" = "--no-deposit" ] && deposit=0
[ "${3:-}" = "--no-deposit" ] && { deposit=0; self_coal=60; }
[ -z "$seat" ] && { echo "usage: service-iron-column.sh SEAT [coal_per_burner] [self_chest_coal] [--no-deposit]"; exit 1; }

HAND_YS=(-45 -48)
SELF_YS=(-51 -54 -57 -60 -63)
EAST_YS=(-51 -57)
DEPOT_X=0.5
DEPOT_Y=-19.5
BUFFER=20

echo "== enemy check =="
LUA_ENEMY_CHECK='local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={-23,-53},radius=150}) do n=n+1 end rcon.print(n)'
enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_ENEMY_CHECK" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
echo "enemies within 150 of column: ${enemies:-0}"
if [ "${enemies:-0}" != "0" ]; then
  echo "ABORT: enemies detected near the iron column, not walking in."
  exit 1
fi

total_coal_in=0
total_plates=0

for y in "${HAND_YS[@]}"; do
  wy=$((y + 2))
  "$LIB/walk.sh" "$seat" -23 "$wy" 3 >/dev/null 2>&1
  di=$("$LIB/act.sh" insert "$seat" x=-24 y=$y name=coal count="$coal" target=burner-mining-drill | jq -r '.inserted // 0')
  fi=$("$LIB/act.sh" insert "$seat" x=-22 y=$y name=coal count="$coal" target=stone-furnace | jq -r '.inserted // 0')
  oi=$("$LIB/act.sh" insert "$seat" x=-20.5 y=$y name=coal count=20 target=burner-inserter | jq -r '.inserted // 0')
  total_coal_in=$((total_coal_in + di + fi + oi))
  echo "hand-fed y=$y: drill+${di} furnace+${fi} out-inserter+${oi} coal (belt-fed, no collection)"
done

for y in "${SELF_YS[@]}"; do
  wy=$((y + 2))
  "$LIB/walk.sh" "$seat" -23 "$wy" 3 >/dev/null 2>&1
  cw=$("$LIB/act.sh" insert "$seat" x=-27 y=$y name=coal count="$self_coal" target=iron-chest | jq -r '.inserted // 0')
  fi=$("$LIB/act.sh" insert "$seat" x=-22 y=$y name=coal count="$coal" target=stone-furnace | jq -r '.inserted // 0')
  oi=$("$LIB/act.sh" insert "$seat" x=-20.5 y=$y name=coal count=20 target=burner-inserter | jq -r '.inserted // 0')
  total_coal_in=$((total_coal_in + cw + fi + oi))
  echo "self-fed y=$y: drill-chest+${cw} furnace+${fi} out-inserter+${oi} coal (belt-fed, no collection)"
done

for y in "${EAST_YS[@]}"; do
  wy=$((y - 2))
  "$LIB/walk.sh" "$seat" -15 "$wy" 3 >/dev/null 2>&1
  di=$("$LIB/act.sh" insert "$seat" x=-15 y=$y name=coal count="$coal" target=burner-mining-drill | jq -r '.inserted // 0')
  fi=$("$LIB/act.sh" insert "$seat" x=-17 y=$y name=coal count="$coal" target=stone-furnace | jq -r '.inserted // 0')
  oi=$("$LIB/act.sh" insert "$seat" x=-18.5 y=$y name=coal count=20 target=burner-inserter | jq -r '.inserted // 0')
  total_coal_in=$((total_coal_in + di + fi + oi))
  echo "east y=$y: drill+${di} furnace+${fi} out-inserter+${oi} coal (belt-fed, no collection)"
done

# off-belt modules: RELOC + adopted module A -- own output chest, swept by hand
"$LIB/walk.sh" "$seat" -29 -42 3 >/dev/null 2>&1
di=$("$LIB/act.sh" insert "$seat" x=-32 y=-44 name=coal count="$coal" target=burner-mining-drill | jq -r '.inserted // 0')
fi=$("$LIB/act.sh" insert "$seat" x=-30 y=-44 name=coal count="$coal" target=stone-furnace | jq -r '.inserted // 0')
oi=$("$LIB/act.sh" insert "$seat" x=-28.5 y=-44 name=coal count=20 target=burner-inserter | jq -r '.inserted // 0')
pt=$("$LIB/act.sh" take "$seat" x=-27.5 y=-44 name=iron-plate | jq -r '.taken // 0')
total_coal_in=$((total_coal_in + di + fi + oi))
total_plates=$((total_plates + pt))
echo "reloc (-32,-44)/(-30,-44): drill+${di} furnace+${fi} out-inserter+${oi} coal, took ${pt} plates from output chest"

da=$("$LIB/act.sh" insert "$seat" x=-34 y=-42 name=coal count="$coal" target=burner-mining-drill | jq -r '.inserted // 0')
fa=$("$LIB/act.sh" insert "$seat" x=-32 y=-42 name=coal count="$coal" target=stone-furnace | jq -r '.inserted // 0')
oa=$("$LIB/act.sh" insert "$seat" x=-30.5 y=-42 name=coal count=20 target=burner-inserter | jq -r '.inserted // 0')
pa=$("$LIB/act.sh" take "$seat" x=-29.5 y=-42 name=iron-plate | jq -r '.taken // 0')
total_coal_in=$((total_coal_in + da + fa + oa))
total_plates=$((total_plates + pa))
echo "module A (-34,-42)/(-32,-42): drill+${da} furnace+${fa} out-inserter+${oa} coal, took ${pa} plates from output chest"

echo "TOTAL: coal inserted=$total_coal_in plates collected=$total_plates"

# 2026-09-26: the gear assembler's input chest (-38.5,-8.5) is fed by the belt
# now, but keep this as a backstop in case it backs up or drops.
GEAR_X=-38.5
GEAR_Y=-8.5
GEAR_TARGET=500
gear_have=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "local c=game.surfaces[1].find_entities_filtered{position={$GEAR_X,$GEAR_Y},radius=1,name='iron-chest'}[1] rcon.print(c and c.get_inventory(defines.inventory.chest).get_item_count('iron-plate') or -1)" 2>/dev/null | jq -r '.output // "-1"' | tr -d '[:space:]')
echo "gear-asm chest (${GEAR_X},${GEAR_Y}) currently has ${gear_have} iron"
if [ "${gear_have:-0}" -ge 0 ] 2>/dev/null; then
  need=$((GEAR_TARGET - gear_have))
  if [ "$need" -gt 0 ]; then
    "$LIB/walk.sh" "$seat" "$GEAR_X" "$GEAR_Y" 3 >/dev/null 2>&1
    fed=$("$LIB/act.sh" insert "$seat" x=$GEAR_X y=$GEAR_Y name=iron-plate count="$need" target=iron-chest | jq -r '.inserted // 0')
    echo "topped up gear-asm chest by ${fed} iron (target ${GEAR_TARGET})"
  else
    echo "gear-asm chest already at/above target, skipping"
  fi
fi

if [ "$deposit" = 1 ]; then
  have=$("$LIB/act.sh" observe "$seat" radius=1 | jq -r '.snapshot.inventory["iron-plate"] // 0')
  drop=$((have - BUFFER))
  if [ "$drop" -gt 0 ]; then
    "$LIB/walk.sh" "$seat" 0.5 -21 3 >/dev/null 2>&1
    got=$("$LIB/act.sh" insert "$seat" x=$DEPOT_X y=$DEPOT_Y name=iron-plate count="$drop" target=iron-chest | jq -r '.inserted // 0')
    echo "deposited $got iron-plate to depot ($DEPOT_X,$DEPOT_Y), kept $BUFFER on hand"
  else
    echo "only $have iron-plate on hand (<=$BUFFER buffer), skipping depot drop"
  fi
fi
