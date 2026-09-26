local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local function probe(x,y) return surf.can_place_entity{name='transport-belt', position={x,y}, direction=defines.direction.west, force='player'} end

p('=== x=-19.5 and x=-20.5, y from -10 to +4 (looking for a gap in / just past the iron-belt wall) ===')
for y = -10, 4 do
  local yy = y + 0.5
  p(string.format('y=%5.1f  x=-20.5:%s  x=-19.5:%s  x=-18.5:%s', yy, tostring(probe(-20.5,yy)), tostring(probe(-19.5,yy)), tostring(probe(-18.5,yy))))
end
-- also the far south end, below the iron column entirely
p('=== far south crossing, y from -66 to -60 ===')
for y = -66, -60 do
  local yy = y + 0.5
  p(string.format('y=%5.1f  x=-20.5:%s  x=-19.5:%s  x=-18.5:%s', yy, tostring(probe(-20.5,yy)), tostring(probe(-19.5,yy)), tostring(probe(-18.5,yy))))
end
rcon.print(table.concat(out, '\n'))
