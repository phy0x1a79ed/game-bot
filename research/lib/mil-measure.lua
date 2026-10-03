local s=game.surfaces[1] local o={'tick '..game.tick}
for _,p in ipairs({{'M',44.5,-21.5},{'M2',45.5,-17.5},{'G',49.5,-22.5},{'G2',52.5,-20.5}}) do local e=s.find_entities_filtered{type='assembling-machine',position={p[2],p[3]},radius=0.3}[1] o[#o+1]=p[1]..'='..e.products_finished end
local bl={} for _,e in ipairs(s.find_entities_filtered{area={{54,-24},{86,-20}},name='boiler'}) do bl[#bl+1]=e.get_fuel_inventory().get_item_count() end o[#o+1]='boilers5 fuel '..table.concat(bl,',')
local st=game.forces.player.get_item_production_statistics(s) local function f(n,c) return math.floor(st.get_flow_count{name=n,category=c,precision_index=defines.flow_precision_index.one_minute,count=true}) end
o[#o+1]='coal made/used 1m '..f('coal','input')..'/'..f('coal','output')..' mil made 1m '..f('military-science-pack','input')
local n=0 for x=40.5,53.5 do local b=s.find_entities_filtered{type={'transport-belt','underground-belt'},position={x,-26.5},radius=0.3}[1] if b then n=n+b.get_transport_line(1).get_item_count()+b.get_transport_line(2).get_item_count() end end o[#o+1]='mainbelt x40-53 items='..n
rcon.print(table.concat(o,' '))
