#!/usr/bin/env bash
# Usage: alerts.sh SEAT [INTERVAL]. Prints NEW/CLEAR alert lines; an alert must persist 2 polls.
seat=$1; interval=${2:-60}
dir=$(cd "$(dirname "$0")" && pwd)
state=$(mktemp -d)
touch "$state/prev" "$state/shown"
while true; do
  cur=$("$dir/act.sh" exec_lua "$seat" path="$dir/alerts.lua" | jq -r '.output // empty' 2>/dev/null | sort -u)
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
