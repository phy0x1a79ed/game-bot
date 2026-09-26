local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local ents = surf.find_entities_filtered{area={{-50,-19},{-26,-15}}, force='player'}
p('entities in box (-50,-19)-(-26,-15): '..#ents)
for _, e in pairs(ents) do p('  '..e.name..' @ '..string.format('%.1f,%.1f',e.position.x,e.position.y)) end
local gt = prototypes.entity['gun-turret']
p('gun-turret max range (attack_parameters.range)='..tostring(gt.attack_parameters and gt.attack_parameters.range))
-- candidate: row y=-16.5, cable asm x=-44.5, circuit asm x=-40.5, inserter x=-42.5
local candidates = {
  {name='assembling-machine-1', x=-44.5, y=-16.5},
  {name='assembling-machine-1', x=-40.5, y=-16.5},
  {name='inserter', x=-42.5, y=-16.5},
  {name='small-electric-pole', x=-46.5, y=-16.5},
  {name='iron-chest', x=-46.5, y=-15.5},
  {name='iron-chest', x=-38.5, y=-15.5},
  {name='inserter', x=-44.5, y=-15.5},
  {name='inserter', x=-38.5, y=-16.5},
}
for _, c in pairs(candidates) do
  p('can_place '..c.name..' @ '..c.x..','..c.y..' = '..tostring(surf.can_place_entity{name=c.name, position={c.x,c.y}}))
end
rcon.print(table.concat(out, '\n'))
