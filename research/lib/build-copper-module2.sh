#!/usr/bin/env bash
# build-copper-module2.sh SEAT X Y
# Build one hand-fed copper module using a FREED burner-mining-drill already
# in inventory (no drill craft): drill(X,Y) east -> furnace(X+2,Y) -> output
# inserter(X+2.5,Y+1.5,dir=north) -> chest(X+2.5,Y+2.5). Matches modules 3-6's
# shape so service-copper.sh can be extended the same way.
set -u
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; X=$2; Y=$3
iy=$(echo "$Y + 1.5" | bc)
cy=$(echo "$Y + 2.5" | bc)
fx=$(echo "$X + 2" | bc)
ix=$(echo "$X + 2.5" | bc)

echo "== enemy check near ($X,$Y) =="
tmp=$(mktemp /tmp/coppercheck.XXXXXX.lua)
cat > "$tmp" <<EOF
local n=0
for _,e in pairs(game.surfaces[1].find_entities_filtered{force="enemy",type="unit",position={$X,$Y},radius=100}) do n=n+1 end
rcon.print(n)
EOF
enemies=$("$LIB/act.sh" exec_lua "$seat" path="$tmp" | jq -r '.output // "0"' | tr -d '[:space:]')
rm -f "$tmp"
echo "enemies: ${enemies:-0}"
if [ "${enemies:-0}" != "0" ]; then echo "ABORT: enemies detected near ($X,$Y)"; exit 1; fi

"$LIB/walk.sh" "$seat" "$X" $(echo "$Y - 3" | bc) 3 >/dev/null

echo "-- building drill($X,$Y)E / furnace($fx,$Y) / inserter($ix,$iy,N) / chest($ix,$cy) --"
"$LIB/act.sh" build "$seat" name=burner-mining-drill x=$X y=$Y direction=east
"$LIB/act.sh" build "$seat" name=stone-furnace x=$fx y=$Y
"$LIB/act.sh" build "$seat" name=burner-inserter x=$ix y=$iy direction=north
"$LIB/act.sh" build "$seat" name=iron-chest x=$ix y=$cy

echo "-- priming fuel --"
"$LIB/act.sh" insert "$seat" x=$X y=$Y name=coal count=25 target=burner-mining-drill
"$LIB/act.sh" insert "$seat" x=$fx y=$Y name=coal count=25 target=stone-furnace
"$LIB/act.sh" insert "$seat" x=$ix y=$iy name=coal count=4 target=burner-inserter

tmp2=$(mktemp /tmp/coppervfy.XXXXXX.lua)
cat > "$tmp2" <<EOF
local d = game.surfaces[1].find_entities_filtered{position={$X,$Y}, radius=0.6, name='burner-mining-drill'}[1]
local f = game.surfaces[1].find_entities_filtered{position={$fx,$Y}, radius=1, name='stone-furnace'}[1]
local i = game.surfaces[1].find_entities_filtered{position={$ix,$iy}, radius=0.6, name='burner-inserter'}[1]
local c = game.surfaces[1].find_entities_filtered{position={$ix,$cy}, radius=0.6, name='iron-chest'}[1]
rcon.print('drill='..(d and tostring(d.status) or 'MISSING')..
  ' furnace='..(f and tostring(f.status) or 'MISSING')..
  ' inserter='..(i and (tostring(i.status)..' pickup='..i.pickup_position.x..','..i.pickup_position.y..' drop='..i.drop_position.x..','..i.drop_position.y) or 'MISSING')..
  ' chest='..(c and 'ok' or 'MISSING'))
EOF
echo "== verify (waiting up to 10s for drop_target) =="
for i in 1 2 3 4 5; do
  sleep 2
  out=$("$LIB/act.sh" exec_lua "$seat" path="$tmp2" | jq -r '.output // .')
  echo "$out"
done
rm -f "$tmp2"
