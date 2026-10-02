#!/usr/bin/env bash
# ascii-map.sh SEAT X0 Y0 X1 Y1 — ASCII map of the box [X0,X1) x [Y0,Y1). Column header = x digits (tens, units).
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; tmp=$(mktemp --suffix=.lua)
sed -e "s/X0/$2/;s/Y0/$3/;s/X1/$4/;s/Y1/$5/" "$LIB/ascii-map.lua" > "$tmp"
"$LIB/act.sh" exec_lua "$seat" path="$tmp" | jq -r '.output // .'; rm -f "$tmp"
