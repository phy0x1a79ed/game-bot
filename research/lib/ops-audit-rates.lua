-- ops-audit-rates: READ-ONLY. Cumulative production counts for named items (force item production statistics), products_finished of named machines, lab statuses and the current research, rail ghost positions. Run twice >=120 s apart; rate/min = delta / minutes (60 ticks per s).
local ST = {} for k,v in pairs(defines.entity_status) do ST[v]=k end
local s = game.surfaces[1]
local f = game.forces.player
rcon.print("TICK "..game.tick)
local stats = f.get_item_production_statistics(s)
local l = {}
for _, n in ipairs({"steel-plate","piercing-rounds-magazine","military-science-pack","automation-science-pack","logistic-science-pack","chemical-science-pack","electronic-circuit","advanced-circuit","engine-unit","grenade","stone-brick","iron-plate","copper-plate","firearm-magazine","rail","construction-robot","roboport"}) do
  l[#l+1] = n.."="..stats.get_input_count(n)
end
rcon.print("PROD "..table.concat(l,","))
for _, p in ipairs({{19.5,-52.5},{27.5,-52.5},{22.5,-45.5},{30.5,-45.5},{42.5,-33.5},{45.5,-29.5},{51.5,-30.5},{16.5,-37.5},{21.5,-97.5},{38.5,-97.5},{42.5,-97.5},{38.5,-92.5},{31.5,-84.5}}) do
  for _, e in pairs(s.find_entities_filtered{position=p, radius=0.4, force="player"}) do
    if e.type=="assembling-machine" or e.type=="furnace" then
      local r = e.get_recipe()
      rcon.print(string.format("AM (%.1f,%.1f) %s %s %s pf=%d", p[1],p[2],e.name,r and r.name or "-",ST[e.status] or "?",e.products_finished))
    end
  end
end
local labs, bad = 0, {}
for _, e in pairs(s.find_entities_filtered{force="player", type="lab"}) do
  labs = labs + 1
  local n = ST[e.status] or "?"
  bad[n] = (bad[n] or 0) + 1
end
l = {} for k,v in pairs(bad) do l[#l+1]=k.."="..v end table.sort(l)
local cr = f.current_research
rcon.print("LABS "..labs.." "..table.concat(l,",").." research="..(cr and cr.name or "none").." progress="..string.format("%.3f", f.research_progress))
local rg = {}
for _, e in pairs(s.find_entities_filtered{force="player", name="entity-ghost", ghost_name="straight-rail"}) do rg[#rg+1] = string.format("%d", e.position.x) end
table.sort(rg, function(a,b) return tonumber(a) < tonumber(b) end)
rcon.print("RAILGHOSTS "..#rg.." x="..table.concat(rg,","))
