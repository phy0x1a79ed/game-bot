#!/usr/bin/env bash
S=${S:-seat-279b96c0}
# guard-throw.sh ITEM TX TY — the seat throws/deploys one ITEM from its own inventory at (TX,TY) (military.md section 10 Lua; refuses inside worm range)
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib
$L/act.sh exec_lua ${S} code="local p=game.players['${S}'] local c=p.character local ITEM,TX,TY='$1',$2,$3
local ap=prototypes.item[ITEM].capsule_action.attack_parameters
local d=math.sqrt((c.position.x-TX)^2+(c.position.y-TY)^2)
if d>ap.range then rcon.print('TOO FAR '..string.format('%.1f',d)..' > '..ap.range) return end
for _,w in pairs(c.surface.find_entities_filtered{type='turret',force='enemy',position=c.position,radius=45}) do
  local r=prototypes.entity[w.name].attack_parameters.range+1
  if (w.position.x-c.position.x)^2+(w.position.y-c.position.y)^2<r*r then rcon.print('IN WORM RANGE '..w.name) return end end
local before=c.get_item_count(ITEM) local st=c.get_main_inventory().find_item_stack(ITEM)
if not st then rcon.print('NO '..ITEM) return end
p.clear_cursor() p.cursor_stack.transfer_stack(st)
p.use_from_cursor{TX,TY} p.clear_cursor()
rcon.print(string.format('tick %d %s %d -> %d at %s,%s from %.1f hp %.0f',game.tick,ITEM,before,c.get_item_count(ITEM),TX,TY,d,c.health))" | jq -r '.output // .'
