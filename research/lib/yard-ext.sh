#!/usr/bin/env bash
# yard-ext.sh SEAT PART MODE — run lib/yard-ext.lua part 0|1 as check|place.
LIB=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib; t=$(mktemp)
sed "s/PART_ARG/$2/" "$LIB/yard-ext.lua" > "$t.in"
"$LIB/redesign-ghosts.sh" "$1" "$t.in" "$3"; rm -f "$t" "$t.in"
