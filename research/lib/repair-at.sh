#!/usr/bin/env bash
# repair-at.sh SEAT x,y [x,y ...] — walk to each listed entity and repair it with packs from the seat (no depot trip, no walk-back).
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; shift
lua() { "$LIB/act.sh" exec_lua "$seat" code="$1" 2>/dev/null | jq -r '.output // ""'; }
for xy in "$@"; do
  x=${xy%,*}; y=${xy#*,}
  "$LIB/walk.sh" "$seat" "$x" "$y" 5 >/dev/null 2>&1
  lua "local pos={$x,$y} local pi=player.index
if not (player.cursor_stack.valid_for_read and player.cursor_stack.name=='repair-pack') then
  local inv=player.get_main_inventory() for i=1,#inv do local s=inv[i] if s.valid_for_read and s.name=='repair-pack' then player.cursor_stack.swap_stack(s) break end end
end
local ent for _,e in pairs(game.surfaces[1].find_entities_filtered{force='player',position=pos,radius=0.7}) do if e.type~='character' and e.health and e.health<e.max_health then ent=e break end end
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
  h=""
  for i in $(seq 1 25); do
    sleep 1
    h=$(lua "local o='whole' for _,k in pairs(game.surfaces[1].find_entities_filtered{force='player',position={$x,$y},radius=0.7}) do if k.type~='character' and k.health and k.health<k.max_health then o=string.format('%s %d/%d',k.name,k.health,k.max_health) end end rcon.print(o)")
    [ "$h" = "whole" ] && break
  done
  echo "($x,$y) $h"
done
lua 'player.clear_cursor() rcon.print("ok")' >/dev/null
