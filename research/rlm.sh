#!/usr/bin/env bash
# Thin wrapper over the rlm-factorio realm CLI, bound to one seat.
#   RLM_SEAT=seat-1234abcd ./rlm.sh observe --radius 30
# The seat comes from $RLM_SEAT, else from the .seat file beside this script.
set -euo pipefail
AWM=/home/tony/lib/miniforge3/envs/awm/bin/awm
SEAT="${RLM_SEAT:-$(cat "$(dirname "$0")/.seat")}"
verb="$1"; shift
exec "$AWM" rlm "factorio-$verb" --seat-id "$SEAT" "$@"
