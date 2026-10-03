#!/usr/bin/env bash
S=${S:-seat-279b96c0}
# guard-targets.sh X Y [R] — enemy structures (hp) and units near (X,Y), seat hp, defenders following, own rally turrets' ammo
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib
$L/act.sh exec_lua ${S} code="local s=game.surfaces[1] local p=game.players['${S}'] local c=p.character local o={}
o[#o+1]=string.format('tick %d seat (%.1f,%.1f) hp %.0f',game.tick,c.position.x,c.position.y,c.health)
for _,e in pairs(s.find_entities_filtered{force='enemy',position={$1,$2},radius=${3:-30},type={'unit-spawner','turret'}}) do o[#o+1]=string.format('  %s (%.0f,%.0f) hp %.0f d %.0f',e.name,e.position.x,e.position.y,e.health,math.sqrt((e.position.x-c.position.x)^2+(e.position.y-c.position.y)^2)) end
local u={} local near=0 for _,e in pairs(s.find_entities_filtered{force='enemy',type='unit',position=c.position,radius=40}) do u[e.name]=(u[e.name] or 0)+1 if (e.position.x-c.position.x)^2+(e.position.y-c.position.y)^2<225 then near=near+1 end end
local t={} for k,v in pairs(u) do t[#t+1]=k..':'..v end o[#o+1]='  units<40: '..table.concat(t,' ')..' (<15: '..near..')'
local f=0 for _,e in pairs(s.find_entities_filtered{name='defender',position=c.position,radius=30}) do f=f+1 end
local tt={} for _,e in pairs(s.find_entities_filtered{name='gun-turret',force='player',position=c.position,radius=30}) do tt[#tt+1]=string.format('(%.0f,%.0f)%dp/%.0fhp',e.position.x,e.position.y,e.get_inventory(1).get_item_count('piercing-rounds-magazine'),e.health) end
o[#o+1]='  defenders '..f..' turrets '..table.concat(tt,' ')..' | poison '..c.get_item_count('poison-capsule')..' def '..c.get_item_count('defender-capsule')..' pierce '..c.get_item_count('piercing-rounds-magazine')
rcon.print(table.concat(o,'\n'))" | jq -r '.output // .'
