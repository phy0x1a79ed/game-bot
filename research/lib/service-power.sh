#!/usr/bin/env bash
# service-power.sh SEAT [TARGET]
# Backup boiler buffer chest (-50.5,-6.5): refilled to TARGET (default 500) only when it falls below 200 (supervisor 15:16 order; the coal belt is the primary feed). Safe to call repeatedly -- no-ops if the feed is already
# at or above target.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
target=${2:-500}
[ -z "$seat" ] && { echo "usage: service-power.sh SEAT [target]"; exit 1; }

# Run 3: the old feed chest (-47.5,-8.5) is now a coal belt tile, which the burner
# inserter (-48.5,-8.5) lifts from. A buffer chest (-50.5,-6.5) with its own burner
# inserter (-50.5,-7.5, south->boiler) bridges until that belt carries coal. Keep the
# buffer at TARGET coal and the boiler's own slot topped.
chest_coal=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code 'local c=game.surfaces[1].find_entity("iron-chest",{-50.5,-6.5}) rcon.print(c and c.get_inventory(defines.inventory.chest).get_item_count("coal") or -1)' 2>/dev/null | jq -r '.output // "-1"' | tr -d '[:space:]')
belt_coal=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code 'local b=game.surfaces[1].find_entity("transport-belt",{-47.5,-8.5}) rcon.print(b and (b.get_transport_line(1).get_item_count("coal")+b.get_transport_line(2).get_item_count("coal")) or -1)' 2>/dev/null | jq -r '.output // "-1"' | tr -d '[:space:]')
echo "boiler buffer chest(-50.5,-6.5): ${chest_coal} coal (target ${target}); coal on belt tile at inserter: ${belt_coal}"
have_coal=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot.inventory["coal"] // 0')
BUFFER_FLOOR=200
give=$((target - chest_coal)); [ "${chest_coal:-0}" -ge "$BUFFER_FLOOR" ] && give=0; [ "$give" -gt "$have_coal" ] && give=$have_coal
if [ "${chest_coal:-0}" -ge 0 ] && [ "$give" -gt 20 ] 2>/dev/null; then
  "$LIB/walk.sh" "$seat" -49 -5 3 >/dev/null
  got=$("$LIB/act.sh" insert "$seat" x=-50.5 y=-6.5 name=coal count="$give" target=iron-chest 2>/dev/null | jq -r '.inserted // 0')
  echo "buffer chest +${got} coal"
  "$LIB/act.sh" insert "$seat" x=-50.5 y=-7.5 name=coal count=5 target=burner-inserter >/dev/null 2>&1
  "$LIB/act.sh" insert "$seat" x=-48.5 y=-8.5 name=coal count=5 target=burner-inserter >/dev/null 2>&1
fi

echo "== ammo assembler upkeep (power block, same area) =="
AMMO_ASM_TARGET=400
"$LIB/walk.sh" "$seat" -38 -4.5 4 >/dev/null
"$LIB/act.sh" insert "$seat" x=-39.5 y=-4.5 name=coal count=5 target=burner-inserter >/dev/null 2>&1
"$LIB/act.sh" insert "$seat" x=-35.5 y=-4.5 name=coal count=5 target=burner-inserter >/dev/null 2>&1
in_lvl=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code 'local c=game.surfaces["nauvis"].find_entity("iron-chest",{-40.5,-4.5}) rcon.print(c.get_inventory(defines.inventory.chest).get_item_count("iron-plate"))' 2>/dev/null | jq -r '.output // "0"' | tr -d '[:space:]')
echo "ammo asm input chest(-40.5,-4.5): ${in_lvl} iron (target ${AMMO_ASM_TARGET})"
# 2026-09-26 14:xx: this used to only READ the level and never actually fed
# it -- found the chest sitting at 0 iron with the assembler starved.
need=$((AMMO_ASM_TARGET - in_lvl))
if [ "${in_lvl:-0}" -ge 0 ] 2>/dev/null && [ "$need" -gt 0 ]; then
  have=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot.inventory["iron-plate"] // 0')
  take=$need; [ "$have" -lt "$take" ] && take=$have
  if [ "$take" -gt 0 ]; then
    got=$("$LIB/act.sh" insert "$seat" x=-40.5 y=-4.5 name=iron-plate count="$take" target=iron-chest 2>/dev/null | jq -r '.inserted // 0')
    echo "  topped ammo asm input chest by ${got} iron"
  else
    echo "  need ${need} iron but 0 on hand"
  fi
fi
out_mags=$("$LIB/act.sh" take "$seat" x=-34.5 y=-4.5 name=firearm-magazine target=iron-chest 2>/dev/null | jq -r '.taken // 0')
[ "$out_mags" -gt 0 ] && echo "collected ${out_mags} magazines from ammo asm output chest for turret top-ups"
