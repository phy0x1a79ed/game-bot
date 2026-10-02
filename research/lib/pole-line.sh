#!/usr/bin/env bash
# pole-line.sh SEAT NAME X1 Y1 X2 Y2 STEP — place NAME poles along an axis-aligned line from (X1,Y1) toward (X2,Y2) every STEP tiles.
# Walks to every third pole and builds three per stop. Prints failures only. Run it from anywhere; the seat needs the poles in inventory.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; name=$2; x1=$3; y1=$4; x2=$5; y2=$6; step=$7
pts=$(awk -v x1=$x1 -v y1=$y1 -v x2=$x2 -v y2=$y2 -v st=$step 'BEGIN{ dx=(x2>x1)?1:((x2<x1)?-1:0); dy=(y2>y1)?1:((y2<y1)?-1:0); n=(dx!=0)?(x2-x1)*dx:(y2-y1)*dy; for(i=0;i<=n;i+=st) printf "%s,%s ", x1+dx*i, y1+dy*i }')
set -- $pts; total=$#; i=0
while [ $i -lt $total ]; do
  chunk=("${@:$((i+1)):3}"); n=${#chunk[@]}
  mid=${chunk[$((n/2))]}; mx=${mid%,*}; my=${mid#*,}
  "$LIB/walk.sh" "$seat" "$mx" "$(echo "$my - 2" | bc)" 1.5 >/dev/null
  list=$(printf '{%s},' "${chunk[@]}")
  "$LIB/act.sh" exec_lua "$seat" code="local r={} for _,p in pairs({$list}) do local ok,e=pcall(remote.call,'game_bot','build',{seat=seat,name='$name',x=p[1],y=p[2],direction='north'}) if not(ok and type(e)=='table' and not e.error and e.ok~=false) then r[#r+1]=p[1]..','..p[2]..' '..(ok and serpent.line(e) or tostring(e)) end end rcon.print(table.concat(r,'\n'))" | jq -r '.output // .' | sed '/^$/d'
  i=$((i+3))
done
echo "pole-line done"
