local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local rows = {-48,-51,-54,-57,-60,-63}
for _, y in pairs(rows) do
  local ents = surf.find_entities_filtered{area={{-30,y-2},{-10,y+2}}, force='player'}
  local line = 'row y='..y..': '
  for _, e in pairs(ents) do
    if e.type ~= 'character' then
      line = line .. e.name..'@'..string.format('%.1f,%.1f',e.position.x,e.position.y)..'/dir'..tostring(e.direction)..' '
    end
  end
  p(line)
end
-- enemy check near column
local n = 0
for _, e in pairs(surf.find_entities_filtered{force='enemy', type='unit', position={-20,-55}, radius=150}) do n = n + 1 end
p('enemies within 150 of column centre: '..n)
rcon.print(table.concat(out, '\n'))
