-- item-map.lua: per-tile map of what belts carry in [X0,X1)x[Y0,Y1). Run via item-map.sh. Upper case = both lanes.
-- i iron, c copper, s steel, g gear, e green circuit, r red circuit, k coal, p plastic, b battery, u sulfur, o ore, x mixed, - empty belt, # other entity
local s=game.surfaces[1] local x0,y0,x1,y1=X0,Y0,X1,Y1
local code={['iron-plate']='i',['copper-plate']='c',['steel-plate']='s',['iron-gear-wheel']='g',['electronic-circuit']='e',['advanced-circuit']='r',coal='k',['plastic-bar']='p',battery='b',sulfur='u',['iron-ore']='o',['copper-ore']='o',stone='o',['stone-brick']='w',['pipe']='/',['engine-unit']='n',['automation-science-pack']='1',['logistic-science-pack']='2',['chemical-science-pack']='3',['military-science-pack']='4',['solid-fuel']='f',['piercing-rounds-magazine']='m',['firearm-magazine']='y'}
local g={} for y=y0,y1-1 do g[y]={} for x=x0,x1-1 do g[y][x]='.' end end
local leg={}
for _,e in pairs(s.find_entities_filtered{area={{x0,y0},{x1,y1}}}) do
 local x,y=math.floor(e.position.x),math.floor(e.position.y)
 if g[y] and g[y][x] then
  if e.type=='transport-belt' or e.type=='underground-belt' or e.type=='splitter' then
   local seen={} local n=0 local both=0
   for i=1,2 do local c=e.get_transport_line(i).get_contents() if #c>0 then both=both+1 end for _,it in pairs(c) do if not seen[it.name] then seen[it.name]=true n=n+1 end end end
   local ch='-' if n>1 then ch='x' elseif n==1 then local nm=next(seen) ch=code[nm] or '?' if ch=='?' then leg[nm]=true end if both==2 then ch=ch:upper() end end
   g[y][x]=ch
  elseif e.type~='resource' and e.type~='character' and e.type~='tree' then g[y][x]='#' end
 end
end
local h='     ' for x=x0,x1-1 do h=h..(math.abs(x)%10) end rcon.print(h)
for y=y0,y1-1 do local r=string.format('%4d ',y) for x=x0,x1-1 do r=r..g[y][x] end rcon.print(r) end
for k,_ in pairs(leg) do rcon.print('? = '..k) end
