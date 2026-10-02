#!/usr/bin/env bash
# swap-furnace.sh SEAT "x,y x,y ..." — replace the stone furnace centred at each point with a
# steel furnace from the seat's inventory, then fuel it with 20 coal. Seat must be within reach.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
lua() { "$LIB/act.sh" exec_lua "$seat" code="local seat='$seat' $1" | jq -r '.output // .'; }
for p in $2; do
  x=${p%,*}; y=${p#*,}
  name=$(lua "local e=game.surfaces[1].find_entity('stone-furnace',{$x,$y}) rcon.print(e and e.name or 'none')")
  if [ "$name" != stone-furnace ]; then echo "($x,$y) no stone furnace: $name"; continue; fi
  "$LIB/act.sh" mine "$seat" x="$x" y="$y" >/dev/null
  gone=0
  for j in $(seq 1 25); do sleep 0.4
    [ "$(lua "rcon.print(game.surfaces[1].find_entity('stone-furnace',{$x,$y}) and 1 or 0)")" = 0 ] && { gone=1; break; }
  done
  [ $gone = 1 ] || { echo "($x,$y) mine stuck"; continue; }
  lua "local r={} local ok,v=pcall(remote.call,'game_bot','build',{seat=seat,name='steel-furnace',x=$x,y=$y,direction='north'}) r[#r+1]='build '..serpent.line(v) ok,v=pcall(remote.call,'game_bot','insert',{seat=seat,x=$x,y=$y,name='coal',count=40,target='steel-furnace'}) r[#r+1]='coal '..serpent.line(v) ok,v=pcall(remote.call,'game_bot','insert',{seat=seat,x=$x,y=$y,name='iron-ore',count=70,target='steel-furnace'}) r[#r+1]='ore '..serpent.line(v) rcon.print('($x,$y) '..table.concat(r,' | '))"
done
