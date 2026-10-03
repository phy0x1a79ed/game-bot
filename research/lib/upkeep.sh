#!/usr/bin/env bash
# upkeep.sh SEAT [INTERVAL_S]
# The unified maintenance loop for the defense/upkeep lane (2026-09-26 role
# change): one pass covers coal hauling, the iron column, copper, power
# (boiler rescue + magazine pickup), the stone
# drill, and turret ammo top-ups -- then sleeps INTERVAL_S (default 600 =
# ~10 game minutes at 1x) and repeats. Logs to upkeep.log beside this script.
# Stop with `kill <pid>` (pid is echoed on start, or `pgrep -f upkeep.sh`).
#
# Coordinates owned (see BOARD.md for full history):
#   coal ring 1: 4 chests around (67-73,-37 to -44)
#   iron column: see service-iron-column.sh header
#   copper modules 2-6: see service-copper.sh header
#   ammo assembler output (-34.5,-4.5): magazines for turret top-ups
#   brick line: electric drill (59.5,-28.5) -> stone furnace (59,-31) -> chest (59.5,-33.5)
#   red-asm copper chests (-42.5,-8.5)/(-34.5,-8.5) -- serviced inside
#     service-copper.sh's delivery step
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
interval=${2:-600}
[ -z "$seat" ] && { echo "usage: upkeep.sh SEAT [interval_s]"; exit 1; }

COAL_FLOOR=200
RING_STOPS=(
  "69 -44 69.5 -42.5 60"
  "73 -40.5 72.5 -40.5 60"
  "71 -36.5 70.5 -37.5 60"
  "66 -39 67.5 -39.5 60"
)

echo "upkeep.sh started for $seat, interval=${interval}s, pid=$$"

# coal_topup: haul from ring1 up to COAL_FLOOR coal-on-hand, if not already
# there. Called before EVERY section that spends coal (iron column, copper,
# stone drill) -- each section can fully drain what an earlier section left,
# so a single haul at the top of the pass is not enough (2026-09-26: this is
# what starved copper modules 5/6's drills and output inserters dry while the
# iron column silently ate the whole coal-check haul first).
coal_topup() {
  "$LIB/service-coal.sh" "$seat" "$COAL_FLOOR"
}

while true; do
  t0=$(date +%s)
  echo "=== cycle $(date -Iseconds) ==="

  echo "-- coal check (pre iron-column) --"
  coal_topup

  echo "-- iron column --"
  "$LIB/service-iron-column.sh" "$seat" 40 60 --no-deposit

  echo "-- coal check (pre copper) --"
  coal_topup

  echo "-- copper --"
  "$LIB/service-copper.sh" "$seat"

  echo "-- depot: iron above 1500 on hand --"
  have_iron=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot.inventory["iron-plate"] // 0')
  if [ "${have_iron:-0}" -gt 1700 ] 2>/dev/null; then
    "$LIB/walk.sh" "$seat" 0.5 -21 3 >/dev/null 2>&1
    got=$("$LIB/act.sh" insert "$seat" x=0.5 y=-19.5 name=iron-plate count=$((have_iron - 1500)) target=iron-chest 2>/dev/null | jq -r '.inserted // 0')
    echo "  depot iron +${got}"
  fi

  echo "-- coal check (pre power) --"
  coal_topup

  echo "-- power (boiler rescue + magazine pickup) --"
  "$LIB/service-power.sh" "$seat"

  echo "-- coal check (pre stone-drill) --"
  coal_topup

  echo "-- stone drill --"
  LUA_ENEMY2='local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={60,-30},radius=60}) do n=n+1 end rcon.print(n)'
  enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_ENEMY2" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
  if [ "${enemies:-0}" = "0" ]; then
    have_coal=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot.inventory["coal"] // 0')
    if [ "${have_coal:-0}" -ge 20 ] 2>/dev/null; then
      "$LIB/walk.sh" "$seat" 61 -30 3 >/dev/null
      lvl=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code 'local f=game.surfaces["nauvis"].find_entity("stone-furnace",{59,-31}) rcon.print(f and f.get_fuel_inventory().get_item_count("coal") or -1)' 2>/dev/null | jq -r '.output // "-1"' | tr -d '[:space:]')
      if [ "${lvl:--1}" -ge 0 ] 2>/dev/null && [ "$lvl" -lt 30 ]; then
        ins=$("$LIB/act.sh" insert "$seat" x=59 y=-31 name=coal count=$((50 - lvl)) target=stone-furnace 2>/dev/null | jq -r '.inserted // 0')
        echo "  brick furnace(59,-31): was ${lvl}, +${ins} coal"
      fi
    fi
  fi

  echo "-- coal check (pre blue steel furnaces) --"
  coal_topup

  echo "-- blue modules' steel furnaces --"
  # Modules 2-4 take coal off P's shared lane, which bank 2's plates now crowd.
  for bf in "43 5" "43 32" "79 40" "99 40"; do
    set -- $bf; fx=$1; fy=$2
    read -r lvl sx sy <<< "$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "local f=game.surfaces[1].find_entity('steel-furnace',{$fx,$fy}) if not f then rcon.print('-1 0 0') return end local q=game.surfaces[1].find_non_colliding_position('character',f.position,4,0.5) or f.position rcon.print(string.format('%d %.1f %.1f',f.get_fuel_inventory().get_item_count('coal'),q.x,q.y))" 2>/dev/null | jq -r '.output // "-1 0 0"')"
    if [ "${lvl:--1}" -ge 0 ] 2>/dev/null && [ "$lvl" -lt 30 ]; then
      "$LIB/walk.sh" "$seat" "$sx" "$sy" 2 >/dev/null
      ins=$("$LIB/act.sh" insert "$seat" x="$fx" y="$fy" name=coal count=$((50 - lvl)) target=steel-furnace 2>/dev/null | jq -r '.inserted // 0')
      echo "  steel furnace($fx,$fy): was ${lvl}, +${ins} coal"
    fi
  done

  echo "-- patrol + turret top-up --"
  "$LIB/patrol.sh" "$seat"
  LUA_LOW='
local out = {}
for _, e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="player", name="gun-turret"}) do
  local ammo = e.get_inventory(defines.inventory.turret_ammo).get_item_count()
  local mine = not (e.last_user and e.last_user.name == "Phyberosis") and e.position.x^2 + e.position.y^2 < 230^2
  if mine and ammo < 20 then out[#out+1] = string.format("%.0f,%.0f", e.position.x, e.position.y) end
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

  echo "-- repair --"
  "$LIB/repair.sh" "$seat" 10

  t1=$(date +%s)
  echo "=== cycle done in $((t1 - t0))s, sleeping ${interval}s ==="
  sleep "$interval"
done
