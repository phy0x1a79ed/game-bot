-- east-coal.lua: east coal line (204,-66) status: drills, density on the junction y=-49.5 x80..86 -> coal/min, turret ammo, chest
local s=game.surfaces[1] local o={'tick '..game.tick}
local w=0 local n=0 for _,d in ipairs(s.find_entities_filtered{name='electric-mining-drill',area={{196,-71},{213,-62}}}) do n=n+1 if d.status==defines.entity_status.working then w=w+1 end end o[#o+1]='drills working '..w..'/'..n
local it,t=0,0 for x=80.5,85.5 do local b=s.find_entities_filtered{type='transport-belt',position={x,-49.5},radius=0.3}[1] if b then t=t+1 it=it+b.get_transport_line(1).get_item_count()+b.get_transport_line(2).get_item_count() end end
o[#o+1]=string.format('junction %d items/%d tiles = %.0f coal/min',it,t,it/t*1.875*60)
local a={} for _,y in ipairs({-73,-70,-67,-64,-61,-58}) do local g=s.find_entities_filtered{name='gun-turret',position={216,y},radius=0.5}[1] a[#a+1]=g and g.get_item_count('piercing-rounds-magazine') or 'X' end o[#o+1]='turrets '..table.concat(a,',')
local c=s.find_entities_filtered{name='iron-chest',position={213.5,-76.5},radius=0.3}[1] o[#o+1]='ammochest '..(c and c.get_item_count('piercing-rounds-magazine') or 'X')
o[#o+1]='enemies<60 '..#s.find_entities_filtered{force='enemy',position={205,-66},radius=60}
local st=game.forces.player.get_item_production_statistics(s) o[#o+1]='coal made/used 1m '..math.floor(st.get_flow_count{name='coal',category='input',precision_index=defines.flow_precision_index.one_minute,count=true})..'/'..math.floor(st.get_flow_count{name='coal',category='output',precision_index=defines.flow_precision_index.one_minute,count=true})
rcon.print(table.concat(o,' '))
