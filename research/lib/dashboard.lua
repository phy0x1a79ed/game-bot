-- dashboard.lua: the production-growth dashboard, per-minute over 10 min and 1 h.
local f=game.forces.player
local surf=game.surfaces[1]
local P=defines.flow_precision_index
local out={string.format('tick=%d evolution=%.3f research=%s',game.tick,game.forces.enemy.get_evolution_factor(surf),f.current_research and f.current_research.name or 'none')}
local function rows(st,items)
  for _,n in ipairs(items) do
    local a=st.get_flow_count{name=n,category='input',precision_index=P.ten_minutes}
    local b=st.get_flow_count{name=n,category='output',precision_index=P.ten_minutes}
    local c=st.get_flow_count{name=n,category='input',precision_index=P.one_hour}
    out[#out+1]=string.format('%-26s made %7.1f used %7.1f | made/1h %7.1f',n,a,b,c)
  end
end
out[#out+1]='-- items (per min)'
rows(f.get_item_production_statistics(surf),{'iron-plate','copper-plate','steel-plate','stone-brick','coal','stone','electronic-circuit','advanced-circuit','processing-unit','plastic-bar','sulfur','iron-gear-wheel','engine-unit','electric-engine-unit','battery','low-density-structure','rocket-fuel','concrete','firearm-magazine','piercing-rounds-magazine','automation-science-pack','logistic-science-pack','military-science-pack','chemical-science-pack','production-science-pack','utility-science-pack'})
out[#out+1]='-- fluids (per min)'
rows(f.get_fluid_production_statistics(surf),{'crude-oil','petroleum-gas','heavy-oil','light-oil','sulfuric-acid','lubricant'})
local q={} for _,t in pairs(f.research_queue or {}) do q[#q+1]=t.name end
out[#out+1]='queue: '..table.concat(q,', ')
rcon.print(table.concat(out,'\n'))
