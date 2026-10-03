-- iron3-milfin.lua: tick + products_finished of every crafting machine in the military/ammo block (x 36..58, y -50..-5)
local s=game.surfaces[1] local o={'tick='..game.tick}
for _,e in pairs(s.find_entities_filtered{area={{34,-50},{58,-5}},type={'assembling-machine','furnace'}}) do
  local r=e.get_recipe() or (e.type=='furnace' and e.previous_recipe)
  local rn=r and (r.name or (r.object_name and r.name)) or '-' if type(rn)~='string' then rn=tostring(rn) end
  o[#o+1]=string.format('%s@%g,%g=%d',rn,e.position.x,e.position.y,e.products_finished) end
rcon.print(table.concat(o,' '))
