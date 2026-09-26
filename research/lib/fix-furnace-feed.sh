#!/usr/bin/env bash
# fix-furnace-feed.sh SEAT
# 2026-09-26 redesign: the self-fed rows' furnace-side fuel inserter
# (-19.5,y+0.5, dir=east) drops coal at (-20.7,y+0.5) -- 0.3 tile short of the
# furnace's collision box -- so it has been piling coal on the ground instead
# of fuelling stone-furnace(-22,y). Per supervisor: rip that loop out, hand-feed
# the furnace+drill directly, and replace it with an OUTPUT loop instead: a new
# burner-inserter(-20.5,y,dir=west) picks up plates from the furnace and drops
# them in a new chest(-19.5,y), so the service routine only has to empty a
# chest, not reach into the furnace's result slot.
# Requires coal (>=104/row: 50 furnace + 50 drill + 4 new-inserter) and
# iron-plate+iron-gear-wheel on hand to craft the 3 replacement inserters
# (already crafted by the caller) -- the mined chest is reused for the new one.
# NOTE 2026-09-26: mining the broken chest recovers its stored coal into
# inventory automatically (it was piling up unused -- one row alone gave back
# 133 coal). The small amount actually spilled on the ground at the drop point
# is NOT auto-picked-up by walking over it (tested: inventory unchanged), and
# there is no verb for looting an item-on-ground entity, so it's left in place
# (1-2 coal per row observed -- not worth the reach).
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; shift
[ -z "$seat" ] && { echo "usage: fix-furnace-feed.sh SEAT [row_y ...]"; exit 1; }

if [ "$#" -gt 0 ]; then ROWS=("$@"); else ROWS=(-51 -54 -57); fi

echo "== enemy check =="
LUA_ENEMY_CHECK='local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={-23,-54},radius=150}) do n=n+1 end rcon.print(n)'
enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_ENEMY_CHECK" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
echo "enemies within 150: ${enemies:-0}"
if [ "${enemies:-0}" != "0" ]; then
  echo "ABORT: enemies detected, not proceeding."
  exit 1
fi

for y in "${ROWS[@]}"; do
  sy=$(echo "$y + 0.5" | bc)
  echo "-- row y=$y (sub-row y=$sy) --"
  "$LIB/walk.sh" "$seat" -21 "$y" 3 >/dev/null

  echo "mining broken inserter(-19.5,$sy) + chest(-18.5,$sy)"
  "$LIB/act.sh" mine "$seat" x=-19.5 y="$sy"
  "$LIB/act.sh" mine "$seat" x=-18.5 y="$sy"

  echo "hand-filling furnace($y) and drill($y)"
  "$LIB/act.sh" insert "$seat" x=-22 y=$y name=coal count=50 target=stone-furnace
  "$LIB/act.sh" insert "$seat" x=-24 y=$y name=coal count=50 target=burner-mining-drill

  echo "building output inserter(-20.5,$y,west) + chest(-19.5,$y)"
  wy2=$((y + 2))
  "$LIB/walk.sh" "$seat" -23 "$wy2" 2 >/dev/null
  "$LIB/act.sh" build "$seat" name=burner-inserter x=-20.5 y=$y direction=west
  "$LIB/act.sh" build "$seat" name=iron-chest x=-19.5 y=$y
  "$LIB/act.sh" insert "$seat" x=-20.5 y=$y name=coal count=4 target=burner-inserter

  echo "verifying pickup/drop"
  code="local e=game.surfaces[1].find_entities_filtered{position={-20.5,$y},radius=0.6,name='burner-inserter'}[1]
if e then rcon.print('pickup='..e.pickup_position.x..','..e.pickup_position.y..' drop='..e.drop_position.x..','..e.drop_position.y) else rcon.print('NO INSERTER FOUND') end"
  RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$code"
done

echo "== final inventory =="
"$LIB/act.sh" observe "$seat" radius=1 | jq -c '.snapshot.inventory'
