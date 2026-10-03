#!/usr/bin/env bash
# repair.sh SEAT [MAX_TARGETS]
# Repairs every damaged player entity with repair packs from the seat's inventory.
# The engine reads a player's repair_state as per-tick input, so a one-shot
# exec_lua does nothing: this installs a self-removing on_nth_tick handler that
# re-asserts selection + repair_state on one entity until it is whole (or 900
# ticks pass), then returns the pack from the cursor to the inventory.
# Do not run while upkeep.sh is walking the same seat.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; max=${2:-20}
lua() { RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$1" 2>/dev/null | jq -r '.output // ""'; }
list=$(lua 'local o={} local p=player.position for _,e in pairs(game.surfaces[1].find_entities_filtered{force="player"}) do if e.type~="character" and e.health and e.max_health and e.health<e.max_health then o[#o+1]=string.format("%.2f,%.2f,%.1f",e.position.x,e.position.y,(e.position.x-p.x)^2+(e.position.y-p.y)^2) end end table.sort(o,function(a,b) return tonumber(a:match("[^,]*$"))<tonumber(b:match("[^,]*$")) end) rcon.print(table.concat(o,";"))')
[ -z "$list" ] && { echo "nothing damaged"; exit 0; }
packs=$(lua 'rcon.print(player.get_main_inventory().get_item_count("repair-pack"))')
if [ "${packs:-0}" -lt 5 ] 2>/dev/null; then
  "$LIB/walk.sh" "$seat" 0.5 -21 3 >/dev/null 2>&1
  got=$("$LIB/act.sh" take "$seat" x=0.5 y=-19.5 name=repair-pack count=50 target=iron-chest 2>/dev/null | jq -r '.taken // 0')
  echo "repair packs from depot (0.5,-19.5): +${got}"
fi
n=0
IFS=';' read -ra items <<< "$list"
for it in "${items[@]}"; do
  IFS=',' read -r x y _ <<< "$it"
  n=$((n+1)); [ "$n" -gt "$max" ] && break
  packs=$(lua 'rcon.print(player.get_main_inventory().get_item_count("repair-pack") + (player.cursor_stack.valid_for_read and player.cursor_stack.name=="repair-pack" and player.cursor_stack.count or 0))')
  [ "${packs:-0}" -le 0 ] && { echo "out of repair packs"; break; }
  "$LIB/walk.sh" "$seat" "$x" "$y" 5 >/dev/null 2>&1
  lua "local pos={$x,$y} local pi=player.index
if not (player.cursor_stack.valid_for_read and player.cursor_stack.name=='repair-pack') then
  local inv=player.get_main_inventory() for i=1,#inv do local s=inv[i] if s.valid_for_read and s.name=='repair-pack' then player.cursor_stack.swap_stack(s) break end end
end
local ents=game.surfaces[1].find_entities_filtered{force='player',position=pos,radius=0.6}
local ent for _,e in pairs(ents) do if e.type~='character' and e.health and e.health<e.max_health then ent=e break end end
local left=900
script.on_nth_tick(1,function()
  local p=game.get_player(pi) left=left-1
  if left<=0 or not (p and p.valid) or not (ent and ent.valid) or ent.health>=ent.max_health then
    if p and p.valid then p.repair_state={repairing=false,position=pos} end
    script.on_nth_tick(1,nil) return
  end
  p.update_selected_entity(pos) p.repair_state={repairing=true,position=pos}
end)
rcon.print('go')" >/dev/null
  for i in $(seq 1 20); do
    sleep 1
    h=$(lua "local e=game.surfaces[1].find_entities_filtered{force='player',position={$x,$y},radius=0.6} local o='gone' for _,k in pairs(e) do if k.health then o=string.format('%s %d/%d',k.name,k.health,k.max_health) end end rcon.print(o)")
    case "$h" in *gone*) break;; esac
    a=${h##* }; [ "${a%%/*}" = "${a##*/}" ] && break
  done
  echo "($x,$y) $h"
done
lua 'player.clear_cursor() rcon.print("cursor cleared")' >/dev/null
