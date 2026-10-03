#!/usr/bin/env bash
# Run one part of copper-ab.lua: copper-ab.sh SEAT PART [LO HI] ; sends header + that part + tail (check mode unless MODE=ghost GHOST_OK=true in env).
set -euo pipefail
R=/home/tony/agentic_workspace/projects/game-bot/factorio/research
SEAT=$1; PART=$2; LO=${3:-}; HI=${4:-}
F=$R/lib/copper-ab.lua
{
  echo "PART='$PART' MODE='${MODE:-check}' GHOST_OK=${GHOST_OK:-false}"
  [ -n "$LO" ] && echo "LO=$LO HI=$HI"
  awk -v p="$PART" '
    /^-- @PART/ {mode = ($3==p) ? "part" : "skip"; next}
    /^-- @TAIL/ {mode = "tail"; next}
    mode=="" || mode=="part" || mode=="tail" {print}' "$F"
} > /tmp/copper-ab-$PART.lua
echo "payload $(wc -c </tmp/copper-ab-$PART.lua) bytes raw, $(gzip -c /tmp/copper-ab-$PART.lua | wc -c) gz" >&2
RLM_SEAT=$SEAT $R/rlm.sh exec-lua --code "$(cat /tmp/copper-ab-$PART.lua)" | jq -r .output
