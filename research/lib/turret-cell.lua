-- turret-cell.lua MODE=check|place|read: gun-turret cell W of Spine A tail (M0b), 2 AM2 -> passive provider (-23.5,50.5)
-- inserter direction here = PICKUP side (drop is opposite): the list below is written by drop direction, so after the ghosts are built rotate each new inserter 180 deg
local s=game.surfaces[1] local N,E,S,W=0,4,8,12 local L={}
local function a(n,x,y,d,t,r) L[#L+1]={n,x,y,d or N,t,r} end
a('underground-belt',-15.5,50.5,S,'input') a('underground-belt',-15.5,52.5,S,'output')
for x=-15.5,-28.5,-1 do a('transport-belt',x,53.5,W) end
a('fast-inserter',-13.5,52.5,S) a('transport-belt',-13.5,53.5,S)
for x=-13.5,-28.5,-1 do a('transport-belt',x,54.5,W) end
for _,c in pairs{-20.5,-26.5} do
 a('assembling-machine-2',c,50.5,N,nil,'gun-turret')
 a('fast-inserter',c+1,52.5,N) a('fast-inserter',c,52.5,N) a('long-handed-inserter',c-1,52.5,N)
end
a('fast-inserter',-22.5,50.5,W) a('fast-inserter',-24.5,50.5,E)
a('passive-provider-chest',-23.5,50.5) a('passive-provider-chest',-23.5,48.5)
for _,x in pairs{-18.5,-23.5,-28.5} do a('medium-electric-pole',x,52.5) end
local bad,placed={},0
if MODE=='read' then
 local o={game.tick}
 for _,c in pairs{-20.5,-26.5} do local m=s.find_entity('assembling-machine-2',{c,50.5})
  if m then o[#o+1]=m.status..' made '..m.products_finished end end
 for _,p in pairs{{-23.5,50.5},{-23.5,48.5}} do local e=s.find_entity('passive-provider-chest',p)
  if e then local t={} for k,q in pairs(e.get_inventory(1).get_contents()) do t[#t+1]=(q.name or k)..':'..(q.count or q) end o[#o+1]=table.concat(t,',') end end
 rcon.print(table.concat(o,' ')) return end
for _,e in pairs(L) do
 local sp={name=e[1],position={e[2],e[3]},direction=e[4],force='player',build_check_type=defines.build_check_type.manual_ghost}
 if e[5] then sp.type=e[5] end
 if not s.can_place_entity(sp) then local nm={} for _,x in pairs(s.find_entities_filtered{position={e[2],e[3]},radius=0.45}) do nm[#nm+1]=x.name end
  bad[#bad+1]=e[1]..'@'..e[2]..','..e[3]..'['..table.concat(nm,'/')..']'
 elseif MODE=='place' then
  local g={name='entity-ghost',inner_name=e[1],position={e[2],e[3]},direction=e[4],force='player'} if e[5] then g.type=e[5] end
  local gh=s.create_entity(g) if gh then placed=placed+1 if e[6] then pcall(function() gh.set_recipe(e[6]) end) end end end
end
rcon.print(MODE..' total '..#L..' placed '..placed..' bad '..#bad..' '..table.concat(bad,' '))
