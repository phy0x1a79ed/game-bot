#!/usr/bin/env bash
# steel-belt.sh SEAT PART MODE — run lib/steel-belt.lua part 1|2 as check|place.
LIB=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib; t=$(mktemp --suffix=.lua)
sed "s/PART_ARG/$2/" "$LIB/steel-belt.lua" > "$t.in"
"$LIB/redesign-ghosts.sh" "$1" "$t.in" "$3"; rm -f "$t" "$t.in"
