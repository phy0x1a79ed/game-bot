#!/usr/bin/env bash
# service-copper.sh SEAT
# Fuels the 8 copper-field furnaces (electric drills, belt-fed bus lane) to 50 coal
# each. Copper plates ride the bus belt, so there is nothing to collect. The old
# hand-fed modules 2-9 (and their burner drills/furnaces/chests) are no longer serviced.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
[ -z "$seat" ] && { echo "usage: service-copper.sh SEAT"; exit 1; }

FURNACES=(
  "16 56" "16 59" "16 62" "16 65"
  "21 56" "21 59" "21 62" "21 65"
)
TARGET=50
STAND_X=19.5; STAND_Y=60.5

enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code 'local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={16,58},radius=60}) do n=n+1 end rcon.print(n)' 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
echo "enemies within 60 of copper field: ${enemies:-0}"
[ "${enemies:-0}" != "0" ] && { echo "ABORT: enemies detected"; exit 1; }

levels=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code 'local o={} for _,p in pairs({{16,56},{16,59},{16,62},{16,65},{21,56},{21,59},{21,62},{21,65}}) do local e=game.surfaces["nauvis"].find_entity("stone-furnace",p) o[#o+1]=e and e.get_fuel_inventory().get_item_count("coal") or -1 end rcon.print(table.concat(o,","))' 2>/dev/null | jq -r '.output // ""' | tr -d '[:space:]')
echo "copper furnace coal levels: $levels"
IFS=',' read -ra lv <<< "$levels"
low=0; for l in "${lv[@]}"; do [ "$l" -ge 0 ] && [ "$l" -lt 30 ] && low=1; done
[ "$low" = 0 ] && { echo "all copper furnaces at 30+ coal, skipping"; exit 0; }

"$LIB/walk.sh" "$seat" "$STAND_X" "$STAND_Y" 3 >/dev/null
i=0; total=0
for f in "${FURNACES[@]}"; do
  set -- $f
  need=$(( TARGET - ${lv[$i]:-0} ))
  if [ "${lv[$i]:--1}" -ge 0 ] && [ "$need" -gt 0 ]; then
    got=$("$LIB/act.sh" insert "$seat" x="$1" y="$2" name=coal count="$need" target=stone-furnace 2>/dev/null | jq -r '.inserted // 0')
    total=$((total + got))
  fi
  i=$((i + 1))
done
echo "copper furnaces: +${total} coal"
