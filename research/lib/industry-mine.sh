#!/usr/bin/env bash
# silo-mine.sh X Y SX SY NAME — walk to stand SX,SY then mine entity NAME at X,Y; waits until gone
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib; S=seat-f8c483e7
$L/walk.sh $S $3 $4 1.0 >/dev/null
$L/act.sh mine $S x=$1 y=$2 | jq -c '{ok,mining,error}'
for i in $(seq 1 12); do sleep 1.5
 n=$($L/act.sh exec_lua $S code="rcon.print(#game.surfaces[1].find_entities_filtered{name='$5',position={$1,$2},radius=0.3})" | jq -r .output | tr -d '\n')
 [ "$n" = "0" ] && { echo "gone $5 $1,$2"; exit 0; }
done; echo "STILL $5 $1,$2"
