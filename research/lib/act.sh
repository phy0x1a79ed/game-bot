#!/usr/bin/env bash
# act.sh VERB SEAT [key=value ...] — one realm call over the gateway's HTTP /invoke.
# Skips the awm CLI's ~0.5s startup. Numbers stay numbers, everything else is a string.
#   lib/act.sh insert seat-1234 x=-22 y=-45 name=coal count=50
set -euo pipefail
verb=$1; seat=$2; shift 2
args=$(jq -n --arg seat "$seat" '{seat_id:$seat}')
for kv in "$@"; do
  k=${kv%%=*}; v=${kv#*=}
  if [[ $v =~ ^-?[0-9]+(\.[0-9]+)?$ || $v == true || $v == false ]]; then
    args=$(jq --arg k "$k" --argjson v "$v" '.[$k]=$v' <<<"$args")
  else
    args=$(jq --arg k "$k" --arg v "$v" '.[$k]=$v' <<<"$args")
  fi
done
curl -s -XPOST "${AWM_HUB:-http://127.0.0.1:7819}/invoke" -H Content-Type:application/json \
  -d "$(jq -n --arg n "rlm_factorio_$verb" --argjson a "$args" '{name:$n,args:$a}')" | jq -r '.result // .' 
