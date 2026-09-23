#!/usr/bin/env bash
# Poll observe-events until an 'arrived' or 'path_blocked' event drains, or
# timeout. body-move is async (pathfinded); this is the recommended wait loop.
#
# Usage: ./lib/wait-arrive.sh [timeout_seconds] [poll_seconds]
set -euo pipefail
cd "$(dirname "$0")/.."
TIMEOUT="${1:-60}"
POLL="${2:-2}"
elapsed=0
while [ "$elapsed" -lt "$TIMEOUT" ]; do
  out="$(./rlm.sh observe-events)"
  if echo "$out" | grep -q '"arrived"'; then
    echo "$out"
    exit 0
  fi
  if echo "$out" | grep -q '"path_blocked"'; then
    echo "$out"
    exit 2
  fi
  sleep "$POLL"
  elapsed=$((elapsed + POLL))
done
echo "TIMEOUT after ${TIMEOUT}s, last events:"
echo "$out"
exit 1
