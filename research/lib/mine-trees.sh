#!/usr/bin/env bash
# mine-trees.sh SEAT WOOD_TARGET X Y [RADIUS] — mine the nearest trees around (X,Y) until the seat holds WOOD_TARGET wood.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; target=$2; X=$3; Y=$4; R=${5:-30}
for i in $(seq 1 30); do
  have=$("$LIB/act.sh" exec_lua "$seat" code='rcon.print(player.get_main_inventory().get_item_count("wood"))' | jq -r .output)
  [ "$have" -ge "$target" ] && { echo "wood=$have"; exit 0; }
  t=$("$LIB/act.sh" exec_lua "$seat" code="local best,bd for _,e in pairs(game.surfaces[1].find_entities_filtered{type='tree',position={$X,$Y},radius=$R}) do local d=(e.position.x-player.position.x)^2+(e.position.y-player.position.y)^2 if not bd or d<bd then best,bd=e,d end end if best then rcon.print(best.position.x..' '..best.position.y) else rcon.print('none') end" | jq -r .output)
  [ "$t" = none ] && { echo "no trees left; wood=$have"; exit 1; }
  set -- $t
  "$LIB/walk.sh" "$seat" "$1" "$2" 4 >/dev/null
  "$LIB/act.sh" mine "$seat" x="$1" y="$2" >/dev/null
  for j in $(seq 1 15); do sleep 1
    gone=$("$LIB/act.sh" exec_lua "$seat" code="rcon.print(#game.surfaces[1].find_entities_filtered{type='tree',position={$1,$2},radius=0.5})" | jq -r .output)
    [ "$gone" = 0 ] && break
  done
done
