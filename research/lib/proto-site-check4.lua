local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local ents = surf.find_entities_filtered{area={{-37,-19},{-25,-14}}}
p('all entities in box (-37,-19)-(-25,-14): '..#ents)
for _, e in pairs(ents) do p('  '..e.name..'('..e.type..') @ '..string.format('%.2f,%.2f',e.position.x,e.position.y)) end
local candidates = {
  {name='assembling-machine-1', x=-34.5, y=-16.5},
  {name='inserter', x=-32.5, y=-16.5},
  {name='assembling-machine-1', x=-30.5, y=-16.5},
  {name='inserter', x=-28.5, y=-16.5},
  {name='iron-chest', x=-27.5, y=-16.5},
  {name='small-electric-pole', x=-35.5, y=-14.5},
  {name='small-electric-pole', x=-29.5, y=-14.5},
}
for _, c in pairs(candidates) do
  p('can_place '..c.name..' @ '..c.x..','..c.y..' = '..tostring(surf.can_place_entity{name=c.name, position={c.x,c.y}}))
end
local n = surf.find_entities_filtered{force="enemy", type="unit", position={-32,-16}, radius=40}
p('enemies within 40 of (-32,-16): '..#n)
rcon.print(table.concat(out, '\n'))
