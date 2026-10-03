local s=game.surfaces[1]
local N,E,S,W=0,4,8,12
local L={}
local function add(n,x,y,d,t,r) L[#L+1]={n,x,y,d or N,t,r} end
add('fast-inserter',8.5,44.5,E)
add('transport-belt',7.5,44.5,N)
for x=-3.5,7.5 do add('transport-belt',x,43.5,W) end
add('assembling-machine-2',4.5,46.5,N,nil,'advanced-circuit')
add('assembling-machine-2',-3.5,46.5,N,nil,'advanced-circuit')
add('assembling-machine-1',0.5,48.5,N,nil,'copper-cable')
add('fast-inserter',4.5,44.5,N) add('fast-inserter',-3.5,44.5,N)
add('fast-inserter',0.5,50.5,S)
add('fast-inserter',2.5,47.5,W) add('fast-inserter',-1.5,47.5,E)
add('fast-inserter',4.5,48.5,S) add('fast-inserter',-3.5,48.5,S)
add('transport-belt',3.5,49.5,W)
add('underground-belt',2.5,49.5,W,'input') add('underground-belt',-1.5,49.5,W,'output')
add('transport-belt',-2.5,49.5,W) add('transport-belt',-3.5,49.5,W)
add('fast-inserter',6.5,46.5,W) add('steel-chest',7.5,46.5)
add('fast-inserter',-5.5,46.5,E) add('iron-chest',-6.5,46.5)
add('medium-electric-pole',2.5,45.5) add('medium-electric-pole',-1.5,45.5) add('medium-electric-pole',-5.5,44.5) add('medium-electric-pole',3.5,50.5)
local bad,placed={},0
for _,e in pairs(L) do
  local spec={name=e[1],position={e[2],e[3]},direction=e[4],force='player',build_check_type=defines.build_check_type.manual_ghost}
  if e[5] then spec.type=e[5] end
  if not s.can_place_entity(spec) then
    local nm={} for _,x in pairs(s.find_entities_filtered{position={e[2],e[3]},radius=0.45}) do nm[#nm+1]=x.name end
    bad[#bad+1]=e[1]..'@'..e[2]..','..e[3]..'['..table.concat(nm,'/')..']'
  elseif MODE=='place' then
    local g={name='entity-ghost',inner_name=e[1],position={e[2],e[3]},direction=e[4],force='player'}
    if e[5] then g.type=e[5] end
    local gh=s.create_entity(g)
    if gh then placed=placed+1 if e[6] then pcall(function() gh.set_recipe(e[6]) end) end end
  end
end
rcon.print(MODE..' total '..#L..' placed '..placed..' bad '..#bad..' '..table.concat(bad,' '))
