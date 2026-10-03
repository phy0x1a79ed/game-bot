local s=game.surfaces[1]
local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
local A={{-52,-72},{-4,-36}}
local cov={}
local out={}
local nd=0
for _,d in pairs(s.find_entities_filtered{type="mining-drill",force="player",area=A}) do
  local r=d.prototype.mining_drill_radius
  for x=math.floor(d.position.x-r),math.ceil(d.position.x+r)-1 do for y=math.floor(d.position.y-r),math.ceil(d.position.y+r)-1 do cov[x..","..y]=true end end
  local dt=d.drop_target
  out[#out+1]=string.format("D %s %.1f,%.1f dir%d %s -> %s",d.name:sub(1,3),d.position.x,d.position.y,d.direction,st[d.status] or "?",dt and (dt.name.."@"..dt.position.x..","..dt.position.y) or "ground")
end
local tiles={} local cn,un,ca,ua=0,0,0,0
for _,o in pairs(s.find_entities_filtered{type="resource",name="iron-ore",area=A}) do
  local k=math.floor(o.position.x)..","..math.floor(o.position.y)
  if cov[k] then cn=cn+1 ca=ca+o.amount else un=un+1 ua=ua+o.amount tiles[#tiles+1]=k..":"..o.amount end
end
out[#out+1]=string.format("COV %d tiles %d ore | UNCOV %d tiles %d ore",cn,ca,un,ua)
local f={}
for _,e in pairs(s.find_entities_filtered{type="furnace",force="player",area=A}) do
  f[#f+1]=string.format("F %s %.1f,%.1f %s",e.name:sub(1,5),e.position.x,e.position.y,st[e.status] or "?")
end
out[#out+1]=table.concat(f,"\n")
rcon.print(table.concat(out,"\n"))
local t2={} for _,t in ipairs(tiles) do t2[#t2+1]=t end
