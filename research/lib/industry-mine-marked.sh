#!/usr/bin/env bash
# industry-mine-marked.sh X1 Y1 X2 Y2 — hand-mine every entity marked for deconstruction in the box that is within reach of seat-f8c483e7 (belts give their items at once, robots ferry one item per trip).
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib; S=seat-f8c483e7
$L/act.sh exec_lua $S code="local p=game.get_player('$S').position local o={} for _,e in pairs(game.surfaces[1].find_entities_filtered{area={{$1,$2},{$3,$4}}}) do if e.to_be_deconstructed() and e.type~='item-entity' then local d=((e.position.x-p.x)^2+(e.position.y-p.y)^2)^0.5 if d<9.5 then o[#o+1]=e.position.x..' '..e.position.y..' '..e.name end end end rcon.print(table.concat(o,'\n'))" | jq -r .output | while read x y n; do [ -n "$n" ] && $L/industry-mineat.sh $x $y $n; done
