local s=game.surfaces[1] local ST={} for k,v in pairs(defines.entity_status) do ST[v]=k end
local function fuel(e) local inv=e.get_fuel_inventory() local t='' for _,it in pairs(inv.get_contents()) do t=t..(it.name=='coal' and 'c' or 'S')..it.count end if t=='' then t='0' end if e.status~=defines.entity_status.working then t=t..'!'..(ST[e.status] or '?'):sub(1,6) end return t end
local o={'t='..game.tick}
local cu={} for _,p in pairs({{16,56},{16,59},{16,62},{16,65},{21,56},{21,59},{21,62},{21,65}}) do local e=s.find_entities_filtered{type='furnace',position=p,radius=0.6}[1] cu[#cu+1]=e and fuel(e) or 'none' end
o[#o+1]='CU '..table.concat(cu,',')
local bl={} for _,p in pairs({{43,5},{43,32},{79,40},{99,40}}) do local e=s.find_entities_filtered{type='furnace',position=p,radius=0.6}[1] bl[#bl+1]=e and fuel(e) or 'none' end
o[#o+1]='BLUE '..table.concat(bl,',')
local bo={} for _,p in pairs({{-41.5,-29},{-44.5,-29},{-52,-24.5},{-52,-20.5},{-50.5,-9}}) do local e=s.find_entities_filtered{type='boiler',position=p,radius=0.6}[1] bo[#bo+1]=fuel(e) end
o[#o+1]='WB '..table.concat(bo,',')
local c=s.find_entities_filtered{name='iron-chest',position={29.5,-12.5},radius=0.3}[1]
o[#o+1]='buf='..c.get_inventory(defines.inventory.chest).get_item_count('solid-fuel')
local ps=game.forces.player.get_item_production_statistics(s) local M=defines.flow_precision_index.one_minute
local function r(n,cat) return math.floor(ps.get_flow_count{name=n,category=cat,precision_index=M}) end
o[#o+1]='SF+'..r('solid-fuel','input')..'-'..r('solid-fuel','output')..' coal+'..r('coal','input')..'-'..r('coal','output')
rcon.print(table.concat(o,' '))
