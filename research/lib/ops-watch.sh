#!/usr/bin/env bash
# Usage: ops-watch.sh STATE_DIR [MAX_WAIT_S]
# Prints alert-stream lines and board ALERT lines that are new since the last call,
# waiting up to MAX_WAIT_S (default 600) for the first one. Prints QUIET on timeout.
state=$1; max=${2:-600}
R=/home/tony/agentic_workspace/projects/game-bot/factorio/research
stream=$state/alerts.stream; board=$R/crew/BOARD.md
mkdir -p "$state"; touch "$stream"
[ -f "$state/stream.off" ] || wc -l < "$stream" > "$state/stream.off"
[ -f "$state/board.off" ] || wc -l < "$board" > "$state/board.off"
for ((t = 0; t < max; t += 15)); do
  s0=$(cat "$state/stream.off"); b0=$(cat "$state/board.off")
  s1=$(wc -l < "$stream"); b1=$(wc -l < "$board")
  if [ "$s1" -gt "$s0" ] || [ "$b1" -gt "$b0" ]; then
    tail -n +"$((s0 + 1))" "$stream" | head -n "$((s1 - s0))" | sed 's/^/STREAM /'
    tail -n +"$((b0 + 1))" "$board" | head -n "$((b1 - b0))" | grep -E '\] (ALERT|NEED)' | cut -c1-600 | sed 's/^/BOARD /'
    echo "$s1" > "$state/stream.off"; echo "$b1" > "$state/board.off"
    exit 0
  fi
  sleep 15
done
echo QUIET
