#!/usr/bin/env bash
# Thin wrapper over the rlm-factorio realm CLI, bound to the live session.
#   ./rlm.sh observe --radius 30
#   ./rlm.sh body-move --x 10 --y -4
set -euo pipefail
AWM=/home/tony/lib/miniforge3/envs/awm/bin/awm
SESSION="${RLM_SESSION:-$(cat "$(dirname "$0")/.session")}"
verb="$1"; shift
exec "$AWM" rlm "factorio-$verb" --session-id "$SESSION" "$@"
