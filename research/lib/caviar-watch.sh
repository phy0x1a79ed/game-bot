#!/usr/bin/env bash
# Stream the federation board and print one line per event on a card that involves caviar.
# Usage: caviar-watch.sh [last-event-id]
set -u
env_file=${AWM_ENV_FILE:-$HOME/agentic_workspace/.awm/env}
url=$(sed -n 's/^AWM_BOARD_URL=//p' "$env_file" | tail -1)
token=$(sed -n 's/^AWM_BOARD_TOKEN=//p' "$env_file" | tail -1)
[ -n "$url" ] && [ -n "$token" ] || { echo "caviar-watch: AWM_BOARD_URL or AWM_BOARD_TOKEN missing in $env_file"; exit 1; }
cursor=${1:-}
state=${CAVIAR_WATCH_STATE:-${XDG_RUNTIME_DIR:-/tmp}/caviar-watch.cursor}
[ -z "$cursor" ] && [ -s "$state" ] && cursor=$(cat "$state")

while true; do
  hdr=(-H "Accept: text/event-stream")
  [ -n "$cursor" ] && hdr+=(-H "Last-Event-ID: $cursor")
  curl -sN --max-time 3600 -A "curl/caviar-watch" -K <(printf 'header = "Authorization: Bearer %s"\n' "$token") "${hdr[@]}" "$url/board/stream" |
  python3 -u -c '
import json, sys
state = sys.argv[1]
eid, etype, data = None, "message", []
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "":
        if eid is not None:
            open(state, "w").write(eid)
            if data:
                try:
                    card = json.loads("\n".join(data))
                except ValueError:
                    card = None
                if isinstance(card, dict):
                    sender = (card.get("sender") or {}).get("swarm", "")
                    if "caviar" in (sender, card.get("recipient"), card.get("claimant")):
                        msg = card.get("message") or {}
                        who = (msg.get("sender") or {}).get("swarm", sender)
                        text = (msg.get("body") or card.get("title") or "").replace("\n", " ")[:300]
                        cid, seq = str(card.get("id", ""))[:8], msg.get("seq", "-")
                        print(f"{etype} card={cid} seq={seq} from={who}: {text}", flush=True)
        eid, etype, data = None, "message", []
        continue
    if line.startswith(":"):
        continue
    field, _, value = line.partition(":")
    value = value[1:] if value.startswith(" ") else value
    if field == "id": eid = value
    elif field == "event": etype = value
    elif field == "data": data.append(value)
' "$state"
  echo "caviar-watch: stream ended (curl rc=${PIPESTATUS[0]}), reconnecting" >&2
  [ -s "$state" ] && cursor=$(cat "$state")
  sleep 5
done
