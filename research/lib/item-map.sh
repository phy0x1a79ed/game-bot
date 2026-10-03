#!/usr/bin/env bash
# item-map.sh SEAT X0 Y0 X1 Y1 — map of what each belt tile carries (legend in item-map.lua).
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; tmp=$(mktemp --suffix=.lua)
sed -e "s/X0/$2/;s/Y0/$3/;s/X1/$4/;s/Y1/$5/" "$LIB/item-map.lua" > "$tmp"
"$LIB/act.sh" exec_lua "$seat" path="$tmp" | jq -r '.output // .'; rm -f "$tmp"
