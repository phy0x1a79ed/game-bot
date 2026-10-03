#!/usr/bin/env bash
# service-power.sh SEAT
# Rescues any boiler that is out of fuel (all 15 are belt-fed by electric
# inserters), then collects magazines from the ammo assembler's output chest for
# turret top-ups. The ammo assembler's input is belt-fed.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1
[ -z "$seat" ] && { echo "usage: service-power.sh SEAT"; exit 1; }

# A boiler that is out of fuel (status no_fuel, or 0 coal) gets topped to 30.
# Belt-fed boilers idle at ~5 coal, so a higher threshold hand-fed all of them every
# cycle and hid whether the belts keep up. Out-of-fuel still needs a rescue: a
# brownout slows the electric coal drills that feed the boilers, a spiral nothing
# else breaks.
LUA_BOILERS='local o={} for _,b in pairs(game.surfaces[1].find_entities_filtered{type="boiler",force="player"}) do local c=b.get_fuel_inventory().get_item_count("coal") if c<1 or b.status==defines.entity_status.no_fuel then local s=game.surfaces[1].find_non_colliding_position("character",b.position,4,0.5) if s and s.x>-48 and s.x<-38 and s.y>-32.5 and s.y<-29.5 then s=game.surfaces[1].find_non_colliding_position("character",{b.position.x,b.position.y-4},2,0.5) end if s then o[#o+1]=string.format("%.1f,%.1f,%d,%.1f,%.1f",b.position.x,b.position.y,c,s.x,s.y) end end end rcon.print(table.concat(o,";"))'
dry=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code "$LUA_BOILERS" 2>/dev/null | jq -r '.output // ""' | tr -d '[:space:]')
boiler_in=0
if [ -n "$dry" ]; then
  IFS=';' read -ra dry_list <<< "$dry"
  for d in "${dry_list[@]}"; do
    IFS=',' read -r bx by bc sx sy <<< "$d"
    have_coal=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot.inventory["coal"] // 0')
    [ "${have_coal:-0}" -lt 10 ] 2>/dev/null && { echo "  boiler ($bx,$by) at $bc coal: none on hand"; continue; }
    give=$((30 - bc)); [ "$give" -gt "$have_coal" ] && give=$have_coal
    "$LIB/walk.sh" "$seat" "$sx" "$sy" 2 >/dev/null 2>&1
    got=$("$LIB/act.sh" insert "$seat" x="$bx" y="$by" name=coal count="$give" target=boiler 2>/dev/null | jq -r '.inserted // 0')
    echo "  boiler ($bx,$by) at $bc coal: +${got}"
    boiler_in=$((boiler_in + got))
  done
fi
echo "boilers out of fuel: +${boiler_in} coal"

echo "== ammo assembler output (magazines for turret top-ups) =="
"$LIB/walk.sh" "$seat" -36 -4.5 4 >/dev/null
out_mags=$("$LIB/act.sh" take "$seat" x=-34.5 y=-4.5 name=firearm-magazine target=iron-chest 2>/dev/null | jq -r '.taken // 0')
[ "$out_mags" -gt 0 ] && echo "collected ${out_mags} magazines from ammo asm output chest for turret top-ups"
