#!/usr/bin/env bash
# loop.sh SEAT [INTERVAL_S] -- runs cycle.sh forever, sleeping INTERVAL_S
# (default 600 = ~10 game minutes at normal speed) between runs. Meant to be
# launched with run_in_background; tail the output for the running log.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
interval=${2:-600}
[ -z "$seat" ] && { echo "usage: loop.sh SEAT [interval_s]"; exit 1; }

while true; do
  "$LIB/cycle.sh" "$seat"
  sleep "$interval"
done
