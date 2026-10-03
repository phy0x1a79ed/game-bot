local s=game.surfaces[1]
local A={{-75,-100},{5,-30}}
local cov={}
for _,d in pairs(s.find_entities_filtered{type="mining-drill",force="player",area={{A[1][1]-3,A[1][2]-3},{A[2][1]+3,A[2][2]+3}}}) do
  local r=d.prototype.mining_drill_radius
  for x=math.floor(d.position.x-r),math.ceil(d.position.x+r)-1 do for y=math.floor(d.position.y-r),math.ceil(d.position.y+r)-1 do cov[x..","..y]=true end end
end
local g={} local tot,un=0,0
for _,o in pairs(s.find_entities_filtered{type="resource",name="iron-ore",area=A}) do
  local x,y=math.floor(o.position.x),math.floor(o.position.y)
  g[y]=g[y] or {}
  tot=tot+o.amount
  if cov[x..","..y] then g[y][x]='.' else un=un+o.amount g[y][x]=tostring(math.min(9,math.floor(o.amount/200))) end
end
local L={"total "..tot.." uncovered "..un.." (digit=amount/200, '.'=covered) x from -75"}
for y=-100,-30 do if g[y] then local r={} for x=-75,4 do r[#r+1]=g[y][x] or ' ' end L[#L+1]=string.format("%4d %s",y,table.concat(r)) end end
rcon.print(table.concat(L,"\n"))
