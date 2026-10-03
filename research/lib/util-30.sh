#!/usr/bin/env bash
# util-30.sh SEAT check|place|recipes FILE... — run utility-30 layout files (council/builder2/util-30.md) on one seat; several FILEs run as one union.
# Composes the layout bodies + util-30-run.lua (+ util-30-check.lua in check mode), comments stripped. UNION=1 runs all files in one script (self-overlap, power, pole links across files).
LIB=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib; seat=$1; mode=$2; shift 2
t=$(mktemp --suffix=.lua)
if [ "$mode" = check ]; then chk="$LIB/util-30-check.lua"; else chk=/dev/null; fi
{
  echo "local MODE = '$mode'"; echo "local s = game.surfaces[1]"
  echo "local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west"
  echo "local U, AREA = {}, {{158, -14}, {292, 90}}"
  for f in "$@"; do
    echo "do"; echo "local L = {}"
    awk '/^-- RUNNER/{exit} /^local (MODE|s|N, E, S, W|AREA) /{next} {print}' "$f"
    echo "for _, e in pairs(L) do U[#U + 1] = e end"; echo "end"
  done
  echo "local L = U"
  awk -v chk="$chk" '{ if($0 ~ /^-- CHECK/){while((getline m < chk)>0) print m} else print }' "$LIB/util-30-run.lua" | sed '1,/^-- ===== run =====/{/^local MODE/d}'
} | grep -v '^\s*--' | sed -e 's/^\s*//' -e '/^$/d' > "$t"
echo "payload $(wc -c < "$t") bytes" >&2
RLM_SEAT=${RLM_SEAT:-$seat} /home/tony/agentic_workspace/projects/game-bot/factorio/research/rlm.sh exec-lua --code "$(cat "$t")" | jq -r '.output // .'; rm -f "$t"
