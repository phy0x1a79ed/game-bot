#!/usr/bin/env bash
# checkpoint-loop.sh SESSION_ID [INTERVAL_S] — the chair's recovery saves: one world save
# every INTERVAL_S (default 1800) named run4-auto-<MMDD-HHMM>, logged to checkpoint.log beside
# this script. Milestone saves keep their own names. Stop with `pkill -f checkpoint-loop.sh`.
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sid=$1; interval=${2:-1800}
while true; do
  name="run4-auto-$(date +%m%d-%H%M)"
  out=$(curl -s -m 120 -X POST http://127.0.0.1:7819/invoke -H 'content-type: application/json' \
    -d "{\"name\":\"rlm_factorio_world_save\",\"args\":{\"session_id\":\"$sid\",\"name\":\"$name\"}}")
  echo "$(date -Iseconds) $name $(echo "$out" | tr -d '\n' | head -c 200)" >> "$LIB/checkpoint.log"
  sleep "$interval"
done
