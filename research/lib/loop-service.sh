#!/usr/bin/env bash
# loop-service.sh SEAT [INTERVAL_S]
# Standing iron-column maintenance loop (2026-09-26, replaces hand-running
# service-iron-column.sh): each cycle, top up coal from ring1 if low, run one
# full service-iron-column.sh sweep, then sleep INTERVAL_S (default 600s =
# ~10 game minutes at 1x speed) and repeat forever. Logs each cycle to
# loop-service.log beside this script. Stop with `kill <pid>` (see the pid
# this script echoes on start, or `pgrep -f loop-service.sh`).
#
# Coal top-up: takes up to 60 coal from each of ring1's 4 chests whenever this
# seat's on-hand coal drops under COAL_FLOOR (default 150) -- never drains
# below the ring's own floor since it only ever asks for a bounded amount
# (diary rule: leave >=20 per chest, ring1 chests run in the hundreds).
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
interval=${2:-600}
[ -z "$seat" ] && { echo "usage: loop-service.sh SEAT [interval_s]"; exit 1; }

COAL_FLOOR=150
RING_STOPS=(
  "69 -44 69.5 -42.5 60"
  "73 -40.5 72.5 -40.5 60"
  "71 -36.5 70.5 -37.5 60"
  "66 -39 67.5 -39.5 60"
)

echo "loop-service.sh started for $seat, interval=${interval}s, pid=$$"

while true; do
  echo "=== cycle $(date -Iseconds) ==="
  have_coal=$("$LIB/act.sh" observe "$seat" radius=1 | jq -r '.snapshot.inventory["coal"] // 0')
  echo "coal on hand: $have_coal"
  if [ "${have_coal:-0}" -lt "$COAL_FLOOR" ] 2>/dev/null; then
    echo "-- coal low, running ring1 top-up --"
    for s in "${RING_STOPS[@]}"; do
      set -- $s; ax=$1; ay=$2; cx=$3; cy=$4; cnt=$5
      "$LIB/walk.sh" "$seat" "$ax" "$ay" 3 >/dev/null
      got=$("$LIB/act.sh" take "$seat" x="$cx" y="$cy" name=coal count="$cnt" target=iron-chest | jq -r '.taken // 0')
      echo "  ring chest ($cx,$cy): +${got} coal"
    done
  fi
  "$LIB/service-iron-column.sh" "$seat" 40 60
  echo "=== cycle done, sleeping ${interval}s ==="
  sleep "$interval"
done
