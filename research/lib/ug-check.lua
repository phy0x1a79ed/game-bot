-- ug-check.lua: underground belt pairs. A live pair reads input D + output D; belt_neighbours.outputs of the exit must be the next tile in the flow direction.
local surf=game.surfaces[1]
local out={}
for _,e in pairs(surf.find_entities_filtered{area={{-50,-16},{-10,12}},type='underground-belt'}) do
  local n=e.belt_neighbours
  local function lst(t) local r={} for _,b in pairs(t) do r[#r+1]=b.name:sub(1,3)..string.format('(%.1f,%.1f)',b.position.x,b.position.y) end return table.concat(r,';') end
  out[#out+1]=string.format('(%.1f,%.1f) dir=%d %s in=[%s] out=[%s]',e.position.x,e.position.y,e.direction,e.belt_to_ground_type,lst(n.inputs),lst(n.outputs))
end
rcon.print(table.concat(out,'\n'))
