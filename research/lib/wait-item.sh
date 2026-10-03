#!/usr/bin/env bash
# wait-item.sh SEAT ITEM N [MAXSEC] — poll the seat's inventory every 10 s until it holds N of ITEM (or MAXSEC passes); prints the count.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; item=$2; n=$3; max=${4:-300}; t=0
while :; do
  c=$("$LIB/act.sh" exec_lua "$seat" code="rcon.print(player.get_main_inventory().get_item_count('$item'))" | jq -r .output)
  if [ "$c" -ge "$n" ] || [ $t -ge $max ]; then echo "$item $c after ${t}s"; exit 0; fi
  sleep 10; t=$((t+10))
done
