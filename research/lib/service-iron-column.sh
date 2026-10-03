#!/usr/bin/env bash
# service-iron-column.sh SEAT [ignored...]
# The home iron column is belt-fuelled (bank B5) and the steel line's stone
# furnaces are retired, so this only rescues any burner furnace or drill in the
# home iron area and bank 2 that has under 3 fuel. Belt-fed furnaces idle at about 5, so the rescue stays idle
# while their belts keep up.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
[ -z "$seat" ] && { echo "usage: service-iron-column.sh SEAT"; exit 1; }

echo "== enemy check =="
LUA_ENEMY_CHECK='local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={-23,-53},radius=150}) do n=n+1 end rcon.print(n)'
enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_ENEMY_CHECK" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
echo "enemies within 150 of column: ${enemies:-0}"
if [ "${enemies:-0}" != "0" ]; then
  echo "ABORT: enemies detected near the iron column, not walking in."
  exit 1
fi

total_coal_in=0

low=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "local o={} for _,e in pairs(game.surfaces[1].find_entities_filtered{area={{-50,-70},{45,-25}},type={'furnace','mining-drill'}}) do local fi=e.get_fuel_inventory() if fi then local c=fi.get_item_count() if c<3 then local q=game.surfaces[1].find_non_colliding_position('character',e.position,4,0.5) if q then o[#o+1]=string.format('%s,%.1f,%.1f,%d,%.1f,%.1f',e.name,e.position.x,e.position.y,c,q.x,q.y) end end end end rcon.print(table.concat(o,';'))" 2>/dev/null | jq -r '.output // ""' | tr -d '[:space:]')
sweep_in=0
if [ -n "$low" ]; then
  IFS=';' read -ra lows <<< "$low"
  for it in "${lows[@]}"; do
    IFS=',' read -r nm ex ey lvl sx sy <<< "$it"
    "$LIB/walk.sh" "$seat" "$sx" "$sy" 1 >/dev/null 2>&1
    got=$("$LIB/act.sh" insert "$seat" x="$ex" y="$ey" name=coal count=$((50 - lvl)) target="$nm" 2>/dev/null | jq -r '.inserted // 0')
    [ "${got:-0}" = "0" ] && echo "  sweep: $nm ($ex,$ey) at $lvl coal: insert failed"
    sweep_in=$((sweep_in + got))
  done
fi
total_coal_in=$((total_coal_in + sweep_in))
echo "sweep (burner machines under 3 coal): +${sweep_in} coal"
echo "TOTAL: coal inserted=$total_coal_in"
