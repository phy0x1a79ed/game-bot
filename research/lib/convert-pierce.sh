#!/usr/bin/env bash
# convert-pierce.sh SEAT COUNT x,y [x,y ...] — at each gun turret take out its yellow magazines and insert COUNT piercing (or top piercing up to COUNT).
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; cnt=$2; shift 2
for xy in "$@"; do
  x=${xy%,*}; y=${xy#*,}
  "$LIB/walk.sh" "$seat" "$x" "$((y+3))" 5 >/dev/null 2>&1
  "$LIB/act.sh" exec_lua "$seat" code="local s=game.surfaces[1] local e=s.find_entities_filtered{name='gun-turret',position={$x,$y},radius=0.6}[1] if not e then rcon.print('($x,$y) MISSING') return end local inv=e.get_inventory(defines.inventory.turret_ammo) local y0=inv.get_item_count('firearm-magazine') local took=0 if y0>0 then local ok,r=pcall(remote.call,'game_bot','take',{seat='$seat',x=$x,y=$y,name='firearm-magazine',count=y0,target='gun-turret'}) took=ok and r.taken or 0 end local need=$cnt-inv.get_item_count('piercing-rounds-magazine') local got=0 if need>0 then local ok,r=pcall(remote.call,'game_bot','insert',{seat='$seat',x=$x,y=$y,name='piercing-rounds-magazine',count=need,target='gun-turret'}) got=ok and r.inserted or tostring(r):sub(60,140) end rcon.print(string.format('(%s,%s) yellow out %s, piercing +%s -> %d',$x,$y,took,got,inv.get_item_count('piercing-rounds-magazine')))" | jq -r .output
done
