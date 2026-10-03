#!/usr/bin/env bash
# load.sh — server UPS and each seat's game-call meters (factorio_load): script ms per
# second, current debt, queued calls, over-budget count and the last time it was held.
set -euo pipefail
curl -s -XPOST "${AWM_HUB:-http://127.0.0.1:7819}/invoke" -H Content-Type:application/json \
  -d '{"name":"rlm_factorio_load","args":{}}' | jq -r '(.result // .) | (if type == "string" then fromjson else . end) | "ups \(.ups) paused \(.paused)",
  (.keys | to_entries[] | "\(.key)\tms/s \(.value.ms_per_s)\tdebt \(.value.debt_ms)\tqueued \(.value.queued)\tover \(.value.over_budget)\tlast_hold \(.value.last_hold // "-" | tostring)")'
