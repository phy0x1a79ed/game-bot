#!/usr/bin/env bash
# build-turrets.sh SEAT
# One-shot: craft 2 gun turrets (20 iron + 10 copper + 10 gears each) + 40
# firearm magazines (4 iron each), then place them on the iron column's east
# side at (-17,-46) and (-17,-54) -- clear of the self-fed rows' east coal
# chests at x=-19 -- with 20 magazines loaded in each.
# Pulls iron/copper from the depot chest (0.5,-19.5); seat starts near there.
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
[ -z "$seat" ] && { echo "usage: build-turrets.sh SEAT"; exit 1; }

DEPOT_X=0.5
DEPOT_Y=-19.5
SPOTS=("-17 -46" "-17 -54")

echo "== enemy check (150 around iron column + depot) =="
LUA_ENEMY_CHECK='local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={-10,-33},radius=150}) do n=n+1 end rcon.print(n)'
enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_ENEMY_CHECK" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
echo "enemies within 150: ${enemies:-0}"
if [ "${enemies:-0}" != "0" ]; then
  echo "ABORT: enemies detected, not proceeding."
  exit 1
fi

echo "== stocking materials from depot =="
"$LIB/walk.sh" "$seat" "$DEPOT_X" "$DEPOT_Y" 3 >/dev/null
gi=$("$LIB/act.sh" take "$seat" x=$DEPOT_X y=$DEPOT_Y name=iron-plate count=230 target=iron-chest | jq -r '.taken // 0')
gc=$("$LIB/act.sh" take "$seat" x=$DEPOT_X y=$DEPOT_Y name=copper-plate count=25 target=iron-chest | jq -r '.taken // 0')
echo "took ${gi} iron-plate, ${gc} copper-plate from depot"

echo "== queueing crafts =="
"$LIB/act.sh" craft "$seat" recipe=iron-gear-wheel count=20
"$LIB/act.sh" craft "$seat" recipe=firearm-magazine count=40
"$LIB/act.sh" craft "$seat" recipe=gun-turret count=2

echo "== waiting for crafting queue to drain =="
for i in $(seq 1 40); do
  sleep 3
  qsize=$("$LIB/act.sh" observe "$seat" radius=1 | jq -r '.snapshot.crafting_queue_size // 0')
  echo "  queue size: $qsize"
  [ "$qsize" = "0" ] && break
done

inv=$("$LIB/act.sh" observe "$seat" radius=1 | jq -c '.snapshot.inventory')
echo "post-craft inventory: $inv"

echo "== placing turrets =="
for spot in "${SPOTS[@]}"; do
  set -- $spot; x=$1; y=$2
  "$LIB/walk.sh" "$seat" "$x" "$y" 3 >/dev/null
  b=$("$LIB/act.sh" build "$seat" name=gun-turret x="$x" y="$y" direction=east)
  echo "build @ $x,$y: $b"
  m=$("$LIB/act.sh" insert "$seat" x="$x" y="$y" name=firearm-magazine count=20 target=gun-turret | jq -r '.inserted // 0')
  echo "  loaded ${m} magazines"
done

echo "== final =="
"$LIB/act.sh" observe "$seat" radius=1 | jq -c '.snapshot.inventory'
