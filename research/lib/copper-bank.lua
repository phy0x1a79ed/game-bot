-- Copper bank status (redesign): fuel per furnace, ghosts left, coal on both coal belts, IW/IE/P lane counts. Run via act.sh exec_lua SEAT path=...
local s=game.surfaces[1] local o={}
local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
for _,x in pairs{37,42} do local l=x..':' for yc=55,67,2 do local f=s.find_entity('steel-furnace',{x,yc}) l=l..' '..(f and (f.get_fuel_inventory().get_item_count()..'/'..(st[f.status] or '?'):sub(1,8)) or 'NONE') end o[#o+1]=l end
o[#o+1]='ghosts '..#s.find_entities_filtered{area={{10,48},{50,72}},name='entity-ghost'}
local function lane(x,y) local b=s.find_entities_filtered{position={x,y},radius=0.3,type={'transport-belt','underground-belt','splitter'}}[1] if not b then return x..','..y..' none' end
 local function c(i) local t={} for _,it in pairs(b.get_transport_line(i).get_contents()) do t[#t+1]=it.name:sub(1,6)..it.count end return table.concat(t,'+') end
 return x..','..y..' ['..c(1)..'|'..c(2)..']' end
for _,p in pairs{{33.5,66.5},{45.5,66.5},{34.5,60.5},{44.5,60.5},{39.5,60.5},{39.5,50.5},{19.5,50.5},{33.5,68.5},{43.5,69.5}} do o[#o+1]=lane(p[1],p[2]) end
rcon.print(table.concat(o,'\n'))
