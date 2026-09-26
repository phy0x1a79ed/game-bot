#!/usr/bin/env bash
# walk.sh SEAT X Y [TOL]  — walk to (X,Y), block until within TOL tiles (default 2).
# Retries with a 1-tile nudge when the path is blocked or the walk stalls. Prints final position.
# Uses act.sh (HTTP /invoke, ~0.4s/call) instead of the awm CLI for speed.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; x=$2; y=$3; tol=${4:-2}
nudges=("0 0" "1 0" "0 1" "-1 0" "0 -1" "2 2" "-2 -2")
for n in "${nudges[@]}"; do
  set -- $n; tx=$(echo "$x + $1" | bc); ty=$(echo "$y + $2" | bc)
  "$LIB/act.sh" move "$seat" x="$tx" y="$ty" >/dev/null 2>&1
  still=0; last=""
  for i in $(seq 1 90); do
    sleep 1
    s=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -c '.snapshot | [.position.x, .position.y, .walking]')
    px=$(echo "$s" | jq '.[0]'); py=$(echo "$s" | jq '.[1]'); walking=$(echo "$s" | jq '.[2]')
    d=$(echo "sqrt(($px - $x)^2 + ($py - $y)^2)" | bc -l)
    if (( $(echo "$d <= $tol" | bc -l) )); then echo "arrived $px,$py"; exit 0; fi
    if [ "$walking" = "false" ]; then break; fi
    if [ "$s" = "$last" ]; then still=$((still+1)); [ $still -ge 4 ] && break; else still=0; fi
    last=$s
  done
done
echo "FAILED to reach $x,$y; at $px,$py"; exit 1
