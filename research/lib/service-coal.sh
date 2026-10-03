#!/usr/bin/env bash
# service-coal.sh SEAT [FLOOR] — haul hand coal up to FLOOR on hand.
# Sources, in order: TAP chests beside the depot (coal belt tap), then coal ring 1.
# Re-read every cycle by upkeep.sh's coal_topup; edit with write + mv.
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
floor=${2:-200}
[ "$floor" -lt 600 ] && floor=600

# "walk_x walk_y chest_x chest_y take": the coalpower tap beside the depot. Ring 1 chests are left alone: they fuel the ring itself and the rule is 20 coal minimum.
TAP_STOPS=(
  "3.5 -30.5 1.5 -28.5 500"
  "3.5 -30.5 2.5 -28.5 500"
)
RING_STOPS=(
)
# Coal ring 1 is retired (its drills are marked for deconstruction), so no drill is hand-fuelled:
# "walk_x walk_y drill_x drill_y target_coal"
RING_HAND_DRILLS=()

have() { "$LIB/act.sh" observe "$seat" radius=1 | jq -r '.snapshot.inventory["coal"] // 0'; }
exec_out() { RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$1" 2>/dev/null | jq -r '.output // ""' | tr -d '[:space:]'; }

enemies=$(exec_out 'local n=0 for _,e in pairs(game.surfaces["nauvis"].find_entities_filtered{force="enemy",type="unit",position={70,-40},radius=60}) do n=n+1 end rcon.print(n)')

fuel_hand_drills() {
  for s in "${RING_HAND_DRILLS[@]}"; do
    set -- $s
    lvl=$(exec_out "local e=game.surfaces[\"nauvis\"].find_entity(\"burner-mining-drill\",{$3,$4}) rcon.print(e and e.burner.inventory.get_item_count(\"coal\") or 99)")
    if [ "${lvl:-99}" -lt 15 ] 2>/dev/null && [ "$(have)" -ge 40 ]; then
      "$LIB/walk.sh" "$seat" "$1" "$2" 3 >/dev/null
      ins=$("$LIB/act.sh" insert "$seat" x="$3" y="$4" name=coal count=$(( $5 - lvl )) target=burner-mining-drill 2>/dev/null | jq -r '.inserted // 0')
      echo "  ring drill ($3,$4): was ${lvl}, +${ins} coal"
    fi
  done
}

have_coal=$(have)
echo "coal on hand: $have_coal"

if [ "${enemies:-0}" != "0" ]; then
  echo "  enemies near ring, skipping ring drill fuel"
else
  fuel_hand_drills
fi
[ "$(have)" -ge "$floor" ] 2>/dev/null && exit 0

for s in "${TAP_STOPS[@]:-}"; do
  [ -z "$s" ] && continue
  set -- $s
  "$LIB/walk.sh" "$seat" "$1" "$2" 3 >/dev/null
  got=$("$LIB/act.sh" take "$seat" x="$3" y="$4" name=coal count="$5" target=iron-chest 2>/dev/null | jq -r '.taken // 0')
  echo "  tap chest ($3,$4): +${got} coal"
done
[ "$(have)" -ge "$floor" ] 2>/dev/null && exit 0

if [ "${enemies:-0}" != "0" ]; then
  echo "  enemies near ring, skipping ring haul this pass"
  exit 0
fi
for s in "${RING_STOPS[@]}"; do
  set -- $s
  "$LIB/walk.sh" "$seat" "$1" "$2" 3 >/dev/null
  got=$("$LIB/act.sh" take "$seat" x="$3" y="$4" name=coal count="$5" target=iron-chest 2>/dev/null | jq -r '.taken // 0')
  echo "  ring chest ($3,$4): +${got} coal"
done
