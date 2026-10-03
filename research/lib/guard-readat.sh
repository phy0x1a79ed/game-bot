#!/usr/bin/env bash
S=${S:-seat-279b96c0}
# guard-readat.sh X Y R — tick, enemy structures' hp within R of (X,Y), units within R, seat hp
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib
$L/act.sh exec_lua ${S} code="local s=game.surfaces[1] local o={'tick '..game.tick} for _,e in pairs(s.find_entities_filtered{force='enemy',position={$1,$2},radius=$3,type={'unit-spawner','turret'}}) do o[#o+1]=string.format('%s(%.0f,%.0f)%.0f',e.name:gsub('%-turret',''),e.position.x,e.position.y,e.health) end o[#o+1]='units '..#s.find_entities_filtered{force='enemy',position={$1,$2},radius=$3,type='unit'} local c=game.players['${S}'].character o[#o+1]=string.format('seat hp %.0f at %.0f,%.0f',c.health,c.position.x,c.position.y) rcon.print(table.concat(o,' '))" | jq -r .output
