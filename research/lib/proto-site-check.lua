local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local ents = surf.find_entities_filtered{area={{-46,-3},{-28,3}}, force='player'}
p('entities in box (-46,-3)-(-28,3): '..#ents)
for _, e in pairs(ents) do p('  '..e.name..' @ '..string.format('%.1f,%.1f',e.position.x,e.position.y)) end
-- candidate layout: cable-asm center A, circuit-asm center A+4 (x-axis), inserter between
local candidates = {
  {name='assembling-machine-1', x=-44.5, y=-2.5},
  {name='assembling-machine-1', x=-40.5, y=-2.5},
  {name='inserter', x=-42.5, y=-2.5},
  {name='small-electric-pole', x=-44.5, y=-0.5},
  {name='iron-chest', x=-38.5, y=-2.5},
  {name='inserter', x=-39.5, y=-2.5},
}
for _, c in pairs(candidates) do
  local can = surf.can_place_entity{name=c.name, position={c.x,c.y}}
  p('can_place '..c.name..' @ '..c.x..','..c.y..' = '..tostring(can))
end
-- nearest existing pole distance for power check
local nearpoles = surf.find_entities_filtered{area={{-50,-8},{-24,4}}, name={'small-electric-pole','medium-electric-pole','big-electric-pole'}}
p('poles nearby: '..#nearpoles)
for _, e in pairs(nearpoles) do p('  pole @ '..string.format('%.1f,%.1f',e.position.x,e.position.y)) end
rcon.print(table.concat(out, '\n'))
