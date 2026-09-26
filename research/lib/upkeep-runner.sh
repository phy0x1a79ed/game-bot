#!/usr/bin/env bash
# upkeep-runner.sh SEAT [interval_s]
# Restart-on-exit wrapper around upkeep.sh (2026-09-26 14:xx, after upkeep.sh
# silently died and sat dead for ~25 min with nothing noticing until the
# supervisor caught it from ALERTS.log). upkeep.sh's own `while true` loop
# only protects against a normal cycle failing internally -- it does nothing
# if the whole process gets killed or crashes out of the shell entirely. This
# wrapper is the outer safety net: if upkeep.sh ever exits for ANY reason, log
# the exit code and immediately relaunch it, forever.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
interval=${2:-600}
[ -z "$seat" ] && { echo "usage: upkeep-runner.sh SEAT [interval_s]"; exit 1; }

while true; do
  echo "=== upkeep-runner: launching upkeep.sh at $(date -Iseconds) ==="
  "$LIB/upkeep.sh" "$seat" "$interval"
  rc=$?
  echo "=== upkeep-runner: upkeep.sh EXITED with code $rc at $(date -Iseconds) -- relaunching in 5s ==="
  sleep 5
done
