-- ec-measure.lua: one sample of every AM1 in the EC block (x4..24, y34..43): tick, recipe, products_finished, status.
local s=game.surfaces[1]
local o={'tick '..game.tick}
for _,m in pairs(s.find_entities_filtered{name='assembling-machine-1',area={{4,33},{24,44}}}) do
  o[#o+1]=string.format('%.1f,%.1f %s %d %s',m.position.x,m.position.y,m.get_recipe() and m.get_recipe().name or '-',m.products_finished,tostring(m.status))
end
local c=s.find_entities_filtered{name='iron-chest',position={24.5,46.5},radius=0.3}[1]
o[#o+1]='buf EC '..(c and c.get_inventory(defines.inventory.chest).get_item_count('electronic-circuit') or -1)
local b38={}
for x=29.5,5.5,-4 do local be=s.find_entities_filtered{name='transport-belt',position={x,38.5},radius=0.3}[1]
 if be then local t={} for i=1,2 do for _,c2 in pairs(be.get_transport_line(i).get_contents()) do t[#t+1]=i..':'..c2.name:sub(1,4)..c2.count end end b38[#b38+1]=x..'='..table.concat(t,'/') end end
o[#o+1]='y38.5 '..table.concat(b38,' ')
rcon.print(table.concat(o,'\n'))
