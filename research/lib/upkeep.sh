#!/usr/bin/env bash
# upkeep.sh SEAT [INTERVAL_S]
# The maintenance loop: repair only. Coal hauls, the iron column burner rescue,
# the boiler rescue and the turret top-ups were cut once belts and robots
# covered them (2026-10-03). Sleeps INTERVAL_S and repeats; logs to upkeep.log
# beside this script. Stop with `kill <pid>` (`pgrep -f upkeep.sh`).
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
interval=${2:-600}
[ -z "$seat" ] && { echo "usage: upkeep.sh SEAT [interval_s]"; exit 1; }

echo "upkeep.sh started for $seat, interval=${interval}s, pid=$$"

while true; do
  t0=$(date +%s)
  echo "=== cycle $(date -Iseconds) ==="

  echo "-- repair --"
  "$LIB/repair.sh" "$seat" 10

  t1=$(date +%s)
  echo "=== cycle done in $((t1 - t0))s, sleeping ${interval}s ==="
  sleep "$interval"
done
