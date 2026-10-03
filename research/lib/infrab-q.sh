#!/usr/bin/env bash
# infrab-q.sh FILE.lua | -  — read-only query on the read seat seat-5d1d9d1c (file path, or lua code on stdin with -)
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib
if [ "$1" = - ]; then t=$(mktemp --suffix=.lua); cat > $t; $L/act.sh exec_lua seat-5d1d9d1c path=$t | jq -r '.output // .'; rm -f $t
else $L/act.sh exec_lua seat-5d1d9d1c path=$1 | jq -r '.output // .'; fi
