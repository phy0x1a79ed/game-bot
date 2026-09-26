#!/usr/bin/env bash
# coal-run.sh SEAT — walk to both coal rings and take coal, spread across chests,
# leaving >=20 per chest (we ask for a bounded amount, never "take all").
AWM=/home/tony/lib/miniforge3/envs/awm/bin/awm
LIB=/home/tony/.claude/jobs/352ae9b5/tmp/factorio/lib
seat=$1
[ -z "$seat" ] && { echo "usage: coal-run.sh SEAT"; exit 1; }

# approach_x approach_y chest_x chest_y take_count
STOPS=(
  "69 -44 69.5 -42.5 40"
  "73 -40.5 72.5 -40.5 40"
  "71 -36.5 70.5 -37.5 30"
  "66 -39 67.5 -39.5 30"
  "80 -44 80.5 -42.5 40"
  "84 -40.5 83.5 -40.5 40"
  "82 -36.5 81.5 -37.5 40"
  "77 -39 78.5 -39.5 40"
)

total=0
for s in "${STOPS[@]}"; do
  set -- $s; ax=$1; ay=$2; cx=$3; cy=$4; cnt=$5
  $LIB/walk.sh "$seat" "$ax" "$ay" 3 >/dev/null
  got=$($AWM rlm factorio-take --seat-id "$seat" --x "$cx" --y "$cy" --name coal --count "$cnt" --target iron-chest 2>/dev/null | jq -r '.taken // 0')
  total=$((total + got))
  echo "chest ($cx,$cy): took $got coal"
done
echo "TOTAL coal taken this run: $total"
$AWM rlm factorio-observe --seat-id "$seat" --radius 1 2>/dev/null | jq -c '.snapshot.inventory'
