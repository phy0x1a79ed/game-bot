-- power-check.lua: boilers, engines (kW), brownout counts, network flows.
local surf=game.surfaces[1]
local ST={} for k,v in pairs(defines.entity_status) do ST[v]=k end
local out={'tick='..game.tick}
for _,e in pairs(surf.find_entities_filtered{name='boiler'}) do out[#out+1]='boiler st='..ST[e.status]..' fuel='..e.get_fuel_inventory().get_item_count()..' temp?' end
for _,e in pairs(surf.find_entities_filtered{name='steam-engine'}) do out[#out+1]=string.format('engine (%.1f,%.1f) st=%s gen_last_tick=%.0f (=%.0f kW) buffer=%s',e.position.x,e.position.y,ST[e.status],e.energy_generated_last_tick,e.energy_generated_last_tick*60/1000,tostring(e.energy)) end
local cnt={}
for _,e in pairs(surf.find_entities_filtered{force='player'}) do
  if e.status then local s=ST[e.status] if s=='no_power' or s=='low_power' then cnt[s]=(cnt[s] or 0)+1 end end
end
for k,v in pairs(cnt) do out[#out+1]=k..'='..v end
-- electric network stats
local p=surf.find_entities_filtered{name='small-electric-pole'}[1]
out[#out+1]='net id '..tostring(p.electric_network_id)
local ns=p.electric_network_statistics
local items={}
for name,_ in pairs(ns.input_counts) do items[#items+1]='in:'..name..'='..string.format('%.0f',ns.get_flow_count{name=name,category='input',precision_index=defines.flow_precision_index.one_minute}) end
for name,_ in pairs(ns.output_counts) do items[#items+1]='out:'..name..'='..string.format('%.0f',ns.get_flow_count{name=name,category='output',precision_index=defines.flow_precision_index.one_minute}) end
out[#out+1]=table.concat(items,' ')
rcon.print(table.concat(out,'\n'))
