#!/usr/bin/env bash
S=${S:-seat-279b96c0}
# guard-enemy.sh X Y [R] — enemy units/structures within R (default 45) of (X,Y), plus the seat's hp and position
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib
$L/act.sh exec_lua ${S} code="local s=game.surfaces[1] local c=game.players['${S}'].character local t={} for _,e in pairs(s.find_entities_filtered{force='enemy',position={$1,$2},radius=${3:-45}}) do local k=e.name t[k]=(t[k] or 0)+1 end local o={} for k,v in pairs(t) do o[#o+1]=k..':'..v end rcon.print(string.format('tick %d seat (%.0f,%.0f) hp %.0f | ',game.tick,c.position.x,c.position.y,c.health)..table.concat(o,' '))" | jq -r '.output // .'
