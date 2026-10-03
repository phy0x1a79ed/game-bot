#!/usr/bin/env bash
# Usage: ops-audit-belt-gaps.sh [SEAT]. Runs ops-audit-belt-gaps.lua over 50-tile x-bands from -500 to 600 and prints every one-tile belt hole.
L=$(cd "$(dirname "$0")" && pwd); seat=${1:-seat-03ce23d6}
for x0 in $(seq -500 50 550); do
  code=$(sed -e "s/X0_V/$x0/g; s/X1_V/$((x0 + 50))/g" "$L/ops-audit-belt-gaps.lua")
  "$L/act.sh" exec_lua "$seat" code="$code" | jq -r --arg b "$x0" '(.output // .error // "") | split("\n")[] | select(startswith("GAP") or startswith("OVER") or startswith("Cannot")) | "band \($b): \(.)"'
done
