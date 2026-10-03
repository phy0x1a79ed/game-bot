#!/usr/bin/env bash
# perim-watch.sh SEAT SECS — poll every 10 s for enemy units within 25 tiles of any defended zone (west + north + east); exit printing the sighting (or 'quiet' at timeout).
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; secs=${2:-600}; end=$((SECONDS+secs))
code="local s=game.surfaces[1] local Z={coal={60,-62,90,-40},nwall={-36,-76,0,-58},steel={0,-56,45,-35},blk5={76,-30,95,-4},opark={25,25,56,50},eblue={60,20,110,52},nwpatch={-155,-160,-125,-130},pipe={-75,-115,-10,-76},blk4={-80,-36,-55,-15},pumpw={-70,28,-48,46},sw={-50,4,-28,22},soil={-72,165,-40,192},copper={-2,44,36,76},nwflank={-50,-68,-36,-48},p1={-125,-185,-105,-160}} local o={} for n,b in pairs(Z) do local en=s.find_entities_filtered{force='enemy',type='unit',area={{b[1]-25,b[2]-25},{b[3]+25,b[4]+25}}} if #en>0 then local t={} for _,e in ipairs(en) do t[e.name]=(t[e.name] or 0)+1 end local q={} for k,v in pairs(t) do q[#q+1]=k..'='..v end o[#o+1]=string.format('%s %d at (%d,%d) %s',n,#en,en[1].position.x,en[1].position.y,table.concat(q,',')) end end rcon.print(game.tick..' '..table.concat(o,' ; '))"
while [ $SECONDS -lt $end ]; do
  r=$("$LIB/act.sh" exec_lua "$seat" code="$code" 2>/dev/null | jq -r '.output // ""')
  case "$r" in *" at ("*) echo "SIGHTING $r"; exit 0;; esac
  sleep 10
done
echo "quiet $r"
