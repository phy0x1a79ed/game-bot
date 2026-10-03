-- iron-rowc-L-g2.lua: ghost/check list for NE-IRON.md sections 8-9 (infra-a).
-- Prepend: MODE='check' or 'ghost'; PART='rowc' | 'feeder' | 'L' | 'g2'. Each part is under 2 KB.
-- rowc: row C, 7 drills (face N) + belt y=-146.5 W, x=515.5 S, side-load (516.5,-137.5).
-- feeder: upgrade marks (yellow -> fast) on the north feeder from (516.5,-137.5) to the platform end.
-- L: overflow line from the yard south ore belt end (115.5,-126.5) to x=6.5 at y=-119.5 (3 UG hops).
-- g2: splitter (6,-51.5) on x=6.5 (decon (6.5,-51.5) first, then ghost), branch to the G2 stub via the west side-load.
local s=game.surfaces[1] local N,E,S,W=0,4,8,12 local ok,bad,n=0,{},0
local DV={[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}} local feeds={}
local function feedsin(x,y) for _,v in pairs(DV) do local nx,ny=x-v[1],y-v[2] for _,e in pairs(s.find_entities_filtered{position={nx,ny},radius=0.3,type={'transport-belt','underground-belt','splitter'}}) do
  local d=DV[e.direction] if e.type~='underground-belt' or e.belt_to_ground_type=='output' then
    if math.abs(e.position.x+d[1]-x)<0.6 and math.abs(e.position.y+d[2]-y)<0.6 then feeds[#feeds+1]=e.position.x..','..e.position.y..'>'..x..','..y end end end end end
local function put(name,x,y,d,t)
  n=n+1
  if MODE=='check' and not name:find('drill') then feedsin(x,y) end
  if MODE=='check' then
    if s.can_place_entity{name=name,position={x,y},direction=d or 0,force='player',build_check_type=defines.build_check_type.ghost_place} then ok=ok+1 else bad[#bad+1]=name:sub(1,3)..x..','..y end
  else
    local a={name='entity-ghost',inner_name=name,position={x,y},direction=d or 0,force='player'} if t then a.type=t end
    if s.create_entity(a) then ok=ok+1 else bad[#bad+1]=name:sub(1,3)..x..','..y end
  end
end
local function row(x1,x2,y,d) local st=x1<=x2 and 1 or -1 for x=x1,x2,st do put('transport-belt',x,y,d) end end
local function col(x,y1,y2,d) local st=y1<=y2 and 1 or -1 for y=y1,y2,st do put('transport-belt',x,y,d) end end
--@PART rowc
if true then
  for _,x in pairs({523.5,526.5,529.5,535.5,538.5,541.5,544.5}) do put('electric-mining-drill',x,-144.5,N) end
  row(544.5,516.5,-146.5,W) col(515.5,-146.5,-138.5,S) put('transport-belt',515.5,-137.5,E)
end
--@PART feeder
if true then
  local e=s.find_entities_filtered{position={516.5,-137.5},radius=0.3,type='transport-belt'}[1] local cnt,ug=0,0
  while e and cnt<120 do cnt=cnt+1
    if e.position.x<470 then break end
    if MODE=='ghost' then e.order_upgrade{force='player',target='fast-transport-belt'} end
    local o=e.belt_neighbours.outputs[1] if not o or o.type~='transport-belt' then break end e=o end
  rcon.print('feeder belts from (516.5,-137.5): '..cnt) return
end
--@PART L
if true then
  col(116.5,-126.5,-120.5,S) put('transport-belt',116.5,-119.5,W)
  local skip={[35.5]=1,[22.5]=1,[21.5]=1,[20.5]=1,[10.5]=1,[9.5]=1}
  for x=115.5,7.5,-1 do
    if x==36.5 or x==23.5 or x==11.5 then put('underground-belt',x,-119.5,W,'input')
    elseif x==34.5 or x==19.5 or x==8.5 then put('underground-belt',x,-119.5,W,'output')
    elseif not skip[x] then put('transport-belt',x,-119.5,W) end end
end
--@PART g2
if true then
  put('splitter',6,-51.5,S) row(5.5,0.5,-50.5,W)
  put('underground-belt',-0.5,-50.5,W,'input') put('underground-belt',-2.5,-50.5,W,'output')
  put('underground-belt',-3.5,-50.5,W,'input') put('underground-belt',-5.5,-50.5,W,'output')
  put('transport-belt',-6.5,-50.5,W) col(-7.5,-50.5,-48.5,S) put('transport-belt',-7.5,-47.5,W)
  put('underground-belt',-8.5,-47.5,W,'input') put('underground-belt',-10.5,-47.5,W,'output') put('transport-belt',-11.5,-47.5,S)
end
--@PART link
if true then
  put('splitter',-12.5,-32,E)
  for _,u in pairs({{-11.5,-6.5},{-5.5,-0.5},{1.5,5.5},{6.5,8.5}}) do put('underground-belt',u[1],-32.5,E,'input') put('underground-belt',u[2],-32.5,E,'output') end
  put('transport-belt',0.5,-32.5,E) for x=9.5,11.5 do put('transport-belt',x,-32.5,E) end
end
--@PART mcu
if true then
  put('splitter',64,70.5,N)
  col(64.5,69.5,61.5,N) put('underground-belt',64.5,60.5,N,'input') put('underground-belt',64.5,55.5,N,'output')
  col(64.5,54.5,50.5,N) put('underground-belt',64.5,49.5,N,'input') put('underground-belt',64.5,44.5,N,'output')
  col(64.5,43.5,36.5,N) put('transport-belt',64.5,35.5,W) put('transport-belt',63.5,35.5,N)
  put('underground-belt',63.5,34.5,N,'input') put('underground-belt',63.5,29.5,N,'output') col(63.5,28.5,27.5,N)
end
--@TAIL
rcon.print(PART..' '..MODE..': '..n..' entities, ok '..ok..', blocked '..#bad..' '..table.concat(bad,' ')..' | existing belts pointing into new tiles: '..table.concat(feeds,' '))
