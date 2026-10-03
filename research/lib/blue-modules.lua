local s=game.surfaces[1] local ST={} for k,v in pairs(defines.entity_status) do ST[v]=k end
local o={'t='..game.tick}
for _,e in pairs(s.find_entities_filtered{name='assembling-machine-2'}) do local r=e.get_recipe() if r and (r.name=='chemical-science-pack' or r.name=='engine-unit') then o[#o+1]=string.format('%s(%.1f,%.1f) %s %d',r.name:sub(1,4),e.position.x,e.position.y,ST[e.status]:sub(1,10),e.products_finished) end end
for _,p in pairs({{82.5,36.5},{78.5,32.5}}) do local e=s.find_entities_filtered{type='assembling-machine',position=p,radius=0.5}[1] o[#o+1]=string.format('%s %s %d',e.get_recipe().name:sub(1,6),ST[e.status]:sub(1,10),e.products_finished) end
local ps=game.forces.player.get_item_production_statistics(s)
o[#o+1]=string.format('blue 1min made %.1f used %.1f',ps.get_flow_count{name='chemical-science-pack',category='input',precision_index=defines.flow_precision_index.one_minute},ps.get_flow_count{name='chemical-science-pack',category='output',precision_index=defines.flow_precision_index.one_minute})
rcon.print(table.concat(o,' | '))
