-- military-watch.lua: perimeter health, losses, wave pressure by front, evolution split, nest groups. Read-only.
local s=game.surfaces[1] local pf=game.forces.player local en=game.forces.enemy
local out={'tick='..game.tick}
out[#out+1]=string.format('evo=%.4f time=%.4f pollution=%.4f kills=%.4f',en.get_evolution_factor(s),en.get_evolution_factor_by_time(s),en.get_evolution_factor_by_pollution(s),en.get_evolution_factor_by_killing_spawners(s))
local ts=s.find_entities_filtered{name='gun-turret',force='player'}
local fed,low,amm,cells=0,0,{},{}
for _,t in pairs(ts) do
  local inv=t.get_inventory(defines.inventory.turret_ammo) local c=0
  for i=1,#inv do local st=inv[i] if st.valid_for_read then c=c+st.count amm[st.name]=(amm[st.name] or 0)+st.count end end
  if c<10 then low=low+1 end
  for _,i in pairs(s.find_entities_filtered{type='inserter',position=t.position,radius=2.5}) do if i.drop_target==t then fed=fed+1 break end end
  local k=string.format('(%d,%d)',math.floor(t.position.x/24)*24,math.floor(t.position.y/24)*24)
  local o=cells[k] or {n=0,k=0} o.n=o.n+1 o.k=o.k+(t.kills or 0) cells[k]=o
end
out[#out+1]=string.format('turrets=%d beltfed=%d under10=%d walls=%d',#ts,fed,low,s.count_entities_filtered{name='stone-wall',force='player'})
for k,v in pairs(amm) do out[#out+1]='  ammo '..k..'='..v end
local ek=en.get_kill_count_statistics(s) local pk=pf.get_kill_count_statistics(s)
out[#out+1]=string.format('lost: gun-turret=%d stone-wall=%d character=%d | killed: spawners=%d worms=%d mediums=%d',ek.get_input_count('gun-turret'),ek.get_input_count('stone-wall'),ek.get_input_count('character'),pk.get_input_count('biter-spawner')+pk.get_input_count('spitter-spawner'),pk.get_input_count('small-worm-turret')+pk.get_input_count('medium-worm-turret'),pk.get_input_count('medium-biter'))
local arr={} for k,o in pairs(cells) do arr[#arr+1]={k,o} end table.sort(arr,function(a,b) return a[2].k>b[2].k end)
for i=1,math.min(6,#arr) do out[#out+1]=string.format('  front %s turrets=%d kills=%d',arr[i][1],arr[i][2].n,arr[i][2].k) end
out[#out+1]=string.format('enemy units: small-biter=%d medium-biter=%d small-spitter=%d medium-spitter=%d big-biter=%d',s.count_entities_filtered{name='small-biter'},s.count_entities_filtered{name='medium-biter'},s.count_entities_filtered{name='small-spitter'},s.count_entities_filtered{name='medium-spitter'},s.count_entities_filtered{name='big-biter'})
out[#out+1]='spawners within 450='..s.count_entities_filtered{type='unit-spawner',force='enemy',position={0,0},radius=450}
rcon.print(table.concat(out,'\n'))
