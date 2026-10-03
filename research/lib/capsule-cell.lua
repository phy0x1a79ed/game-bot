-- capsule-cell.lua: read the guard capsule cell (x 32..41, y -18..-5) and its feeds
local s=game.surfaces[1] local o={'tick '..game.tick}
local ST={} for k,v in pairs(defines.entity_status) do ST[v]=k end
local function m(n,x,y,tag) local e=s.find_entities_filtered{position={x,y},name=n}[1] if not e then o[#o+1]=tag..' MISSING' return end
  local r=e.type=='assembling-machine' and e.get_recipe() and e.get_recipe().name or ''
  local fin=e.products_finished or 0
  local inp=e.get_inventory(defines.inventory.crafter_input or defines.inventory.furnace_source or 2)
  local t={} if inp then for _,q in pairs(inp.get_contents()) do t[#t+1]=q.name:sub(1,8)..q.count end end
  local out=e.get_output_inventory() local u={} for _,q in pairs(out.get_contents()) do u[#u+1]=q.name:sub(1,8)..q.count end
  o[#o+1]=string.format('%s %s %s made %d in[%s] out[%s]',tag,r,ST[e.status] or e.status,fin,table.concat(t,','),table.concat(u,',')) end
m('assembling-machine-2',37.5,-16.5,'D') m('assembling-machine-1',37.5,-12.5,'G') m('assembling-machine-2',37.5,-9.5,'P') m('steel-furnace',37,-6,'S')
for _,c in pairs{{40.5,-17.5,'Dkit'},{40.5,-10.5,'Pkit'}} do local e=s.find_entity('iron-chest',{c[1],c[2]}) local t={} for _,q in pairs(e.get_inventory(1).get_contents()) do t[#t+1]=q.name..':'..q.count end o[#o+1]=c[3]..' '..table.concat(t,',') end
local function b(x,y,tag) local e=s.find_entities_filtered{position={x,y},type={'transport-belt','underground-belt'}}[1] if not e then o[#o+1]=tag..' none' return end local t={} for i=1,2 do local c={} for _,q in pairs(e.get_transport_line(i).get_contents()) do c[#c+1]=q.name:sub(1,8)..q.count end t[#t+1]='L'..i..'['..table.concat(c,'+')..']' end o[#o+1]=tag..' '..table.concat(t,' ') end
b(23.5,-4.5,'A@23.5,-4.5') b(33.5,-5.5,'A@33.5,-5.5') b(34.5,-11.5,'A@34.5,-11.5') b(34.5,-17.5,'A end') b(33.5,-9.5,'C end') b(24.5,-7.5,'iron y-7.5@24.5') b(26.5,-7.5,'iron@26.5') b(27.5,-12.5,'iron x27.5') b(42.5,-15.5,'pierce belt') b(44.5,-14.5,'pierce end')
local m2=s.find_entity('assembling-machine-2',{45.5,-17.5}) o[#o+1]='M2 '..(ST[m2.status] or m2.status)..' made '..m2.products_finished
rcon.print(table.concat(o,'\n'))
