#!/usr/bin/env bash
# act.sh VERB SEAT [key=value ...] — one realm call over the gateway's HTTP /invoke.
# Skips the awm CLI's ~0.5s startup. Numbers stay numbers, everything else is a string.
#   lib/act.sh insert seat-1234 x=-22 y=-45 name=coal count=50
set -euo pipefail
verb=$1; seat=$2; shift 2
args=$(jq -n --arg seat "$seat" '{seat_id:$seat}')
for kv in "$@"; do
  k=${kv%%=*}; v=${kv#*=}
  if [[ $v =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
    v=$(printf '%s' "$v" | sed -E 's/^(-?)\./\10./')
    args=$(jq --arg k "$k" --argjson v "$v" '.[$k]=$v' <<<"$args")
  elif [[ $v == true || $v == false ]]; then
    args=$(jq --arg k "$k" --argjson v "$v" '.[$k]=$v' <<<"$args")
  else
    args=$(jq --arg k "$k" --arg v "$v" '.[$k]=$v' <<<"$args")
  fi
done
# Military seats: refuse exec_lua code that could create, move or edit items/entities (two breaches, 2026-10-03).
MIL_SEATS=" seat-ce11af14 seat-a2b6c0e7 seat-2ed242b9 seat-b384e7b5 seat-0f4d0348 "
if [[ $verb == exec_lua && $MIL_SEATS == *" $seat "* ]]; then
  code=$(jq -r '(.code // "") + "\n" + (if .path then .path else "" end)' <<<"$args")
  p=$(jq -r '.path // empty' <<<"$args"); [ -n "$p" ] && [ -f "$p" ] && code+=$'\n'"$(cat "$p")"
  bad=$(grep -oE 'set_stack|cursor_stack[^.]*\.(set|transfer)|\.insert[[:space:]]*[({]|teleport|\.(health|fuel)[[:space:]]*=[^=]|create_entity[^)]*$' <<<"$code" | head -1 || true)
  if [ -z "$bad" ] && grep -q 'create_entity' <<<"$code" && ! grep -qE "create_entity.*(entity-ghost|item-request-proxy)" <<<"$code"; then bad=create_entity; fi
  if [ -n "$bad" ]; then echo "{\"ok\":false,\"error\":\"REFUSED by military guard: '$bad' (no item/entity creation, no inventory writes)\"}"; exit 3; fi
fi
curl -s -XPOST "${AWM_HUB:-http://127.0.0.1:7819}/invoke" -H Content-Type:application/json \
  -d "$(jq -n --arg n "rlm_factorio_$verb" --argjson a "$args" '{name:$n,args:$a}')" | jq -r '.result // .' 
