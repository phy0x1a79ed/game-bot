-- coal-feeders.lua: home coal patch drills, their destination belt, ore left under each; union ore for the block 5 column vs the rest (main belt y=-26.5).
local s=game.surfaces[1]
local ST={} for k,v in pairs(defines.entity_status) do ST[v]=k end
local ore={} for _,o in pairs(s.find_entities_filtered{type='resource',name='coal',area={{40,-80},{110,-10}}}) do ore[math.floor(o.position.x)..','..math.floor(o.position.y)]=o.amount end
local groups={} local seen={}
local out={}
for _,d in pairs(s.find_entities_filtered{type='mining-drill',force='player',area={{37,-83},{113,-7}}}) do
  local r=d.prototype.mining_drill_radius local a=0
  local dp=d.drop_position local t=s.find_entities_filtered{position=dp,radius=0.5,force='player'}[1]
  local tgt=t and string.format('%s(%.1f,%.1f)',t.name,t.position.x,t.position.y) or 'ground'
  local key=t and t.name or 'ground'
  if t and t.type=='transport-belt' then key='belt x='..t.position.x..' y='..t.position.y end
  local g=(d.position.x==74.5 and d.position.y<=-28) and 'block5-column' or 'other'
  groups[g]=groups[g] or {ore=0,n=0,rate=0}
  for x=math.floor(d.position.x-r),math.ceil(d.position.x+r)-1 do for y=math.floor(d.position.y-r),math.ceil(d.position.y+r)-1 do local k=x..','..y if ore[k] and not seen[g..k] then seen[g..k]=true groups[g].ore=groups[g].ore+ore[k] end end end
  for x=math.floor(d.position.x-r),math.ceil(d.position.x+r)-1 do for y=math.floor(d.position.y-r),math.ceil(d.position.y+r)-1 do local k=x..','..y if ore[k] then a=a+ore[k] end end end
  if a>0 then groups[g].n=groups[g].n+1 out[#out+1]=string.format('%s (%.1f,%.1f) %s ore=%d -> %s',d.name,d.position.x,d.position.y,ST[d.status],a,tgt) end
end
for g,v in pairs(groups) do out[#out+1]=g..': drills with ore '..v.n..' union ore '..v.ore end
rcon.print(table.concat(out,'\n'))
