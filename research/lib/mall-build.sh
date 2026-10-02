#!/usr/bin/env bash
# mall-build.sh SEAT XMIN XMAX YMIN YMAX STANDX STANDY [NAMES] — walk to (STANDX,STANDY), build every entity of
# crew/mall-plan.json whose centre lies in the box (skipping transport-belt unless NAMES lists it), poles and chests first.
# Prints failures only. Entities already present are reported as failures; ignore those.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; x1=$2; x2=$3; y1=$4; y2=$5; sx=$6; sy=$7; names=${8:-assembling-machine-1,small-electric-pole,iron-chest,inserter,stone-furnace}
"$LIB/walk.sh" "$seat" "$sx" "$sy" 1.5 >/dev/null
list=$(jq -r --argjson x1 $x1 --argjson x2 $x2 --argjson y1 $y1 --argjson y2 $y2 --arg names "$names" '
  ($names|split(",")) as $n | [.entities[] | select(.x>=$x1 and .x<=$x2 and .y>=$y1 and .y<=$y2 and (.name as $m | $n|index($m)))]
  | sort_by(if .name=="small-electric-pole" then 0 elif .name=="iron-chest" then 1 elif .name=="assembling-machine-1" then 2 else 3 end)
  | map("{\"" + .name + "\"," + (.x|tostring) + "," + (.y|tostring) + ",\"" + ({"N":"north","E":"east","S":"south","W":"west"}[(.dir // "N")]) + "\"}") | join(",")' "$LIB/../crew/mall-plan.json")
"$LIB/act.sh" exec_lua "$seat" code="local r={} for _,p in pairs({$list}) do local ok,e=pcall(remote.call,'game_bot','build',{seat=seat,name=p[1],x=p[2],y=p[3],direction=p[4]}) if not(ok and type(e)=='table' and not e.error and e.ok~=false) then r[#r+1]=p[1]..' '..p[2]..','..p[3]..' '..(ok and serpent.line(e) or tostring(e)) end end rcon.print(table.concat(r,'\n'))" | jq -r '.output // .' | sed '/^$/d'
echo "mall-build done"
