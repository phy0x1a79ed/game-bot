#!/usr/bin/env bash
# area.sh SEAT X1 Y1 X2 Y2 — list player entities in the box: name (x,y) dir, plus belt items, chest contents, inserter/drill drop targets, status.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; tmp=$(mktemp /tmp/area.XXXXXX.lua)
cat > "$tmp" <<EOL
local out={}
local function inv(e)
  local s={}
  for _,id in pairs({defines.inventory.chest,defines.inventory.crafter_output,defines.inventory.fuel}) do
    local ok,i=pcall(function() return e.get_inventory(id) end)
    if ok and i then for _,it in pairs(i.get_contents()) do s[#s+1]=it.name..':'..it.count end end
  end
  return table.concat(s,',')
end
for _,e in pairs(game.surfaces[1].find_entities_filtered{area={{$2,$3},{$4,$5}},force='player'}) do
  if e.type~='character' then
    local x=''
    if e.type=='transport-belt' or e.type=='underground-belt' or e.type=='splitter' then
      x=' items='..e.get_transport_line(1).get_item_count()+e.get_transport_line(2).get_item_count()
      if e.type=='underground-belt' then x=x..' '..e.belt_to_ground_type end
    elseif e.type=='container' then x=' ['..inv(e)..']'
    elseif e.type=='inserter' or e.type=='mining-drill' then
      x=' st='..tostring(e.status)
      if e.type=='inserter' then x=x..' pick='..e.pickup_position.x..','..e.pickup_position.y..' drop='..e.drop_position.x..','..e.drop_position.y end
    elseif e.type=='furnace' then x=' st='..tostring(e.status)..' ['..inv(e)..']'
    end
    out[#out+1]=e.name..' ('..e.position.x..','..e.position.y..') d='..e.direction..x
  end
end
table.sort(out)
rcon.print(table.concat(out,'\n'))
EOL
"$LIB/act.sh" exec_lua "$seat" path="$tmp" | jq -r '.output // .'
rm -f "$tmp"
