#!/usr/bin/env bash
# scan.sh SEAT [--all] [key=value ...] — survey entities with factorio_scan, one entity per line.
# Area: x1= y1= x2= y2=, or radius= (around x= y=, else the seat). Filters: name= type= force=.
# Lists take commas: name=iron-chest,steel-chest  fields=name,position,status.
# Without --all, prints one page (limit= rows, default 200) and the next cursor on stderr.
# With --all, follows cursors to the end. count_only=true prints just the total.
#   lib/scan.sh seat-1234 radius=40 type=assembling-machine fields=name,position,status,recipe
set -euo pipefail
seat=$1; shift
all=0; [ "${1:-}" = --all ] && { all=1; shift; }
args=$(jq -n --arg seat "$seat" '{seat_id:$seat}')
for kv in "$@"; do
  k=${kv%%=*}; v=${kv#*=}
  case $k in
    name|type|fields) args=$(jq --arg k "$k" --arg v "$v" '.[$k]=($v|split(","))' <<<"$args") ;;
    *) if [[ $v =~ ^-?[0-9]*\.?[0-9]+$ || $v == true || $v == false ]]; then
         v=$(printf '%s' "$v" | sed -E 's/^(-?)\./\10./')
         args=$(jq --arg k "$k" --argjson v "$v" '.[$k]=$v' <<<"$args")
       else
         args=$(jq --arg k "$k" --arg v "$v" '.[$k]=$v' <<<"$args")
       fi ;;
  esac
done
while :; do
  r=$(curl -s -XPOST "${AWM_HUB:-http://127.0.0.1:7819}/invoke" -H Content-Type:application/json \
        -d "$(jq -n --argjson a "$args" '{name:"rlm_factorio_scan",args:$a}')" | jq '(.result // .) | if type == "string" then fromjson else . end')
  if ! jq -e 'has("count")' <<<"$r" >/dev/null; then echo "$r" >&2; exit 1; fi
  if jq -e 'has("entities")' <<<"$r" >/dev/null; then jq -c '.entities[]' <<<"$r"; else jq -r .count <<<"$r"; fi
  next=$(jq -r '.next // empty' <<<"$r")
  [ -n "$next" ] || exit 0
  if [ $all = 0 ]; then echo "next=$next" >&2; exit 0; fi
  args=$(jq --arg c "$next" '.cursor=$c' <<<"$args")
done
