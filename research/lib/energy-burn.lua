-- energy-burn.lua: fuel burn by consumer class (coal-equivalent/min), steam output, electric networks, fuel kinds in use.
local s=game.surfaces[1]
local ST={} for k,v in pairs(defines.entity_status) do ST[v]=k end
local COAL=4e6
local out={'tick='..game.tick}
local cls={}
local fuels={}
local function add(c,k,v) cls[c]=cls[c] or {} cls[c][k]=(cls[c][k] or 0)+v end
for _,e in pairs(s.find_entities_filtered{force='player'}) do
  local b=e.burner
  if b and e.type~='character' then
    local c=e.type=='boiler' and 'boiler' or (e.type=='furnace' and e.name) or e.name
    add(c,'n',1)
    local st=ST[e.status] or '?'
    if st=='working' then add(c,'working',1) end
    local inv=b.inventory
    for i=1,#inv do local it=inv[i] if it.valid_for_read then fuels[c..':'..it.name]=(fuels[c..':'..it.name] or 0)+it.count end end
    if b.currently_burning then local nm=b.currently_burning.name.name or tostring(b.currently_burning.name) fuels[c..':burning:'..nm]=(fuels[c..':burning:'..nm] or 0)+1 end
    if st=='working' and e.type~='boiler' then add(c,'W',e.prototype.get_max_energy_usage()*60) end
  end
end
-- boilers: actual load = steam engine output (boiler effectivity 1)
local gen=0 local eng=0 local cap=0
for _,e in pairs(s.find_entities_filtered{name='steam-engine'}) do gen=gen+e.energy_generated_last_tick*60 eng=eng+1 cap=cap+e.prototype.get_max_energy_production()*60 end
add('boiler','W',gen)
for c,t in pairs(cls) do
  out[#out+1]=string.format('%-22s n=%3d working=%3d  burn %.2f MW = %.1f coal/min',c,t.n or 0,t.working or 0,(t.W or 0)/1e6,(t.W or 0)/COAL*60)
end
out[#out+1]=string.format('steam engines %d: generating %.2f MW of %.2f MW',eng,gen/1e6,cap/1e6)
local fl={} for k,v in pairs(fuels) do fl[#fl+1]=k..'='..v end table.sort(fl)
out[#out+1]='fuel held/burning: '..table.concat(fl,' ')
-- electric networks
local nets={}
for _,p in pairs(s.find_entities_filtered{type='electric-pole',force='player'}) do
  local id=p.electric_network_id if id and not nets[id] then nets[id]={p=p,n=0} end if id then nets[id].n=nets[id].n+1 end
end
for id,t in pairs(nets) do
  local ns=t.p.electric_network_statistics
  local prod,cons=0,0
  for name,_ in pairs(ns.input_counts) do prod=prod+ns.get_flow_count{name=name,category='input',precision_index=defines.flow_precision_index.one_minute,count=false} end
  for name,_ in pairs(ns.output_counts) do cons=cons+ns.get_flow_count{name=name,category='output',precision_index=defines.flow_precision_index.one_minute,count=false} end
  if t.n>2 then out[#out+1]=string.format('net %d poles=%d produced %.2f MW consumed %.2f MW (sample pole %.0f,%.0f)',id,t.n,prod*60/1e6,cons*60/1e6,t.p.position.x,t.p.position.y) end
end
local ps=game.forces.player.get_item_production_statistics(s)
local fs=game.forces.player.get_fluid_production_statistics(s)
local function r(st,n,cat) return st.get_flow_count{name=n,category=cat,precision_index=defines.flow_precision_index.ten_minutes} end
out[#out+1]=string.format('per min (10 min): coal made %.0f used %.0f | solid-fuel made %.0f used %.0f | crude made %.0f | petroleum-gas made %.0f used %.0f | light-oil made %.0f used %.0f',r(ps,'coal','input'),r(ps,'coal','output'),r(ps,'solid-fuel','input'),r(ps,'solid-fuel','output'),r(fs,'crude-oil','input'),r(fs,'petroleum-gas','input'),r(fs,'petroleum-gas','output'),r(fs,'light-oil','input'),r(fs,'light-oil','output'))
rcon.print(table.concat(out,'\n'))
