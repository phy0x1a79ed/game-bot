#!/usr/bin/env bash
# place-turrets.sh SEAT AMMO COUNT x,y [x,y ...] — walk to each spot, build a gun turret (if none), insert COUNT of AMMO.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; ammo=$2; cnt=$3; shift 3
for xy in "$@"; do
  x=${xy%,*}; y=${xy#*,}
  "$LIB/walk.sh" "$seat" "$x" "$((y+3))" 4 >/dev/null 2>&1
  "$LIB/act.sh" exec_lua "$seat" code="local s=game.surfaces[1] local e=s.find_entities_filtered{name='gun-turret',position={$x,$y},radius=0.6}[1] local b='exists' if not e then local ok,r=pcall(remote.call,'game_bot','build',{seat='$seat',name='gun-turret',x=$x,y=$y}) b=ok and (r.built and 'built' or serpent.line(r)) or tostring(r) end local ok,r=pcall(remote.call,'game_bot','insert',{seat='$seat',x=$x,y=$y,name='$ammo',count=$cnt,target='gun-turret'}) e=s.find_entities_filtered{name='gun-turret',position={$x,$y},radius=0.6}[1] rcon.print('($x,$y) '..b..' ammo '..(e and e.get_inventory(defines.inventory.turret_ammo).get_item_count() or -1))" | jq -r .output
done
