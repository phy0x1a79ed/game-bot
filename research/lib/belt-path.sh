#!/usr/bin/env bash
# belt-path.sh SEAT 'P={box={x0,y0,x1,y1},s={x,y},sdirs={0..3},g={x,y,dir},open={{x,y}..},block={{x0,y0,x1,y1}..}}'
# Tile coords are integer tile corners (tile (x,y) = centre x+.5,y+.5); dir 0=N 1=E 2=S 3=W. Prints a build list (see belt-path.lua).
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp=$(mktemp --suffix=.lua); awk -v p="local $2" '{ if ($0=="PARAMS") print p; else print }' "$LIB/belt-path.lua" > "$tmp"
"$LIB/act.sh" exec_lua "$1" path="$tmp" | jq -r '.output // .'; rm -f "$tmp"
