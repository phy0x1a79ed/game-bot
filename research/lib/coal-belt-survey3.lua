local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

-- everything near the power block + science lines, to find a clear corridor to the boiler
local box = {{-58,-34},{-10,4}}
local ents = surf.find_entities_filtered{area=box, force='player'}
p('entities in box (-58,-34)-(-10,4): ' .. #ents)
-- bucket by 2-wide x columns to show occupied x ranges at each y-band, cheap textual map
local occ = {}
for _, e in pairs(ents) do
  if e.type ~= 'character' then
    local bx = math.floor(e.position.x)
    local by = math.floor(e.position.y)
    occ[#occ+1] = {x=e.position.x, y=e.position.y, name=e.name, dir=e.direction}
  end
end
table.sort(occ, function(a,b) if a.y ~= b.y then return a.y < b.y else return a.x < b.x end end)
for _, o in pairs(occ) do
  p(string.format('  %-22s @ %6.1f,%6.1f dir=%s', o.name, o.x, o.y, tostring(o.dir)))
end

-- cliffs / water in this box (belts can't cross water; cliffs need explosives)
local water = surf.count_tiles_filtered{area=box, name={'water','deepwater','water-green','water-shallow'}}
p('water tile count in box: ' .. water)
local cliffs = surf.find_entities_filtered{area=box, type='cliff'}
p('cliffs in box: ' .. #cliffs)
for _, c in pairs(cliffs) do p('  cliff @ ' .. string.format('%.1f,%.1f', c.position.x, c.position.y)) end

rcon.print(table.concat(out, '\n'))
