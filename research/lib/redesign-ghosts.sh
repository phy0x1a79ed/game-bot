#!/usr/bin/env bash
# redesign-ghosts.sh SEAT LAYOUT.lua check|place|recipes — run a redesign ghost layout on your own seat.
# Composes LAYOUT (the entity list) + redesign-run.lua (+ redesign-run-check.lua in check mode), comments stripped, payload kept small.
LIB=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib; t=$(mktemp --suffix=.lua)
if [ "$3" = check ]; then chk="$LIB/redesign-run-check.lua"; else chk=/dev/null; fi
awk -v chk="$chk" '/^-- RUNNER/{while((getline l < run)>0){ if(l ~ /^-- CHECK/){while((getline m < chk)>0) print m} else print l } next} {print}' run="$LIB/redesign-run.lua" "$2" \
 | grep -v '^\s*--' | sed -e 's/^\s*//' -e '/^$/d' -e "s/MODE_ARG/'$3'/" > "$t"
echo "payload $(wc -c < "$t") bytes" >&2
"$LIB/act.sh" exec_lua "$1" path="$t" | jq -r '.output // .'; rm -f "$t"
