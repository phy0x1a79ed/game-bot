#!/usr/bin/env bash
# fluid-net.sh SEAT X Y — count the entities of the fluid system containing the fluid entity at (X,Y) (geometric flood; pumps are boundaries). The freeze limit is ~110.
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib; t=$(mktemp --suffix=.lua)
sed -e "s/START_XY/{$2,$3}/" $L/fluid-net.lua > $t; $L/act.sh exec_lua $1 path=$t | jq -r '.output // .'; rm -f $t
