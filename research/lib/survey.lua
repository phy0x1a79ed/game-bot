-- survey.lua: machine counts by status, mined patch reserves, power, buffers, threats.
local s=game.surfaces[1]
local st={} for k,v in pairs(defines.entity_status) do st[v]=k end
local out={}
-- machines by name and status
local agg={}
for _,e in pairs(s.find_entities_filtered{force="player",type={"mining-drill","furnace","assembling-machine","lab","boiler","generator","offshore-pump","rocket-silo"}}) do
  local k=e.name local a=agg[k] or {n=0} agg[k]=a a.n=a.n+1
  local ss=st[e.status] or "nil" a[ss]=(a[ss] or 0)+1
end
for k,a in pairs(agg) do local t={} for ss,c in pairs(a) do if ss~="n" then t[#t+1]=ss.."="..c end end out[#out+1]=string.format("%-24s %4d  %s",k,a.n,table.concat(t," ")) end
-- reserves under drills, by resource, grouped into 64-tile cells
local res={}
for _,d in pairs(s.find_entities_filtered{force="player",type="mining-drill"}) do
  local m=d.mining_target
  local cell=math.floor(d.position.x/64)..","..math.floor(d.position.y/64)
  local r=d.prototype.mining_drill_radius or 1
  if m then local key=m.name.."@"..cell
  if not res[key] then
    local amt=0 local c=d.position
    for _,o in pairs(s.find_entities_filtered{type="resource",area={{c.x-40,c.y-40},{c.x+40,c.y+40}},name=m.name}) do amt=amt+o.amount end
    res[key]={drills=0,amt=amt,x=c.x,y=c.y}
  end
  res[key].drills=res[key].drills+1 end
end
out[#out+1]="-- mined patches (ore within 40 of first drill in each 64-cell)"
for k,v in pairs(res) do out[#out+1]=string.format("%-28s drills %3d  ore %.2fM  near (%d,%d)",k,v.drills,v.amt/1e6,v.x,v.y) end
-- power
local p=game.forces.player
for _,pole in pairs(s.find_entities_filtered{force="player",type="electric-pole",limit=1}) do
  local es=pole.electric_network_statistics
  local P=defines.flow_precision_index
  local prod,cons=0,0
  for n,_ in pairs(es.output_counts) do prod=prod+es.get_flow_count{name=n,category="output",precision_index=P.one_minute} end
  for n,_ in pairs(es.input_counts) do cons=cons+es.get_flow_count{name=n,category="input",precision_index=P.one_minute} end
  out[#out+1]=string.format("power (1-min avg, network of first pole): produced %.2f MW consumed %.2f MW",prod*60/1e6,cons*60/1e6)
end
-- buffers in containers
local buf={}
for _,c in pairs(s.find_entities_filtered{force="player",type="container"}) do
  local inv=c.get_inventory(defines.inventory.chest)
  for _,it in pairs(inv.get_contents()) do buf[it.name]=(buf[it.name] or 0)+it.count end
end
local bl={} for n,c in pairs(buf) do if c>=200 then bl[#bl+1]=n.."="..c end end table.sort(bl)
out[#out+1]="-- chest buffers >=200: "..table.concat(bl," ")
-- threats
local nests=s.count_entities_filtered{force="enemy",type="unit-spawner",position={0,0},radius=400}
local worms=s.count_entities_filtered{force="enemy",type="turret",position={0,0},radius=400}
out[#out+1]=string.format("enemy within 400: spawners %d worms %d; evolution %.3f; pollution at (0,0) %.0f",nests,worms,game.forces.enemy.get_evolution_factor(s),s.get_pollution{0,0})
rcon.print(table.concat(out,"\n"))
