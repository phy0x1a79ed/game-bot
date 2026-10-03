#!/usr/bin/env bash
# trunk-place.sh SEAT XFROM XTO — place rail pieces (odd x, y=-161, east) from the seat's inventory, walking the trunk in 18-tile windows with safe-walk.
# Pieces already built are skipped. Prints one line per window: stand x, built, failed.
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib
seat=$1; xf=$2; xt=$3
for ((c=xf+9; ; c+=18)); do
  lo=$((c-9)); hi=$((c+9)); [ $hi -gt $xt ] && hi=$xt; [ $((lo%2)) -eq 0 ] && lo=$((lo+1))
  [ $lo -gt $xt ] && break
  mid=$(( (lo+hi)/2 ))
  "$L/safe-walk.sh" "$seat" $mid -157.5 2 2>&1 | tail -1 | grep -v arrived
  RLM_SEAT=$seat "$L/../rlm.sh" exec-lua --code "local seat='$seat' local s=game.surfaces[1] local ok,bad=0,{} for x=$lo,$hi,2 do if not s.find_entities_filtered{position={x,-161},radius=0.3,name='straight-rail'}[1] then local k,r=pcall(remote.call,'game_bot','build',{seat=seat,name='rail',x=x,y=-161,direction='east'}) if k and type(r)=='table' and r.built then ok=ok+1 else bad[#bad+1]=x..':'..(k and serpent.line(r) or tostring(r)):sub(1,60) end end end rcon.print('window $lo..$hi built '..ok..' fail '..table.concat(bad,' '))" | jq -r .output
  [ $hi -ge $xt ] && break
done
