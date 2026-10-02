#!/usr/bin/env bash
# belt-run.sh SEAT NAME DIR X1 Y1 X2 Y2 [OFFX OFFY] — place a straight line of NAME (belt) tiles with facing DIR from (X1,Y1) to (X2,Y2) inclusive,
# in chunks of 14 tiles. The seat stands at the chunk centre shifted by (OFFX,OFFY) (default 0 2) so it never blocks a tile.
# The line must run along one axis (X1==X2 or Y1==Y2). Prints failures only.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; name=$2; dir=$3; x1=$4; y1=$5; x2=$6; y2=$7; ox=${8:-0}; oy=${9:-2}
tiles=$(awk -v x1=$x1 -v y1=$y1 -v x2=$x2 -v y2=$y2 'BEGIN{ dx=(x2>x1)?1:((x2<x1)?-1:0); dy=(y2>y1)?1:((y2<y1)?-1:0); n=(dx!=0)?(x2-x1)*dx:(y2-y1)*dy; for(i=0;i<=n;i++) printf "%s,%s ", x1+dx*i, y1+dy*i }')
set -- $tiles; total=$#; i=0
while [ $i -lt $total ]; do
  chunk=("${@:$((i+1)):14}"); n=${#chunk[@]}
  mid=${chunk[$((n/2))]}; mx=${mid%,*}; my=${mid#*,}
  sx=$(echo "$mx + $ox" | bc); sy=$(echo "$my + $oy" | bc)
  "$LIB/walk.sh" "$seat" "$sx" "$sy" 1.5 >/dev/null
  list=$(printf '{%s},' "${chunk[@]}")
  "$LIB/act.sh" exec_lua "$seat" code="local r={} for _,p in pairs({$list}) do local ok,e=pcall(remote.call,'game_bot','build',{seat=seat,name='$name',x=p[1],y=p[2],direction='$dir'}) if not(ok and type(e)=='table' and not e.error and e.ok~=false) then r[#r+1]=p[1]..','..p[2]..' '..(ok and serpent.line(e) or tostring(e)) end end rcon.print(table.concat(r,'\n'))" | jq -r '.output // .' | sed '/^$/d'
  i=$((i+14))
done
echo "belt-run done $x1,$y1 -> $x2,$y2"
