#!/usr/bin/env bash
# belt-trace.sh SEAT X Y [MAXN] — downstream BFS over belts from (X,Y): per-tile lane contents (name@lane+count), splitters, and every inserter picking from the belt with its target.
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib; t=$(mktemp --suffix=.lua)
sed -e "s/START_XY/{$2,$3}/;s/MAXN_V/${4:-400}/" $L/belt-trace.lua > $t; $L/act.sh exec_lua $1 path=$t | jq -r '.output // .'; rm -f $t
