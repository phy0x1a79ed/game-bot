local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local n = surf.find_entities_filtered{force="enemy", type="unit", position={-42,-16}, radius=50}
p('enemies within 50 of (-42,-16): '..#n)
for _, e in pairs(n) do p('  '..e.name..' @ '..string.format('%.1f,%.1f',e.position.x,e.position.y)) end
local corpses = surf.find_entities_filtered{area={{-52,-24},{-24,-8}}, name='character-corpse'}
p('corpses in area: '..#corpses)
for _, c in pairs(corpses) do
  local inv = c.get_inventory(defines.inventory.character_corpse) or c.get_inventory(defines.inventory.character_main)
  p('  corpse @ '..string.format('%.2f,%.2f',c.position.x,c.position.y)..' player='..tostring(c.character_corpse_player_index))
end
rcon.print(table.concat(out, '\n'))
