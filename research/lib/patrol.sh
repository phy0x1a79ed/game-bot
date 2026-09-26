#!/usr/bin/env bash
# patrol.sh SEAT -- one exec_lua call: every gun-turret's ammo (flags <15),
# enemy units within 200 of (0,-20), and any enemy group within 60 of a known
# polluting site. Read-only. Run every patrol cycle; top up flagged turrets
# by hand afterward with lib/act.sh insert.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
[ -z "$seat" ] && { echo "usage: patrol.sh SEAT"; exit 1; }
RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$(cat "$LIB/patrol.lua")" 2>/dev/null | jq -r '.output // .'
