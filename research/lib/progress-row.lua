-- progress-row.lua: one CSV row of the headline rates (made per min, 10-min average) for progress.csv.
local f=game.forces.player local s=game.surfaces[1] local P=defines.flow_precision_index
local st=f.get_item_production_statistics(s)
local function m(n) return st.get_flow_count{name=n,category='input',precision_index=P.ten_minutes} end
local es={} for k,v in pairs(defines.entity_status) do es[v]=k end
local labs,work=0,0 for _,l in pairs(s.find_entities_filtered{type="lab",force="player"}) do labs=labs+1 if es[l.status]=="working" then work=work+1 end end
local n=0 for _,t in pairs(f.technologies) do if t.researched then n=n+1 end end
rcon.print(string.format("%d,%.3f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.1f,%.1f,%.1f,%.1f,%d/%d,%d,%d",game.tick,game.forces.enemy.get_evolution_factor(s),m("iron-plate"),m("copper-plate"),m("steel-plate"),m("stone-brick"),m("coal"),m("electronic-circuit"),m("automation-science-pack"),m("logistic-science-pack"),m("chemical-science-pack"),m("military-science-pack"),work,labs,n,s.count_entities_filtered{name="construction-robot"}))
