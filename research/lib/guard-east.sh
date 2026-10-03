#!/usr/bin/env bash
# guard-east.sh SEAT [full] — run guard-east.lua; brief (only low/damaged turrets) unless 'full'.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
flag=true; [ "$2" = "full" ] && flag=false
"$LIB/act.sh" exec_lua "$1" code="BRIEF_FLAG=$flag $(cat "$LIB/guard-east.lua")" | jq -r .output
