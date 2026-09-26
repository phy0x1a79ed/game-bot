#!/usr/bin/env bash
# upkeep.sh SEAT [INTERVAL_S]
# The unified maintenance loop for the defense/upkeep lane (2026-09-26 role
# change): one pass covers coal hauling, the iron column, copper, power
# (boiler + ammo assembler), the green-science-line input chests, the stone
# drill, and turret ammo top-ups -- then sleeps INTERVAL_S (default 600 =
# ~10 game minutes at 1x) and repeats. Logs to upkeep.log beside this script.
# Stop with `kill <pid>` (pid is echoed on start, or `pgrep -f upkeep.sh`).
#
# Coordinates owned (see BOARD.md for full history):
#   coal ring 1: 4 chests around (67-73,-37 to -44)
#   iron column: see service-iron-column.sh header
#   copper modules 2-6: see service-copper.sh header
#   boiler feed (-47.5,-8.5), ammo assembler in/out (-40.5,-4.5)/(-34.5,-4.5)
#   green-line chests: copper(-46.5,-2.5), iron(-42.5,-2.5)/(-38.5,-2.5)/
#     (-34.5,-2.5)/(-30.5,-2.5)
#   stone drill (60,-30) + chest (59.5,-31.5)
#   red-asm copper chests (-42.5,-8.5)/(-34.5,-8.5) -- serviced inside
#     service-copper.sh's delivery step
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
interval=${2:-600}
[ -z "$seat" ] && { echo "usage: upkeep.sh SEAT [interval_s]"; exit 1; }

COAL_FLOOR=150
RING_STOPS=(
  "69 -44 69.5 -42.5 60"
  "73 -40.5 72.5 -40.5 60"
  "71 -36.5 70.5 -37.5 60"
  "66 -39 67.5 -39.5 60"
)

GREEN_CHESTS=(
  "-46.5 -2.5 copper-plate 200"
  "-42.5 -2.5 iron-plate 300"
  "-38.5 -2.5 iron-plate 300"
  "-34.5 -2.5 iron-plate 300"
  "-30.5 -2.5 iron-plate 300"
)

echo "upkeep.sh started for $seat, interval=${interval}s, pid=$$"

# coal_topup: haul from ring1 up to COAL_FLOOR coal-on-hand, if not already
# there. Called before EVERY section that spends coal (iron column, copper,
# stone drill) -- each section can fully drain what an earlier section left,
# so a single haul at the top of the pass is not enough (2026-09-26: this is
# what starved copper modules 5/6's drills and output inserters dry while the
# iron column silently ate the whole coal-check haul first).
coal_topup() {
  have_coal=$("$LIB/act.sh" observe "$seat" radius=1 | jq -r '.snapshot.inventory["coal"] // 0')
  echo "coal on hand: $have_coal"
  if [ "${have_coal:-0}" -lt "$COAL_FLOOR" ] 2>/dev/null; then
    LUA_CHECK='local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={70,-40},radius=60}) do n=n+1 end rcon.print(n)'
    enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_CHECK" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
    if [ "${enemies:-0}" = "0" ]; then
      for s in "${RING_STOPS[@]}"; do
        set -- $s; ax=$1; ay=$2; cx=$3; cy=$4; cnt=$5
        "$LIB/walk.sh" "$seat" "$ax" "$ay" 3 >/dev/null
        got=$("$LIB/act.sh" take "$seat" x="$cx" y="$cy" name=coal count="$cnt" target=iron-chest 2>/dev/null | jq -r '.taken // 0')
        echo "  ring chest ($cx,$cy): +${got} coal"
      done
    else
      echo "  enemies near ring, skipping coal-run this pass"
    fi
  fi
}

while true; do
  t0=$(date +%s)
  echo "=== cycle $(date -Iseconds) ==="

  echo "-- coal check (pre iron-column) --"
  coal_topup

  echo "-- iron column --"
  "$LIB/service-iron-column.sh" "$seat" 40 60

  echo "-- coal check (pre copper) --"
  coal_topup

  echo "-- copper --"
  "$LIB/service-copper.sh" "$seat"

  echo "-- power (boiler + ammo assembler) --"
  "$LIB/service-power.sh" "$seat"

  echo "-- green-line chests --"
  LUA_ENEMY='local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={-38,-2},radius=60}) do n=n+1 end rcon.print(n)'
  enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_ENEMY" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
  if [ "${enemies:-0}" = "0" ]; then
    for g in "${GREEN_CHESTS[@]}"; do
      set -- $g; gx=$1; gy=$2; item=$3; cap=$4
      lvl=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "local c=game.surfaces[\"nauvis\"].find_entity(\"iron-chest\",{$gx,$gy}) rcon.print(c and c.get_inventory(defines.inventory.chest).get_item_count(\"$item\") or -1)" 2>/dev/null | jq -r '.output // "-1"' | tr -d '[:space:]')
      if [ "${lvl:-0}" -ge 0 ] 2>/dev/null; then
        need=$((cap - lvl))
        if [ "$need" -gt 0 ]; then
          have=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r ".snapshot.inventory[\"$item\"] // 0")
          take=$need; [ "$have" -lt "$take" ] && take=$have
          if [ "$take" -gt 0 ]; then
            "$LIB/walk.sh" "$seat" "$gx" "$gy" 3 >/dev/null
            got=$("$LIB/act.sh" insert "$seat" x="$gx" y="$gy" name="$item" count="$take" target=iron-chest 2>/dev/null | jq -r '.inserted // 0')
            echo "  green chest($gx,$gy) $item: was ${lvl}, +${got}"
          else
            echo "  green chest($gx,$gy) $item: was ${lvl}, need ${need} but 0 on hand"
          fi
        fi
      fi
    done
  else
    echo "  enemies near green line, skipping"
  fi

  echo "-- coal check (pre stone-drill) --"
  coal_topup

  echo "-- stone drill --"
  LUA_ENEMY2='local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={60,-30},radius=60}) do n=n+1 end rcon.print(n)'
  enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_ENEMY2" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
  if [ "${enemies:-0}" = "0" ]; then
    have_coal=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot.inventory["coal"] // 0')
    if [ "${have_coal:-0}" -ge 20 ] 2>/dev/null; then
      "$LIB/walk.sh" "$seat" 61 -30 3 >/dev/null
      ins=$("$LIB/act.sh" insert "$seat" x=60 y=-30 name=coal count=30 target=burner-mining-drill 2>/dev/null | jq -r '.inserted // 0')
      echo "  stone drill(60,-30): +${ins} coal"
    fi
  fi

  echo "-- patrol + turret top-up --"
  "$LIB/patrol.sh" "$seat"
  LUA_LOW='
local out = {}
for _, e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="player", name="gun-turret"}) do
  local ammo = e.get_inventory(defines.inventory.turret_ammo).get_item_count()
  if ammo < 20 then out[#out+1] = string.format("%.0f,%.0f", e.position.x, e.position.y) end
end
rcon.print(table.concat(out, ";"))
'
  low=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_LOW" 2>/dev/null | jq -r '.output // ""' | tr -d '[:space:]')
  if [ -n "$low" ]; then
    IFS=';' read -ra spots <<< "$low"
    for spot in "${spots[@]}"; do
      IFS=',' read -r tx ty <<< "$spot"
      have_mag=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot.inventory["firearm-magazine"] // 0')
      if [ "${have_mag:-0}" -gt 0 ] 2>/dev/null; then
        "$LIB/walk.sh" "$seat" "$tx" "$ty" 4 >/dev/null
        got=$("$LIB/act.sh" insert "$seat" x="$tx" y="$ty" name=firearm-magazine count=20 target=gun-turret 2>/dev/null | jq -r '.inserted // 0')
        echo "  topped turret($tx,$ty): +${got} magazines"
      fi
    done
  fi

  t1=$(date +%s)
  echo "=== cycle done in $((t1 - t0))s, sleeping ${interval}s ==="
  sleep "$interval"
done
