-- Copper field redesign (industry, run 4): ghost build list. Set MODE='check'|'place' and STAGE=1|2 above this file's body.
-- Stage 1: furnace bank (x 33..46, y 50..71), coal splitters' belts, plate route to (19.5,50.5), A/B south rows. Stage 2: field drills, collectors, poles.
local s=game.surfaces[1]
local N,E,S,W=0,4,8,12
local L={}
local function add(n,x,y,d,t) L[#L+1]={n,x,y,d or N,t} end
local function belts(x1,y1,x2,y2,d) for x=math.min(x1,x2),math.max(x1,x2) do for y=math.min(y1,y2),math.max(y1,y2) do add('transport-belt',x,y,d) end end end
if STAGE==1 then
 for yc=55,67,2 do
  add('steel-furnace',37,yc) add('steel-furnace',42,yc)
  add('long-handed-inserter',35.5,yc-0.5,W) add('inserter',35.5,yc+0.5,W)
  add('inserter',38.5,yc-0.5,W) add('inserter',40.5,yc-0.5,E)
  add('long-handed-inserter',43.5,yc-0.5,E) add('inserter',43.5,yc+0.5,E)
 end
 for _,y in pairs{55.5,61.5,65.5} do add('medium-electric-pole',38.5,y) add('medium-electric-pole',40.5,y) end
 add('medium-electric-pole',35.5,70.5)
 -- plates
 belts(39.5,51.5,39.5,66.5,N) add('transport-belt',39.5,50.5,W) belts(33.5,50.5,38.5,50.5,W)
 add('underground-belt',32.5,50.5,W,'input') add('underground-belt',29.5,50.5,W,'output') belts(19.5,50.5,28.5,50.5,W)
 -- coal E (from splitter SC1 (32,51.5) right output) and coal W (from SC2 (32,53.5))
 belts(32.5,52.5,37.5,52.5,E) add('underground-belt',38.5,52.5,E,'input') add('underground-belt',40.5,52.5,E,'output')
 belts(41.5,52.5,44.5,52.5,E) belts(45.5,52.5,45.5,66.5,S)
 add('transport-belt',32.5,54.5,E) belts(33.5,54.5,33.5,66.5,S)
 -- ore inputs
 belts(34.5,54.5,34.5,68.5,N) belts(44.5,54.5,44.5,69.5,N)
 -- collector B south row -> IW
 add('transport-belt',23.5,68.5,E) belts(24.5,68.5,28.5,68.5,E)
 add('underground-belt',29.5,68.5,E,'input') add('underground-belt',31.5,68.5,E,'output') belts(32.5,68.5,33.5,68.5,E)
 -- collector A south row -> IE
 add('transport-belt',15.5,69.5,E) belts(16.5,69.5,28.5,69.5,E)
 add('underground-belt',29.5,69.5,E,'input') add('underground-belt',31.5,69.5,E,'output') belts(32.5,69.5,43.5,69.5,E)
 -- site roboport
 add('roboport',49,60) add('medium-electric-pole',46.5,62.5)
elseif STAGE==2 then
 for _,y in pairs{55.5,58.5,61.5,64.5} do
  add('electric-mining-drill',17.5,y,W) add('electric-mining-drill',21.5,y,E) add('electric-mining-drill',25.5,y,W)
 end
 belts(15.5,55.5,15.5,68.5,S) belts(23.5,55.5,23.5,67.5,S)
 add('transport-belt',18.5,50.5,S)
 for _,p in pairs{{11.5,57.5},{11.5,63.5},{19.5,57.5},{19.5,63.5},{27.5,57.5},{27.5,66.5}} do add('medium-electric-pole',p[1],p[2]) end
end
local bad,ok,placed={},0,0
for _,e in pairs(L) do
 local spec={name=e[1],position={e[2],e[3]},direction=e[4],force='player',build_check_type=defines.build_check_type.manual_ghost}
 if e[5] then spec.type=e[5] end
 local can=s.can_place_entity(spec)
 if not can then
  local ex=s.find_entities_filtered{position={e[2],e[3]},radius=0.45} local nm={} for _,x in pairs(ex) do nm[#nm+1]=x.name end
  bad[#bad+1]=e[1]..'@'..e[2]..','..e[3]..'['..table.concat(nm,'/')..']'
 else ok=ok+1
  if MODE=='place' then
   local g={name='entity-ghost',inner_name=e[1],position={e[2],e[3]},direction=e[4],force='player'}
   if e[5] then g.type=e[5] end
   if s.create_entity(g) then placed=placed+1 end
  end
 end
end
rcon.print('stage '..STAGE..' '..MODE..': total '..#L..' ok '..ok..' placed '..placed..' bad '..#bad..'\n'..table.concat(bad,' '))
