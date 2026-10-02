local s=game.surfaces[1]
local out={}
local evo=game.forces.enemy.get_evolution_factor(s)
local units=s.find_entities_filtered{force='enemy',type='unit',position={0,-20},radius=420}
local byname={}
for _,u in ipairs(units) do byname[u.name]=(byname[u.name] or 0)+1 end
local nm={} for k,v in pairs(byname) do nm[#nm+1]=k..'='..v end table.sort(nm)
out[#out+1]=string.format('tick=%d evo=%.4f units=%d [%s]',game.tick,evo,#units,table.concat(nm,' '))
if byname['medium-biter'] or byname['medium-spitter'] then out[#out+1]='ALERT MEDIUM units present' end
local nests={{'N1',-17,-237},{'N2',46,-245},{'SW',-186,134},{'W',-252,14},{'NW',-241,-185},{'W2',-296,-39},{'S',-24,336}}
local c={} for _,n in ipairs(nests) do c[n[1]]=0 end
local near={} -- units within 120 of the base centre (-10,0)
for _,u in ipairs(units) do
  local best,bd='?',1e9
  for _,n in ipairs(nests) do local d=math.sqrt((u.position.x-n[2])^2+(u.position.y-n[3])^2) if d<bd then bd=d best=n[1] end end
  if bd<=60 then c[best]=c[best]+1 end
  local d0=math.sqrt((u.position.x+10)^2+(u.position.y)^2)
  if d0<130 then near[#near+1]=string.format('(%.0f,%.0f)',u.position.x,u.position.y) end
end
local t={} for _,n in ipairs(nests) do t[#t+1]=n[1]..'='..c[n[1]] end
out[#out+1]='near-nest(60): '..table.concat(t,' ')
if #near>0 then out[#out+1]='ALERT units within 130 of base: '..#near..' '..table.concat(near,' ',1,math.min(#near,12)) end
-- spawners within 260 of base
local sp=s.find_entities_filtered{force='enemy',type='unit-spawner',position={-10,-20},radius=330}
local mind,minp=1e9,nil
for _,e in ipairs(sp) do local d=math.sqrt((e.position.x+10)^2+(e.position.y+20)^2) if d<mind then mind=d minp=e.position end end
out[#out+1]=string.format('spawners within 330: %d nearest %.0f at (%.0f,%.0f)',#sp,mind,minp and minp.x or 0,minp and minp.y or 0)
-- turrets
local tur=s.find_entities_filtered{name='gun-turret',force='player'}
local low={} local tot=0
for _,e in ipairs(tur) do
  local inv=e.get_inventory(defines.inventory.turret_ammo)
  local n=0 if inv then n=inv.get_item_count() end
  tot=tot+1
  if n<15 then low[#low+1]=string.format('(%.0f,%.0f)=%d hp%.0f',e.position.x,e.position.y,n,e.health) end
end
out[#out+1]='turrets='..tot..' below15: '..(#low>0 and table.concat(low,' ') or 'none')
if #low>0 then out[#out+1]='ALERT low-ammo turrets: '..#low end
-- turret damage
local dmg={} for _,e in ipairs(tur) do if e.health<e.prototype.get_max_health(e.quality)*0.8 then dmg[#dmg+1]=string.format('(%.0f,%.0f) hp%.0f',e.position.x,e.position.y,e.health) end end
if #dmg>0 then out[#out+1]='damaged turrets: '..table.concat(dmg,' ') end
-- machines with 0 turrets within 18
local ents=s.find_entities_filtered{force='player',type={'mining-drill','furnace','assembling-machine','lab','generator','boiler','radar'}}
local nocover={}
for _,e in ipairs(ents) do
  local n=0 for _,t in ipairs(tur) do local dx,dy=t.position.x-e.position.x,t.position.y-e.position.y if dx*dx+dy*dy<=18*18 then n=n+1 end end
  if n==0 then nocover[#nocover+1]=string.format('%s(%.0f,%.0f)',e.name,e.position.x,e.position.y) end
end
out[#out+1]='no-cover machines: '..(#nocover>0 and table.concat(nocover,' ',1,math.min(#nocover,15)) or 'none')
if #nocover>0 then out[#out+1]='ALERT flank with no cover: '..#nocover end
local ps=game.get_pollution_statistics(s)
local ab=0 for name,_ in pairs(ps.output_counts) do if name:find('spawner') then ab=ab+ps.get_flow_count{name=name,category='output',precision_index=defines.flow_precision_index.one_minute} end end
out[#out+1]=string.format('absorb=%.1f/min',ab)
rcon.print(table.concat(out,'\n'))
