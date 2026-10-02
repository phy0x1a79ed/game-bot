-- flows.lua: 10-min and 1-h production/consumption of key items per minute.
local f=game.forces.player
local surf=game.surfaces[1]
local st=f.get_item_production_statistics(surf)
local out={'tick='..game.tick}
local items={'iron-ore','iron-plate','copper-ore','copper-plate','stone','coal','stone-brick','steel-plate','iron-gear-wheel','copper-cable','electronic-circuit','transport-belt','inserter','firearm-magazine','automation-science-pack','logistic-science-pack','assembling-machine-1','electric-mining-drill','burner-mining-drill','stone-furnace','iron-chest','gun-turret','small-electric-pole','wood','repair-pack','stone-wall','pipe','splitter','underground-belt','lab','long-handed-inserter','burner-inserter'}
out[#out+1]=string.format('%-24s %9s %9s | %9s %9s | totals in/out','item','in/min10','out/min10','in/min1h','out/min1h')
local P=defines.flow_precision_index
for _,n in ipairs(items) do
  local a=st.get_flow_count{name=n,category='input',precision_index=P.ten_minutes}
  local b=st.get_flow_count{name=n,category='output',precision_index=P.ten_minutes}
  local c=st.get_flow_count{name=n,category='input',precision_index=P.one_hour}
  local d=st.get_flow_count{name=n,category='output',precision_index=P.one_hour}
  out[#out+1]=string.format('%-24s %9.1f %9.1f | %9.1f %9.1f | %d / %d',n,a,b,c,d,st.get_input_count(n),st.get_output_count(n))
end
rcon.print(table.concat(out,'\n'))
