#!/usr/bin/env bash
# convert-row.sh SEAT Y MODE
# MODE=self   -- mine burner-drill(-24,Y) + fuel-inserter(-25.5,Y-0.5) + coal-chest(-26.5,Y-0.5), place electric drill.
# MODE=hand   -- mine burner-drill(-24,Y) only, place electric drill.
# MODE=rebuild-- no burner drill to mine (lost earlier); optionally mine leftover coal-chest(-26.5,Y-0.5); place electric drill fresh from inventory.
# Electric drill goes at (-24.5,Y-0.5) facing east, dropping into the existing furnace at (-22,Y).
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; y=$2; mode=$3
sy=$(echo "$y - 0.5" | bc)

tmp1=$(mktemp /tmp/rowcheck.XXXXXX.lua)
cat > "$tmp1" <<EOF
local n=0
for _,e in pairs(game.surfaces[1].find_entities_filtered{force="enemy",type="unit",position={-23,$y},radius=150}) do n=n+1 end
rcon.print(n)
EOF
echo "== enemy check near row y=$y =="
enemies=$("$LIB/act.sh" exec_lua "$seat" path="$tmp1" | jq -r '.output // "0"' | tr -d '[:space:]')
rm -f "$tmp1"
echo "enemies: ${enemies:-0}"
if [ "${enemies:-0}" != "0" ]; then echo "ABORT row $y: enemies detected"; exit 1; fi

"$LIB/walk.sh" "$seat" -24 "$sy" 4 >/dev/null

if [ "$mode" = "self" ] || [ "$mode" = "hand" ]; then
  echo "-- mining burner-mining-drill(-24,$y) --"
  "$LIB/act.sh" mine "$seat" x=-24 y=$y
fi
if [ "$mode" = "self" ] || [ "$mode" = "rebuild" ]; then
  echo "-- mining fuel-inserter(-25.5,$sy) + coal-chest(-26.5,$sy) if present --"
  "$LIB/act.sh" mine "$seat" x=-25.5 y=$sy 2>&1 | grep -v '^$' || true
  "$LIB/act.sh" mine "$seat" x=-26.5 y=$sy 2>&1 | grep -v '^$' || true
fi

echo "-- placing electric-mining-drill(-24.5,$sy) facing east --"
"$LIB/act.sh" build "$seat" name=electric-mining-drill x=-24.5 y=$sy direction=east

tmp2=$(mktemp /tmp/rowverify.XXXXXX.lua)
cat > "$tmp2" <<EOF
local d = game.surfaces[1].find_entities_filtered{position={-24.5,$sy}, radius=0.6, name='electric-mining-drill'}[1]
local f = game.surfaces[1].find_entities_filtered{position={-22,$y}, radius=1, name='stone-furnace'}[1]
if d then
  rcon.print('drill status='..tostring(d.status)..' drop_target='..(d.drop_target and (d.drop_target.name..'@'..d.drop_target.position.x..','..d.drop_target.position.y) or 'nil'))
else
  rcon.print('DRILL NOT FOUND')
end
if f then rcon.print('furnace status='..tostring(f.status)) end
EOF
echo "== verifying (waiting up to 10s for drop_target + status) =="
for i in 1 2 3 4 5; do
  sleep 2
  out=$("$LIB/act.sh" exec_lua "$seat" path="$tmp2" | jq -r '.output // .')
  echo "$out"
  echo "$out" | grep -q 'drop_target=stone-furnace' && break
done
rm -f "$tmp2"
