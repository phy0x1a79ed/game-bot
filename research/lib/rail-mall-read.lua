local s=game.surfaces[1]
local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
local o={"tick "..game.tick}
for _,e in pairs(s.find_entities_filtered{type='assembling-machine',area={{10,-106},{54,-74}}}) do
 local r=e.get_recipe()
 o[#o+1]=string.format("%s %.1f,%.1f %s %s pf=%d out=%s",e.name:sub(-1),e.position.x,e.position.y,r and r.name or '-',st[e.status] or '?',e.products_finished,serpent.line(e.get_output_inventory().get_contents()))
end
for _,e in pairs(s.find_entities_filtered{type='container',area={{10,-106},{54,-74}}}) do o[#o+1]=string.format("chest %.1f,%.1f %s",e.position.x,e.position.y,serpent.line(e.get_inventory(defines.inventory.chest).get_contents())) end
rcon.print(table.concat(o,"\n"))
