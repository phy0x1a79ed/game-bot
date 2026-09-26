local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local function chest_at(pos)
  local c = surf.find_entities_filtered{position=pos, radius=1, name='iron-chest'}[1]
  if not c then return 'NO CHEST' end
  local inv = c.get_inventory(defines.inventory.chest)
  local items = {}
  for _, it in pairs(inv.get_contents()) do items[#items+1] = it.name..':'..it.count end
  return table.concat(items, ' ')
end
p('depot(0.5,-19.5): ' .. chest_at({0.5,-19.5}))
p('gear-asm chest(-38.5,-8.5): ' .. chest_at({-38.5,-8.5}))
p('red-asm iron?(-42.5,-2.5)/(-38.5,-2.5)/(-34.5,-2.5)/(-30.5,-2.5) [green line iron chests]:')
for _, pos in pairs({{-42.5,-2.5},{-38.5,-2.5},{-34.5,-2.5},{-30.5,-2.5}}) do
  p('  '..pos[1]..','..pos[2]..': '..chest_at(pos))
end
rcon.print(table.concat(out, '\n'))
