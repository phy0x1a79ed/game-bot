#!/usr/bin/env bash
# mine-ents.sh SEAT "x,y x,y ..." — mine the player entity at each point, one at a time, waiting until it is gone.
# Seat must already be within reach. Reports the points that stayed.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; fail=""
for p in $2; do
  x=${p%,*}; y=${p#*,}
  "$LIB/act.sh" mine "$seat" x="$x" y="$y" >/dev/null
  ok=0
  for j in $(seq 1 25); do sleep 0.4
    n=$("$LIB/act.sh" exec_lua "$seat" code="rcon.print(#game.surfaces[1].find_entities_filtered{position={$x,$y},radius=0.45,force='player'})" | jq -r .output)
    [ "$n" = 0 ] && { ok=1; break; }
  done
  [ $ok = 1 ] || fail="$fail $p"
done
echo "stuck:$fail"
