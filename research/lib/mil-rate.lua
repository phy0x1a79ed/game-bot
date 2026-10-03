-- mil-rate.lua: military science block status (industry lane). Run: lib/act.sh exec_lua SEAT path=<abs>/lib/mil-rate.lua
local s=game.surfaces[1]
local function st(e) for k,v in pairs(defines.entity_status) do if v==e.status then return k end end return tostring(e.status) end
local o={'tick '..game.tick}
for _,p in ipairs({{'W',40.5,-43.5},{'M',44.5,-21.5},{'G',49.5,-22.5},{'M2',45.5,-17.5},{'G2',52.5,-20.5}}) do local e=s.find_entities_filtered{type='assembling-machine',position={p[2],p[3]},radius=0.3}[1]
 if e then local t='' for _,it in ipairs(e.get_inventory((defines.inventory.assembling_machine_input or defines.inventory.crafter_input)).get_contents()) do t=t..it.name:sub(1,6)..'='..it.count..' ' end
 o[#o+1]=p[1]..'='..st(e)..' made'..e.products_finished..' in['..t..'] out'..e.get_inventory((defines.inventory.assembling_machine_output or defines.inventory.crafter_output)).get_item_count() else o[#o+1]=p[1]..' MISSING' end end
local function lanes(a,b) local t={{},{}} for _,e in ipairs(s.find_entities_filtered{type={'transport-belt','underground-belt'},area={a,b}}) do for l=1,2 do for _,it in ipairs(e.get_transport_line(l).get_contents()) do t[l][it.name]=(t[l][it.name] or 0)+it.count end end end local q='' for l=1,2 do q=q..'L'..l..':' for n,v in pairs(t[l]) do q=q..n:sub(1,8)..'='..v..' ' end end return q end
o[#o+1]='wallbelt['..lanes({41,-41},{45,-34})..'] FB['..lanes({45,-35},{48,-24})..'] col['..lanes({41,-25},{42,-20})..']'
local c=s.find_entities_filtered{name='iron-chest',position={52.5,-23.5},radius=0.3}[1] o[#o+1]='grenadechest='..c.get_item_count('grenade')
local out=s.find_entities_filtered{name='iron-chest',position={45.5,-32.5},radius=0.3}[1] o[#o+1]='OUT='..out.get_item_count('piercing-rounds-magazine')
local stt=game.forces.player.get_item_production_statistics(s) o[#o+1]='mil made 1min='..stt.get_flow_count{name='military-science-pack',category='input',precision_index=defines.flow_precision_index.one_minute,count=true}..' used='..stt.get_flow_count{name='military-science-pack',category='output',precision_index=defines.flow_precision_index.one_minute,count=true}
rcon.print(table.concat(o,' '))
