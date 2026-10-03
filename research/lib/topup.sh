#!/usr/bin/env bash
# topup.sh SEAT TARGET x,y [x,y ...] — walk to each named gun turret and top it up to TARGET magazines.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; target=$2; shift 2
for xy in "$@"; do
  x=${xy%,*}; y=${xy#*,}
  have=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "local e=game.surfaces[1].find_entities_filtered{name='gun-turret',position={$x,$y},radius=0.5}[1] rcon.print(e and e.get_inventory(defines.inventory.turret_ammo).get_item_count() or -1)" 2>/dev/null | jq -r '.output // "-1"' | tr -d '\n')
  [ "$have" = "-1" ] && { echo "($x,$y) no turret"; continue; }
  mags=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot.inventory["firearm-magazine"] // 0')
  need=$((target - have)); [ "$need" -le 0 ] && { echo "($x,$y) has $have"; continue; }
  [ "$need" -gt "${mags:-0}" ] && need=${mags:-0}
  [ "$need" -le 0 ] && { echo "out of magazines"; break; }
  "$LIB/walk.sh" "$seat" "$x" "$y" 6 >/dev/null 2>&1
  got=$("$LIB/act.sh" insert "$seat" x="$x" y="$y" name=firearm-magazine count="$need" target=gun-turret 2>/dev/null | jq -r '.inserted // 0')
  echo "($x,$y) had $have +$got"
done
