-- turret-cover.lua: polluting or powered machines with fewer than 2 gun turrets within 17 tiles, clustered into named gaps.
local s=game.surfaces[1]
local tur=s.find_entities_filtered{type='ammo-turret',force='player'}
local out={'tick='..game.tick..' turrets='..#tur}
local un={}
local types={'mining-drill','furnace','boiler','generator','assembling-machine','lab','radar'}
local tot=0
for _,e in ipairs(s.find_entities_filtered{force='player',type=types}) do
  tot=tot+1
  local n=0
  for _,t in ipairs(tur) do local dx,dy=t.position.x-e.position.x,t.position.y-e.position.y if dx*dx+dy*dy<=17*17 then n=n+1 end end
  if n<2 then un[#un+1]={x=e.position.x,y=e.position.y,n=n,name=e.name} end
end
out[#out+1]='checked='..tot..' with<2 turrets='..#un
-- cluster by 12 tiles
local cl={}
for _,u in ipairs(un) do
  local placed=false
  for _,c in ipairs(cl) do if (c.x-u.x)^2+(c.y-u.y)^2<=144 then c.m[#c.m+1]=u placed=true break end end
  if not placed then cl[#cl+1]={x=u.x,y=u.y,m={u}} end
end
for _,c in ipairs(cl) do
  local names={} for _,m in ipairs(c.m) do names[m.name]=(names[m.name] or 0)+1 end
  local r={} for k,v in pairs(names) do r[#r+1]=k..'x'..v end
  local mn=1e9 for _,m in ipairs(c.m) do mn=math.min(mn,m.n) end
  out[#out+1]=string.format('gap near (%.0f,%.0f): %d entities (%s) min turrets in range=%d',c.x,c.y,#c.m,table.concat(r,','),mn)
end
rcon.print(table.concat(out,'\n'))
