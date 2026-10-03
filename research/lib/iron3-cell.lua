-- iron3-cell.lua: robot cell (x 73..92, y 2..26) status: machine states, finished counts, kit chest, input chest stock
local s=game.surfaces[1] local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
rcon.print('tick '..game.tick)
for _,e in pairs(s.find_entities_filtered{area={{72,9},{93,27}},type={'assembling-machine'}}) do rcon.print(string.format('%s (%g,%g) %s fin=%d',e.get_recipe() and e.get_recipe().name or '-',e.position.x,e.position.y,st[e.status] or '?',e.products_finished)) end
for _,p in pairs({{83.5,19.5,'KIT'},{73.5,11.5,'EN'},{79.5,16.5,'circ'},{73.5,20.5,'FR'},{79.5,23.5,'BPcu'},{86.5,12.5,'AC'},{90.5,12.5,'cable-cu'},{89.5,19.5,'RP'}}) do local c=s.find_entity('iron-chest',{p[1],p[2]}) local o={} for _,i in pairs(c.get_inventory(defines.inventory.chest).get_contents()) do o[#o+1]=i.name..'='..i.count end rcon.print(p[3]..': '..table.concat(o,' ')) end
local t=s.find_entity('storage-tank',{64.5,0.5}) local a=s.find_entity('storage-tank',{69.5,24.5}) rcon.print('lube '..math.floor(t.get_fluid_count())..' acid '..math.floor(a.get_fluid_count()))
