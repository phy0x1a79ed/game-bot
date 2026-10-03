-- east-stone-field.lua: Load Stone E field. 20 drills (pairs belt x=469.5 / x=480.5), lane-merge collector (T at 462.5,-148.5),
-- belt y=-156.5 west to x=426.5, 18 chest-buffered loader columns x 426.5..446.5 (poles at 429.5/436.5/443.5), 8 SE turrets.
-- MODE=check|build ; X0..X1 limits the entities handled (build window). Inserters are rotated to south after building.
local MODE,X0,X1,SEAT='check',-1e9,1e9,'seat-013b1efd'
local s=game.surfaces[1] local N,E,S,W=0,4,8,12
local L={}
local function a(n,x,y,d) L[#L+1]={n,x,y,d or N} end
for _,p in ipairs{{465.5,-166.5},{465.5,-160.5},{465.5,-154.5},{473.5,-166.5},{473.5,-160.5},{473.5,-154.5},{476.5,-162.5},{476.5,-156.5},{476.5,-150.5},{484.5,-162.5},{484.5,-156.5},{484.5,-150.5},{429.5,-158.5},{436.5,-158.5},{443.5,-158.5}} do a('medium-electric-pole',p[1],p[2]) end
for _,y in ipairs{-168.5,-165.5,-162.5,-159.5,-156.5} do a('electric-mining-drill',467.5,y,E) a('electric-mining-drill',471.5,y,W) end
for _,y in ipairs{-163.5,-160.5,-157.5,-154.5,-151.5} do a('electric-mining-drill',478.5,y,E) a('electric-mining-drill',482.5,y,W) end
for y=-168.5,-150.5 do a('transport-belt',469.5,y,S) end
for x=469.5,463.5,-1 do a('transport-belt',x,-149.5,W) end a('transport-belt',462.5,-149.5,S)
for y=-163.5,-148.5 do a('transport-belt',480.5,y,S) end
for x=480.5,463.5,-1 do a('transport-belt',x,-147.5,W) end a('transport-belt',462.5,-147.5,N)
for x=462.5,450.5,-1 do a('transport-belt',x,-148.5,W) end
for y=-148.5,-155.5,-1 do a('transport-belt',449.5,y,N) end
for x=449.5,426.5,-1 do a('transport-belt',x,-156.5,W) end
for x=426.5,446.5 do if x~=429.5 and x~=436.5 and x~=443.5 then
 a('iron-chest',x,-158.5) a('inserter',x,-157.5) a('fast-inserter',x,-159.5) end end
for _,t in ipairs{{486,-146},{488,-146},{490,-146},{492,-146},{486,-144},{488,-144},{490,-144},{492,-144}} do a('gun-turret',t[1],t[2]) end
local bad,n,built,fail={},0,0,{}
for _,e in ipairs(L) do if e[2]>=X0 and e[2]<=X1 then n=n+1
 if MODE=='check' then
  if not s.can_place_entity{name=e[1],position={e[2],e[3]},direction=e[4],force='player',build_check_type=defines.build_check_type.ghost_place} then bad[#bad+1]=e[1]..' '..e[2]..','..e[3] end
 else
  if s.find_entities_filtered{position={e[2],e[3]},name=e[1],radius=0.2}[1] then built=built+1 else
  local nm=e[1] local dd=({[0]='north','east','south'})[0]
  local dn=({[N]='north',[E]='east',[S]='south',[W]='west'})[e[4]]
  local ok,r=pcall(remote.call,'game_bot','build',{seat=SEAT,name=nm,x=e[2],y=e[3],direction=dn})
  if ok and type(r)=='table' and r.built then built=built+1 else fail[#fail+1]=nm..' '..e[2]..','..e[3]..':'..(ok and serpent.line(r) or tostring(r)):sub(1,50) end end
 end end end
if MODE=='build' then
 for _,i in pairs(s.find_entities_filtered{area={{X0-1,-160},{X1+1,-157}},name={'inserter','fast-inserter'}}) do if i.direction~=S then i.direction=S end end
end
rcon.print('tick '..game.tick..' MODE '..MODE..' ents '..n..' built '..built..' bad '..#bad..' '..table.concat(bad,'; ')..' FAIL '..#fail..' '..table.concat(fail,'; '))
