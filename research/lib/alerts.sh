#!/usr/bin/env bash
# Usage: alerts.sh SEAT [INTERVAL]. Prints NEW/CLEAR alert lines; an alert must persist 2 polls.
# One poll = two calls (alerts.lua machines, alerts-b.lua the rest), each kept near the 15 ms script budget.
seat=$1; interval=${2:-60}
dir=$(cd "$(dirname "$0")" && pwd)
state=$(mktemp -d)
touch "$state/prev" "$state/shown"
while true; do
  cur=$({ "$dir/act.sh" exec_lua "$seat" path="$dir/alerts.lua" budget_ms=30; "$dir/act.sh" exec_lua "$seat" path="$dir/alerts-b.lua" budget_ms=30; } | jq -r '.output // empty' 2>/dev/null | sort -u)
  if [ -f "$dir/upkeep.log" ] && [ -n "$(find "$dir/upkeep.log" -mmin +15)" ]; then
    cur=$(printf '%s\nUPKEEP-STALE upkeep.log unchanged for 15+ min' "$cur" | sort -u)
  fi
  if [ -n "$cur" ] || [ -s "$state/prev" ]; then
    echo "$cur" | grep -v '^$' > "$state/cur"
    comm -12 "$state/cur" "$state/prev" > "$state/stable"
    comm -23 "$state/stable" "$state/shown" | sed 's/^/NEW /'
    comm -23 "$state/shown" "$state/cur" | sed 's/^/CLEAR /'
    comm -12 "$state/shown" "$state/cur" | cat - "$state/stable" | sort -u > "$state/shown.new"
    mv "$state/shown.new" "$state/shown"
    mv "$state/cur" "$state/prev"
  fi
  sleep "$interval"
done
