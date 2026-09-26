local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local asms = surf.find_entities_filtered{area={{-50,-4},{-24,4}}, name='assembling-machine-1'}
for _, e in pairs(asms) do
  local r = e.get_recipe()
  p('asm @ '..string.format('%.1f,%.1f',e.position.x,e.position.y)..' recipe='..(r and r.name or 'none')..' status='..tostring(e.status))
end
local chests = surf.find_entities_filtered{area={{-50,-4},{-24,4}}, name='iron-chest'}
for _, e in pairs(chests) do
  local inv = e.get_inventory(defines.inventory.chest)
  local items = {}
  if inv then for _, it in pairs(inv.get_contents()) do items[#items+1]=it.name..':'..it.count end end
  p('chest @ '..string.format('%.1f,%.1f',e.position.x,e.position.y)..' contents: '..table.concat(items,','))
end
rcon.print(table.concat(out, '\n'))
