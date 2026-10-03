#!/usr/bin/env bash
# walk.sh SEAT X Y [TOL] — walk to (X,Y), block until within TOL tiles (default 2).
# Retries with a 1-tile nudge when the path is blocked or the walk stalls. Prints final position.
# Exit codes: 0 arrived; 1 moved but could not reach the target; 2 STUCK (the seat cannot
# move at all: trapped in a pocket); 3 the seat cannot be observed.
# A stuck seat gets a marker in crew/stuck/<seat> and one board ALERT. While the marker
# exists every walk refuses at once (exit 2), so loops fail fast instead of burning cycles.
# Whoever frees the seat (mine the blocking piece, walk out, rebuild it) may delete the
# marker; the next walk also clears it by itself once the seat has moved off the marked spot.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; x=$2; y=$3; tol=${4:-2}
STUCK_DIR="$LIB/../crew/stuck"; marker="$STUCK_DIR/$seat"
BOARD="$LIB/../crew/BOARD.md"

pos() {
  "$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot | "\(.position.x) \(.position.y) \(.walking)"' 2>/dev/null
}
dist() { echo "sqrt(($1 - $3)^2 + ($2 - $4)^2)" | bc -l; }

read -r sx sy _ <<< "$(pos)"
if [ -z "$sx" ] || [ "$sx" = "null" ]; then echo "UNOBSERVABLE seat $seat"; exit 3; fi

if [ -f "$marker" ]; then
  read -r mx my < "$marker"
  if (( $(echo "$(dist "$sx" "$sy" "$mx" "$my") > 1.5" | bc -l) )); then
    rm -f "$marker"
  else
    echo "STUCK seat $seat at ($sx,$sy): marker $marker; free it, then delete the marker"; exit 2
  fi
fi

px=$sx; py=$sy; misses=0
nudges=("0 0" "1 0" "0 1" "-1 0" "0 -1" "2 2" "-2 -2")
for n in "${nudges[@]}"; do
  set -- $n; tx=$(echo "$x + $1" | bc); ty=$(echo "$y + $2" | bc)
  "$LIB/act.sh" move "$seat" x="$tx" y="$ty" >/dev/null 2>&1
  still=0; last=""
  for i in $(seq 1 90); do
    sleep 1
    read -r cx cy walking <<< "$(pos)"
    if [ -z "$cx" ] || [ "$cx" = "null" ]; then
      misses=$((misses+1)); [ $misses -ge 5 ] && { echo "UNOBSERVABLE seat $seat"; exit 3; }; continue
    fi
    misses=0; px=$cx; py=$cy
    if (( $(echo "$(dist "$px" "$py" "$x" "$y") <= $tol" | bc -l) )); then echo "arrived $px,$py"; exit 0; fi
    [ "$walking" = "false" ] && break
    if [ "$px $py" = "$last" ]; then still=$((still+1)); [ $still -ge 4 ] && break; else still=0; fi
    last="$px $py"
  done
done

if (( $(echo "$(dist "$px" "$py" "$sx" "$sy") < 1.5" | bc -l) )); then
  mkdir -p "$STUCK_DIR"
  echo "$px $py" > "$marker"
  printf '[%s walk] ALERT seat %s is STUCK at (%.1f,%.1f): it could not move toward (%s,%s) on any of 7 tries. Walks on this seat now refuse until it is freed (mine the blocking piece with the seat, walk out, rebuild it, delete %s).\n' \
    "$(date +%H:%M)" "$seat" "$px" "$py" "$x" "$y" "crew/stuck/$seat" >> "$BOARD"
  echo "STUCK seat $seat at ($px,$py) trying to reach $x,$y"; exit 2
fi
echo "FAILED to reach $x,$y; at $px,$py"; exit 1
