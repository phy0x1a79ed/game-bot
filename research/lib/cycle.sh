#!/usr/bin/env bash
# cycle.sh SEAT -- one full defense/copper/power cycle: patrol scan, copper
# sweep+delivery, boiler feed top-up. Run this instead of hand-running each
# script separately. Intended cadence: every ~10 game minutes (~600s real
# time at normal game speed). See loop.sh to run it unattended.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
[ -z "$seat" ] && { echo "usage: cycle.sh SEAT"; exit 1; }

echo "===== cycle $(date -u +%H:%M:%S) ====="
echo "--- patrol ---"
"$LIB/patrol.sh" "$seat"
echo "--- copper ---"
"$LIB/service-copper.sh" "$seat"
echo "--- power ---"
"$LIB/service-power.sh" "$seat"
echo "===== cycle done ====="
