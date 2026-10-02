#!/usr/bin/env bash
# ammo.sh SEAT [TARGET=25]
# Tops every gun turret below TARGET magazines up to TARGET from the seat's
# inventory, nearest first, stopping when the magazines run out.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; target=${2:-25}
lua() { RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$1" 2>/dev/null | jq -r '.output // ""'; }
list=$(lua "local o={} local p=player.position for _,e in pairs(game.surfaces[1].find_entities_filtered{force='player',name='gun-turret'}) do local a=e.get_inventory(defines.inventory.turret_ammo).get_item_count() if a<$target then o[#o+1]=string.format('%.1f,%.1f,%d,%.0f',e.position.x,e.position.y,a,(e.position.x-p.x)^2+(e.position.y-p.y)^2) end end table.sort(o,function(a,b) return tonumber(a:match('[^,]*\$'))<tonumber(b:match('[^,]*\$')) end) rcon.print(table.concat(o,';'))")
[ -z "$list" ] && { echo "all turrets >= $target"; exit 0; }
IFS=';' read -ra items <<< "$list"
for it in "${items[@]}"; do
  IFS=',' read -r x y have _ <<< "$it"
  mags=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot.inventory["firearm-magazine"] // 0')
  [ "${mags:-0}" -le 0 ] && { echo "out of magazines"; break; }
  need=$((target - have)); [ "$need" -gt "$mags" ] && need=$mags
  "$LIB/walk.sh" "$seat" "$x" "$y" 5 >/dev/null 2>&1
  got=$("$LIB/act.sh" insert "$seat" x="$x" y="$y" name=firearm-magazine count="$need" target=gun-turret 2>/dev/null | jq -r '.inserted // 0')
  echo "turret ($x,$y) had $have: +$got"
done
