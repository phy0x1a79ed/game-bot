-- infrab-r3.lua: R3a robot cell layout (fresh, x 66..105, y -7..26). MODE: check | list. GROUP filters (nil = all).
local MODE='MODE_V' local GROUP='GROUP_V'
local E={} local function a(g,n,x,y,d,extra) E[#E+1]={g=g,n=n,x=x,y=y,d=d or 'north',t=extra} end
local B='transport-belt'
-- feed: splitter on M', y=25.5/24.5 east, x=105.5 north, K0a west on y=-6.5
a('feed','splitter',92.5,26,'east') a('feed',B,93.5,25.5,'east') a('feed',B,94.5,25.5,'north')
for x=94.5,104.5 do a('feed',B,x,24.5,'east') end
for y=24.5,10.5,-1 do a('feed',B,105.5,y,'north') end
a('feed','splitter',105,9.5,'north')
for y=8.5,-5.5,-1 do a('feed',B,105.5,y,'north') end
a('feed',B,105.5,-6.5,'west') for x=104.5,69.5,-1 do a('k0a',B,x,-6.5,'west') end
a('k2b',B,104.5,8.5,'north') for x=104.5,86.5,-1 do a('k2b',B,x,7.5,'west') end
for x=66.5,93.5 do a('k0b',B,x,-5.5,'east') end
for y=-2.5,-4.5,-1 do a('k0b',B,67.5,y,'north') end
for x=79.5,103.5 do a('k1',B,x,0.5,'west') end
for x=79.5,97.5 do a('k1',B,x,1.5,'west') end
for x=79.5,94.5 do a('k2a',B,x,8.5,'east') end
a('k2a','underground-belt',95.5,8.5,'east','input') a('k2a','underground-belt',97.5,8.5,'east','output')
a('k2a',B,98.5,8.5,'east') a('k2a',B,99.5,8.5,'east')
-- row A machines (y=-2.5)
a('rowA','assembling-machine-1',70.5,-2.5) a('rowA','assembling-machine-1',73.5,-2.5)
a('rowA','assembling-machine-2',80.5,-2.5) a('rowA','assembling-machine-2',84.5,-2.5)
a('rowA','electric-furnace',88.5,-2.5) a('rowA','assembling-machine-2',92.5,-2.5)
a('rowA','assembling-machine-2',96.5,-2.5) a('rowA','assembling-machine-2',99.5,-2.5)
a('rowA','assembling-machine-1',103.5,-2.5)
-- row B machines (y=4.5)
a('rowB','assembling-machine-2',80.5,4.5) a('rowB','assembling-machine-2',83.5,4.5)
a('rowB','electric-furnace',87.5,4.5) a('rowB','assembling-machine-2',91.5,4.5)
a('rowB','chemical-plant',95.5,4.5,'south') a('rowB','assembling-machine-1',99.5,4.5)
a('rowB','passive-provider-chest',102.5,4.5) a('rowB','iron-chest',67.5,-6.5) a('rowB','iron-chest',84.5,7.5)
-- inserters (direction = pickup side)
local I,L='inserter','long-handed-inserter'
for _,v in pairs({{I,68.5,-2.5,'east'},{L,70.5,-4.5,'north'},{L,72.5,-4.5,'north'},{I,73.5,-4.5,'south'},
 {I,79.5,-0.5,'south'},{L,80.5,-0.5,'north'},{I,82.5,-2.5,'east'},{I,84.5,-4.5,'north'},{I,86.5,-2.5,'east'},
 {L,89.5,-4.5,'north'},{I,90.5,-2.5,'west'},{I,92.5,-4.5,'north'},{I,94.5,-2.5,'west'},{I,95.5,-0.5,'south'},
 {L,96.5,-0.5,'north'},{L,99.5,-4.5,'north'},{I,101.5,-2.5,'west'},{L,103.5,-4.5,'north'},{I,103.5,-0.5,'north'},
 {I,68.5,-6.5,'east'}}) do a('insA',v[1],v[2],v[3],v[4]) end
for _,v in pairs({{I,79.5,2.5,'north'},{L,80.5,2.5,'north'},{L,80.5,6.5,'north'},{I,82.5,2.5,'north'},{L,83.5,2.5,'north'},
 {L,83.5,6.5,'north'},{I,85.5,4.5,'east'},{I,87.5,6.5,'south'},{I,87.5,2.5,'south'},{I,89.5,4.5,'west'},
 {I,90.5,2.5,'north'},{L,91.5,2.5,'north'},{L,91.5,6.5,'north'},{I,95.5,6.5,'south'},{L,95.5,2.5,'south'},
 {L,99.5,2.5,'north'},{L,99.5,6.5,'south'},{I,101.5,4.5,'west'},{I,85.5,7.5,'east'}}) do a('insB',v[1],v[2],v[3],v[4]) end
-- lube
local P,G='pipe','pipe-to-ground'
for _,v in pairs({{G,78.5,1.5,'south'},{G,78.5,-3.5,'north'},{P,78.5,-4.5},{P,79.5,-4.5},{P,80.5,-4.5},{G,81.5,-4.5,'west'},
 {G,87.5,-4.5,'east'},{G,88.5,-4.5,'west'},{G,95.5,-4.5,'east'},{P,96.5,-4.5}}) do a('lube',v[1],v[2],v[3],v[4]) end
-- acid
for _,v in pairs({{P,73.5,24.5},{G,73.5,23.5,'south'},{G,73.5,13.5,'north'},{P,73.5,12.5},{P,72.5,12.5},{P,72.5,11.5},{P,72.5,10.5},
 {G,73.5,10.5,'west'},{G,83.5,10.5,'east'},{G,84.5,10.5,'west'},{G,92.5,10.5,'east'},{P,93.5,10.5},{P,93.5,11.5},{P,93.5,12.5},{P,94.5,12.5},{G,94.5,11.5,'south'},{G,94.5,6.5,'north'}}) do a('acid',v[1],v[2],v[3],v[4]) end
-- poles
for _,v in pairs({{71.5,-4.5},{78.5,-2.5},{82.5,-1.5},{86.5,-1.5},{90.5,-1.5},{94.5,-1.5},{101.5,-1.5},{81.5,2.5},{81.5,6.5},{85.5,5.5},{89.5,5.5},{93.5,4.5},{97.5,4.5},{67.5,-1.5},{103.5,4.5}}) do a('pole','medium-electric-pole',v[1],v[2]) end
local s=game.surfaces[1] local D={north=defines.direction.north,east=defines.direction.east,south=defines.direction.south,west=defines.direction.west}
local bad,ok,cnt={},0,{}
for _,e in pairs(E) do if GROUP=='' or GROUP==e.g then
 cnt[e.n]=(cnt[e.n] or 0)+1
 if MODE=='check' then
  local ex=s.find_entities_filtered{position={e.x,e.y},name=e.n}[1]
  if ex and ex.position.x==e.x and ex.position.y==e.y then ok=ok+1 elseif s.can_place_entity{name=e.n,position={e.x,e.y},direction=D[e.d],force='player'} then ok=ok+1
  else local b=s.find_entities_filtered{position={e.x,e.y},radius=0.6} local nm={} for _,q in pairs(b) do nm[#nm+1]=q.name end bad[#bad+1]=e.n..'('..e.x..','..e.y..')['..table.concat(nm,'/')..']' end
 end end end
local c={} for n,k in pairs(cnt) do c[#c+1]=n..'='..k end
rcon.print('ok '..ok..' bad '..#bad..': '..table.concat(bad,' ')..'\nCOUNTS '..table.concat(c,' '))
if MODE=='power' then
 local poles={} for _,e in pairs(E) do if e.n=='medium-electric-pole' then poles[#poles+1]={e.x,e.y} end end
 for _,p in pairs(s.find_entities_filtered{type='electric-pole',area={{60,-12},{110,30}}}) do poles[#poles+1]={p.position.x,p.position.y,p.name} end
 local miss={}
 for _,e in pairs(E) do local pr=prototypes.entity[e.n] if pr.electric_energy_source_prototype or e.n:find('inserter') or e.n:find('assembl') or e.n:find('furnace') or e.n:find('chemical') then
  local bb=pr.collision_box local hw=math.max(-bb.left_top.x,bb.right_bottom.x) local hh=math.max(-bb.left_top.y,bb.right_bottom.y)
  local cov=false for _,p in pairs(poles) do local r=(p[3]=='small-electric-pole') and 2.5 or 3.5 if math.abs(e.x-p[1])<r+hw and math.abs(e.y-p[2])<r+hh then cov=true break end end
  if not cov then miss[#miss+1]=e.n..'('..e.x..','..e.y..')' end end end
 rcon.print('unpowered: '..table.concat(miss,' '))
end
if MODE=='ghost' then
 local FIL={['89.5,-4.5']='iron-plate',['87.5,6.5']='iron-plate',['68.5,-6.5']='stone',['85.5,7.5']='stone'}
 local n,skip,err=0,0,{}
 for _,e in pairs(E) do if GROUP=='' or GROUP==e.g then
  local ex=s.find_entities_filtered{position={e.x,e.y},name=e.n}[1]
  local gh=s.find_entities_filtered{position={e.x,e.y},ghost_name=e.n}[1]
  if (ex and ex.position.x==e.x and ex.position.y==e.y) or gh then skip=skip+1 else
   local ok,g=pcall(s.create_entity,{name='entity-ghost',inner_name=e.n,position={e.x,e.y},direction=D[e.d],force='player',type=e.t})
   if ok and g then n=n+1 local f=FIL[e.x..','..e.y] if f and e.n:find('inserter') then pcall(function() g.use_filters=true g.set_filter(1,f) end) end
   else err[#err+1]=e.n..'('..e.x..','..e.y..')' end end end end
 rcon.print('ghosts '..n..' skipped '..skip..' failed '..#err..' '..table.concat(err,' '))
end
