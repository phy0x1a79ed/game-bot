-- attack-watch.lua: unit groups, units far from any nest, and unit counts per nest. ALERT lines mean an attack is forming or moving.
local s=game.surfaces[1]
local nests={{'N1',-17,-237},{'N2',46,-245},{'SW',-186,134},{'W',-252,14},{'NW',-241,-185},{'W2',-296,-39},{'S',-24,336}}
local units=s.find_entities_filtered{force='enemy',type='unit',position={0,-20},radius=420}
local out={'tick='..game.tick..' units='..#units}
local cnt={}
for _,n in ipairs(nests) do cnt[n[1]]={n=0,far=0} end
local groups={}
local far={}
for _,u in ipairs(units) do
  local best,bd='?',1e9
  for _,n in ipairs(nests) do local d=math.sqrt((u.position.x-n[2])^2+(u.position.y-n[3])^2) if d<bd then bd=d best=n[1] end end
  if cnt[best] then cnt[best].n=cnt[best].n+1 end
  if bd>45 then far[#far+1]=string.format('(%.0f,%.0f) from %s %.0f',u.position.x,u.position.y,best,bd) if cnt[best] then cnt[best].far=cnt[best].far+1 end end
  local ok,g=pcall(function() return u.unit_group end)
  if ok and g then groups[g.group_number]=g end
end
for _,n in ipairs(nests) do out[#out+1]=string.format('%s units=%d beyond45=%d',n[1],cnt[n[1]].n,cnt[n[1]].far) end
local ng=0
for k,g in pairs(groups) do ng=ng+1
  local c=g.command local cs='none'
  if c then cs=tostring(c.type) if c.destination then cs=cs..string.format(' dest=(%.0f,%.0f)',c.destination.x,c.destination.y) end end
  out[#out+1]=string.format('ALERT group#%d state=%s members=%d pos=(%.0f,%.0f) cmd=%s',k,tostring(g.state),#g.members,g.position.x,g.position.y,cs)
end
out[#out+1]='groups='..ng
if #far>0 then out[#out+1]='far units: '..table.concat(far,'; ') end
local ps=game.get_pollution_statistics(s)
local ab=0 for name,_ in pairs(ps.output_counts) do if name:find('spawner') then ab=ab+ps.get_flow_count{name=name,category='output',precision_index=defines.flow_precision_index.one_minute} end end
out[#out+1]=string.format('spawner absorption (1min avg)=%.1f/min evo=%.4f',ab,game.forces.enemy.get_evolution_factor(s))
rcon.print(table.concat(out,'\n'))
