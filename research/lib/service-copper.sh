#!/usr/bin/env bash
# service-copper.sh SEAT [COAL_FOR_MODULE2_CHEST]
# Sweeps the 3 active copper modules (2026-09-26, post-collapse-of-module-1
# rebuild), refuels the 2 hand-fed ones, tops module 2's self-fuel coal chest,
# then delivers collected copper-plate FIRST to the red-science-line copper
# input chests (-42.5,-8.5)/(-34.5,-8.5) up to 200 each, remainder to the
# shared depot (0.5,-19.5). Safe to call repeatedly.
#
# Modules:
#   module2 (self-fuelling): drill(20,57)/furnace(22,57), coal chest(17,57)
#     feeds both via inserters; output inserter+chest at (22.5,58.5)/(22.5,59.5)
#   module3 (hand-fed, module-1 rebuild): drill(18,60)/furnace(20,60),
#     output inserter+chest at (20.5,61.5)/(20.5,62.5)
#   module4 (hand-fed, new): drill(12,60)/furnace(14,60),
#     output inserter+chest at (14.5,61.5)/(14.5,62.5)
#   module5 (hand-fed, new): drill(12,54)/furnace(14,54),
#     output inserter+chest at (14.5,55.5)/(14.5,56.5)
#   module6 (hand-fed, new): drill(18,54)/furnace(20,54),
#     output inserter+chest at (20.5,52.5,dir=south)/(20.5,51.5) -- north side,
#     south side collides with module 2's drill
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
coal_for_chest=${2:-0}
[ -z "$seat" ] && { echo "usage: service-copper.sh SEAT [coal_for_module2_chest]"; exit 1; }

echo "== enemy check =="
LUA_CHECK='local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={16,58},radius=60}) do n=n+1 end rcon.print(n)'
enemies=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_CHECK" 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
echo "enemies within 60 of copper field: ${enemies:-0}"
if [ "${enemies:-0}" != "0" ]; then
  echo "ABORT: enemies detected, not proceeding."
  exit 1
fi

total=0

echo "== module 2 (self-fuelling) =="
"$LIB/walk.sh" "$seat" 20 55 6 >/dev/null
if [ "$coal_for_chest" -gt 0 ]; then
  "$LIB/act.sh" insert "$seat" x=17 y=57 name=coal count="$coal_for_chest" target=iron-chest >/dev/null 2>&1
fi
"$LIB/act.sh" insert "$seat" x=22.5 y=58.5 name=coal count=20 target=burner-inserter >/dev/null 2>&1
t=$("$LIB/act.sh" take "$seat" x=22.5 y=59.5 name=copper-plate target=iron-chest 2>/dev/null | jq -r '.taken // 0')
total=$((total + t))
echo "module2 output chest(22.5,59.5): +${t} copper-plate"

echo "== module 3 (hand-fed, drill 18,60 / furnace 20,60) =="
"$LIB/walk.sh" "$seat" 16 62 4 >/dev/null
d=$("$LIB/act.sh" insert "$seat" x=18 y=60 name=coal count=50 target=burner-mining-drill 2>/dev/null | jq -r '.inserted // 0')
f=$("$LIB/act.sh" insert "$seat" x=20 y=60 name=coal count=50 target=stone-furnace 2>/dev/null | jq -r '.inserted // 0')
"$LIB/act.sh" insert "$seat" x=20.5 y=61.5 name=coal count=20 target=burner-inserter >/dev/null 2>&1
t=$("$LIB/act.sh" take "$seat" x=20.5 y=62.5 name=copper-plate target=iron-chest 2>/dev/null | jq -r '.taken // 0')
total=$((total + t))
echo "module3: +${d} coal drill, +${f} coal furnace, +${t} copper-plate from (20.5,62.5)"

echo "== module 4 (hand-fed, drill 12,60 / furnace 14,60) =="
d=$("$LIB/act.sh" insert "$seat" x=12 y=60 name=coal count=50 target=burner-mining-drill 2>/dev/null | jq -r '.inserted // 0')
f=$("$LIB/act.sh" insert "$seat" x=14 y=60 name=coal count=50 target=stone-furnace 2>/dev/null | jq -r '.inserted // 0')
"$LIB/act.sh" insert "$seat" x=14.5 y=61.5 name=coal count=20 target=burner-inserter >/dev/null 2>&1
t=$("$LIB/act.sh" take "$seat" x=14.5 y=62.5 name=copper-plate target=iron-chest 2>/dev/null | jq -r '.taken // 0')
total=$((total + t))
echo "module4: +${d} coal drill, +${f} coal furnace, +${t} copper-plate from (14.5,62.5)"

echo "== module 5 (hand-fed, drill 12,54 / furnace 14,54) =="
d=$("$LIB/act.sh" insert "$seat" x=12 y=54 name=coal count=50 target=burner-mining-drill 2>/dev/null | jq -r '.inserted // 0')
f=$("$LIB/act.sh" insert "$seat" x=14 y=54 name=coal count=50 target=stone-furnace 2>/dev/null | jq -r '.inserted // 0')
"$LIB/act.sh" insert "$seat" x=14.5 y=55.5 name=coal count=20 target=burner-inserter >/dev/null 2>&1
t=$("$LIB/act.sh" take "$seat" x=14.5 y=56.5 name=copper-plate target=iron-chest 2>/dev/null | jq -r '.taken // 0')
total=$((total + t))
echo "module5: +${d} coal drill, +${f} coal furnace, +${t} copper-plate from (14.5,56.5)"

echo "== module 6 (hand-fed, drill 18,54 / furnace 20,54) =="
d=$("$LIB/act.sh" insert "$seat" x=18 y=54 name=coal count=50 target=burner-mining-drill 2>/dev/null | jq -r '.inserted // 0')
f=$("$LIB/act.sh" insert "$seat" x=20 y=54 name=coal count=50 target=stone-furnace 2>/dev/null | jq -r '.inserted // 0')
"$LIB/act.sh" insert "$seat" x=20.5 y=52.5 name=coal count=20 target=burner-inserter >/dev/null 2>&1
t=$("$LIB/act.sh" take "$seat" x=20.5 y=51.5 name=copper-plate target=iron-chest 2>/dev/null | jq -r '.taken // 0')
total=$((total + t))
echo "module6: +${d} coal drill, +${f} coal furnace, +${t} copper-plate from (20.5,51.5)"

echo "total copper-plate collected this sweep: $total"

if [ "$total" -gt 0 ]; then
  echo "== delivering: red-asm chests first (cap 200 each), then depot =="
  "$LIB/walk.sh" "$seat" -42.5 -8.5 3 >/dev/null
  # read current chest levels to respect the 200 cap
  LUA_LVL='
local function n(pos) local c=game.surfaces["nauvis"].find_entity("iron-chest",pos) return c and c.get_inventory(defines.inventory.chest).get_item_count("copper-plate") or 0 end
rcon.print(n({-42.5,-8.5})..","..n({-34.5,-8.5}))
'
  lvl=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_LVL" 2>/dev/null | jq -r '.output // "0,0"' | tr -d '[:space:]')
  lvl1=${lvl%%,*}; lvl2=${lvl##*,}
  room1=$((200 - lvl1)); [ "$room1" -lt 0 ] && room1=0
  room2=$((200 - lvl2)); [ "$room2" -lt 0 ] && room2=0

  give1=$total; [ "$give1" -gt "$room1" ] && give1=$room1
  if [ "$give1" -gt 0 ]; then
    got=$("$LIB/act.sh" insert "$seat" x=-42.5 y=-8.5 name=copper-plate count="$give1" target=iron-chest 2>/dev/null | jq -r '.inserted // 0')
    echo "red-asm chest(-42.5,-8.5) (was ${lvl1}): +${got}"
    total=$((total - got))
  fi

  if [ "$total" -gt 0 ]; then
    "$LIB/walk.sh" "$seat" -34.5 -8.5 3 >/dev/null
    give2=$total; [ "$give2" -gt "$room2" ] && give2=$room2
    if [ "$give2" -gt 0 ]; then
      got=$("$LIB/act.sh" insert "$seat" x=-34.5 y=-8.5 name=copper-plate count="$give2" target=iron-chest 2>/dev/null | jq -r '.inserted // 0')
      echo "red-asm chest(-34.5,-8.5) (was ${lvl2}): +${got}"
      total=$((total - got))
    fi
  fi

  if [ "$total" -gt 0 ]; then
    "$LIB/walk.sh" "$seat" 0.5 -19.5 3 >/dev/null
    got=$("$LIB/act.sh" insert "$seat" x=0.5 y=-19.5 name=copper-plate count="$total" target=iron-chest 2>/dev/null | jq -r '.inserted // 0')
    echo "depot(0.5,-19.5): +${got}"
  fi
fi

"$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -c '.snapshot.inventory'
