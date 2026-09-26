#!/usr/bin/env bash
# build-copper-module.sh SEAT Y [SKIP_DRILL_FURNACE]
# Build one full self-fueling copper module at row Y:
#   drill (20,Y) east -> furnace (22,Y).
#   Fuel infra goes EAST/WEST on the same row (not north/south) so modules can
#   sit close together without their oversized bounding boxes colliding:
#     chest(17,Y) -> inserter(18,Y,dir=west) -> drill(20,Y)
#     chest(25,Y) -> inserter(24,Y,dir=east) -> furnace(22,Y)
# Requires in inventory: (unless SKIP_DRILL_FURNACE=1) 1 burner-mining-drill,
# 1 stone-furnace; always: 2 iron-chest, 2 burner-inserter; plus coal to prime.
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; Y=$2; skip=${3:-0}
[ -z "${Y:-}" ] && { echo "usage: build-copper-module.sh SEAT Y [skip_drill_furnace]"; exit 1; }

"$LIB/walk.sh" "$seat" 21 "$Y" 6 >/dev/null

echo "-- building module row $Y --"
if [ "$skip" != "1" ]; then
  "$LIB/act.sh" build "$seat" name=burner-mining-drill x=20 y=$Y direction=east
  "$LIB/act.sh" build "$seat" name=stone-furnace x=22 y=$Y
fi
"$LIB/act.sh" build "$seat" name=iron-chest x=17 y=$Y
"$LIB/act.sh" build "$seat" name=iron-chest x=25 y=$Y
"$LIB/act.sh" build "$seat" name=burner-inserter x=18 y=$Y direction=west
"$LIB/act.sh" build "$seat" name=burner-inserter x=24 y=$Y direction=east

echo "-- priming fuel --"
"$LIB/act.sh" insert "$seat" x=17 y=$Y name=coal count=30 target=iron-chest
"$LIB/act.sh" insert "$seat" x=25 y=$Y name=coal count=30 target=iron-chest
"$LIB/act.sh" insert "$seat" x=18 y=$Y name=coal count=4 target=burner-inserter
"$LIB/act.sh" insert "$seat" x=24 y=$Y name=coal count=4 target=burner-inserter
"$LIB/act.sh" insert "$seat" x=20 y=$Y name=coal count=25 target=burner-mining-drill
"$LIB/act.sh" insert "$seat" x=22 y=$Y name=coal count=25 target=stone-furnace

echo "-- module row $Y done --"
"$LIB/act.sh" observe "$seat" radius=1 | jq -c '.snapshot.inventory'
