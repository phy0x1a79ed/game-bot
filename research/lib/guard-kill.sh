#!/usr/bin/env bash
# guard-kill.sh TX TY SX SY [NAME] — kill one spawner at (TX,TY): defender at the seat, poison cloud on it, SMG from stand (SX,SY); bails at seat hp<140
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib; S=${S:-seat-279b96c0}; N=${5:-spawner}
ammo(){ $L/act.sh exec_lua $S code="local c=game.players['$S'].character local a=c.get_inventory(defines.inventory.character_ammo)[1] rcon.print('ammo '..(a.valid_for_read and (a.count-1)*10+a.ammo or 0)..' rounds')" | jq -r .output; }
ammo
$L/act.sh move $S x=$3 y=$4 >/dev/null; sleep 2
$L/act.sh exec_lua $S code="local c=game.players['$S'].character rcon.print(string.format('at %.1f,%.1f',c.position.x,c.position.y))" | jq -r .output
p=$($L/act.sh exec_lua $S code="local c=game.players['$S'].character rcon.print(c.position.x..' '..c.position.y)" | jq -r .output)
$L/guard-throw.sh defender-capsule $p
$L/guard-throw-at.sh poison-capsule $1 $2
$L/act.sh exec_lua $S code="game.players['$S'].shooting_state={state=defines.shooting.shooting_enemies,position={$1,$2}} rcon.print('fire')" | jq -r .output
for i in $(seq 1 12); do sleep 2; o=$($L/guard-readat.sh $1 $2 2); echo "$o"; hp=$(echo "$o" | grep -o 'seat hp [0-9]*' | awk '{print $3}'); [ "$hp" -lt 140 ] && { echo RETREAT; break; }; echo "$o" | grep -q "spawner(" || { echo KILLED; break; }; done
$L/act.sh exec_lua $S code="game.players['$S'].shooting_state={state=defines.shooting.not_shooting} rcon.print('cease')" | jq -r .output
ammo
