#!/usr/bin/env bash
# industry-mineat.sh X Y NAME — mine entity NAME at X,Y from where the seat stands; waits until gone (no walk)
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib; S=seat-f8c483e7
$L/act.sh mine $S x=$1 y=$2 | jq -c '{ok,mining,error}' | grep -v '"ok":true' 
for i in $(seq 1 16); do sleep 0.7
 n=$($L/act.sh exec_lua $S code="rcon.print(#game.surfaces[1].find_entities_filtered{name='$3',position={$1,$2},radius=0.3})" | jq -r .output | tr -d '\n')
 [ "$n" = "0" ] && { echo "gone $3 $1,$2"; exit 0; }
done; echo "STILL $3 $1,$2"; exit 1
