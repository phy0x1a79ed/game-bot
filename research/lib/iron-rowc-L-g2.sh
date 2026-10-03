#!/usr/bin/env bash
# iron-rowc-L-g2.sh SEAT MODE PART: runs one part of lib/iron-rowc-L-g2.lua (MODE check|ghost; PART rowc|feeder|L|g2),
# stripping the other parts so each exec_lua payload stays under 2 KB.
set -euo pipefail
L="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1 mode=$2 part=$3
tmp=$(mktemp --suffix=.lua)
{ echo "MODE='$mode' PART='$part'"
  awk -v p="$part" '
    /^--@PART / { cur=$2; next }
    /^--@TAIL/ { cur="tail"; next }
    (cur=="" || cur==p || cur=="tail") && $0 !~ /^--/ { print }
  ' "$L/iron-rowc-L-g2.lua"; } > "$tmp"
wc -c < "$tmp" >&2
RLM_SEAT=$seat "$L/../rlm.sh" exec-lua --code "$(cat "$tmp")" | jq -r .output
rm -f "$tmp"
