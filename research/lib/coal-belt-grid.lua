local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

local x0, x1 = -60, -44
local y0, y1 = -22, -6
p('grid x=' .. x0 .. '..' .. x1 .. ' y=' .. y0 .. '..' .. y1 .. ' (row=y, each char=one x, .=buildable #=blocked)')
for y = y0, y1 do
  local row = {}
  for x = x0, x1 do
    local ok = surf.can_place_entity{name='transport-belt', position={x+0.5, y+0.5}, direction=defines.direction.west, force='player'}
    row[#row+1] = ok and '.' or '#'
  end
  p(string.format('y=%4d %s', y, table.concat(row)))
end
p('x-ruler   ' .. table.concat((function() local t={} for x=x0,x1 do t[#t+1]=tostring((x)%10) end return t end)(), ''))
rcon.print(table.concat(out, '\n'))
