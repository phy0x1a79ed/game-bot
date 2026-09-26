#!/usr/bin/env bash
# service-power.sh SEAT [TARGET]
# Keeps the boiler feed chest (-47.5,-8.5) at TARGET coal (default 300),
# pulling the shortfall from coal ring 1's 4 chests while never taking a
# chest below 20. Safe to call repeatedly -- no-ops if the feed is already
# at or above target.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
target=${2:-300}
[ -z "$seat" ] && { echo "usage: service-power.sh SEAT [target]"; exit 1; }

LUA_LVL='
local function n(pos) local c=game.surfaces["nauvis"].find_entity("iron-chest",pos) return c and c.get_inventory(defines.inventory.chest).get_item_count("coal") or 0 end
rcon.print(n({-47.5,-8.5}))
'
have=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_LVL" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
echo "boiler feed chest(-47.5,-8.5): ${have} coal (target ${target})"
need=$((target - have))
if [ "$need" -le 0 ]; then
  echo "already at/above target, nothing to do"
else
  echo "== enemy check =="
  LUA_CHECK='local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={70,-40},radius=60}) do n=n+1 end rcon.print(n)'
  enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_CHECK" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
  if [ "${enemies:-0}" != "0" ]; then
    echo "ABORT: enemies near coal ring, skipping boiler top-up this pass."
  else
    on_hand=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code 'rcon.print(player.get_main_inventory().get_item_count("coal"))' 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
    echo "already carrying ${on_hand:-0} coal"
    need=$((need - on_hand))
    [ "$need" -lt 0 ] && need=0

    echo "shortfall after on-hand coal: ${need} -- pulling from ring 1 (floor 20/chest)"
    RING1=("69.5 -42.5" "72.5 -40.5" "70.5 -37.5" "67.5 -39.5")
    carried=0
    for c in "${RING1[@]}"; do
      [ "$carried" -ge "$need" ] && break
      set -- $c; cx=$1; cy=$2
      "$LIB/walk.sh" "$seat" "$cx" "$cy" 3 >/dev/null
      lvl=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "local c=game.surfaces[\"nauvis\"].find_entity(\"iron-chest\",{$cx,$cy}) rcon.print(c.get_inventory(defines.inventory.chest).get_item_count(\"coal\"))" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
      spare=$((lvl - 20))
      [ "$spare" -lt 0 ] && spare=0
      want=$((need - carried))
      [ "$spare" -gt "$want" ] && spare=$want
      if [ "$spare" -gt 0 ]; then
        got=$("$LIB/act.sh" take "$seat" x="$cx" y="$cy" name=coal count="$spare" target=iron-chest 2>/dev/null | jq -r '.taken // 0')
        carried=$((carried + got))
        echo "chest($cx,$cy) had ${lvl}: took ${got}"
      fi
    done

    total_want=$((on_hand + carried))
    echo "delivering up to ${total_want} coal to boiler feed"
    "$LIB/walk.sh" "$seat" -47.5 -8.5 3 >/dev/null
    got=$("$LIB/act.sh" insert "$seat" x=-47.5 y=-8.5 name=coal count="$total_want" target=iron-chest 2>/dev/null | jq -r '.inserted // 0')
    echo "boiler feed(-47.5,-8.5): +${got} coal"
  fi
fi

echo "== ammo assembler upkeep (power block, same area) =="
"$LIB/walk.sh" "$seat" -38 -4.5 4 >/dev/null
"$LIB/act.sh" insert "$seat" x=-39.5 y=-4.5 name=coal count=5 target=burner-inserter >/dev/null 2>&1
"$LIB/act.sh" insert "$seat" x=-35.5 y=-4.5 name=coal count=5 target=burner-inserter >/dev/null 2>&1
in_lvl=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code 'local c=game.surfaces["nauvis"].find_entity("iron-chest",{-40.5,-4.5}) rcon.print(c.get_inventory(defines.inventory.chest).get_item_count("iron-plate"))' 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
echo "ammo asm input chest(-40.5,-4.5): ${in_lvl} iron (cap 100)"
out_mags=$("$LIB/act.sh" take "$seat" x=-34.5 y=-4.5 name=firearm-magazine target=iron-chest 2>/dev/null | jq -r '.taken // 0')
[ "$out_mags" -gt 0 ] && echo "collected ${out_mags} magazines from ammo asm output chest for turret top-ups"
