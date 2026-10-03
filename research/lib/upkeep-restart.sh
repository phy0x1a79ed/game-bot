#!/usr/bin/env bash
# upkeep-restart.sh SEAT [interval_s]
# Restarts the upkeep loop so edits to upkeep.sh take effect: bash parses the
# whole while-loop up front, so a running loop never sees them. Matches pids
# by exact argv rather than pkill -f, which also matches the shell running it.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
interval=${2:-300}
[ -z "$seat" ] && { echo "usage: upkeep-restart.sh SEAT [interval_s]"; exit 1; }
bash -n "$LIB/upkeep.sh" || exit 1
for pid in $(ps -eo pid=,args= | awk -v a="bash $LIB/upkeep-runner.sh $seat" -v b="bash $LIB/upkeep.sh $seat" 'index($0,a) || index($0,b) {print $1}'); do
  kill "$pid"
done
sleep 2
setsid nohup "$LIB/upkeep-runner.sh" "$seat" "$interval" >> "$LIB/upkeep.log" 2>&1 < /dev/null &
disown
sleep 2
ps -eo pid=,args= | grep -F "$LIB/upkeep" | grep -v grep
