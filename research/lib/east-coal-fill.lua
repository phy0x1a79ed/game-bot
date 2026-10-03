-- east-coal-fill.lua: rebuild missing drills, field poles and collector belts of the Load Coal E field within reach of the seat (YMIN..YMAX).
local SEAT,YMIN,YMAX='seat-013b1efd',-162,-130
local s=game.surfaces[1] local L={}
for _,p in ipairs{{348.5,-146.5},{348.5,-139.5},{357.5,-146.5},{357.5,-139.5}} do L[#L+1]={'medium-electric-pole',p[1],p[2],'north'} end
for y=-150.5,-135.5,3 do L[#L+1]={'electric-mining-drill',350.5,y,'east'} L[#L+1]={'electric-mining-drill',354.5,y,'west'} end
for y=-135.5,-155.5,-1 do L[#L+1]={'transport-belt',352.5,y,'north'} end
local b,f,k=0,{},0
for _,e in ipairs(L) do if e[3]>=YMIN and e[3]<=YMAX then
 if s.find_entities_filtered{position={e[2],e[3]},name=e[1],radius=0.2}[1] then k=k+1 else
 local ok,r=pcall(remote.call,'game_bot','build',{seat=SEAT,name=e[1],x=e[2],y=e[3],direction=e[4]})
 if ok and type(r)=='table' and r.built then b=b+1 else f[#f+1]=e[1]..' '..e[2]..','..e[3]..':'..(ok and serpent.line(r) or tostring(r)):sub(1,40) end end end end
rcon.print('present '..k..' built '..b..' fail '..#f..' '..table.concat(f,'; '))
