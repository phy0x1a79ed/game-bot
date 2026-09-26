local f = game.forces.player
local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

p('tick='..game.tick..' evolution='..string.format('%.3f', game.forces.enemy.get_evolution_factor(surf)))
p('current_research='..tostring(f.current_research and (f.current_research.name..' '..string.format('%.1f%%', f.research_progress*100))))
local r = {}
for n,t in pairs(f.technologies) do if t.researched then r[#r+1]=n end end
table.sort(r)
p('researched: '..table.concat(r, ','))

p('=== KEY ENTITY/RECIPE ENABLED ===')
for _, n in pairs({'splitter','underground-belt','fast-transport-belt','stone-wall','gun-turret','medium-electric-pole','steel-plate','electric-mining-drill','pipe-to-ground'}) do
  local ok, en = pcall(function() return f.recipes[n] and f.recipes[n].enabled end)
  p(n..' recipe_enabled='..tostring(ok and en))
end

p('=== PRODUCTION RATES last10min (per min) ===')
local stats = f.get_item_production_statistics(surf)
for _, n in pairs({'iron-plate','copper-plate','stone','coal','iron-gear-wheel','electronic-circuit','automation-science-pack'}) do
  local per10 = stats.get_flow_count{name=n, category='input', precision_index=defines.flow_precision_index.ten_minutes, count=true}
  p(n..' last10min_total='..per10..' approx_per_min='..string.format('%.1f', per10/10))
end

p('=== POLLUTION at key sites ===')
for _, pt in pairs({{-24,-50,'iron column'},{20,60,'copper field'},{73,-47,'coal-1/ring1'},{60,-30,'stone drill'},{-50,-9,'power block'},{0,-19,'depot/mall site'}}) do
  local x,y,label = pt[1],pt[2],pt[3]
  local ok, pol = pcall(function() return surf.get_pollution({x,y}) end)
  p(label..' @ ('..x..','..y..') pollution='..tostring(ok and pol))
end

p('=== DEPOT/MALL CANDIDATE AREA (-20,-25)-(15,15) obstacles ===')
local cnt = 0
for _, e in pairs(surf.find_entities_filtered{area={{-20,-25},{15,15}}}) do
  if e.type ~= 'character' and e.type ~= 'resource' then cnt = cnt + 1 end
end
p('non-character/resource entity count in candidate mall/waist box = '..cnt)

p('=== BELT/POLE/WALL ITEM STOCK (depot chest + all iron-chests total) ===')
local totals = {}
for _, e in pairs(surf.find_entities_filtered{name={'iron-chest','wooden-chest'}}) do
  local inv = e.get_inventory(defines.inventory.chest)
  if inv then
    for _, it in pairs(inv.get_contents()) do
      totals[it.name] = (totals[it.name] or 0) + it.count
    end
  end
end
local tl = {}
for k,v in pairs(totals) do if v >= 5 then tl[#tl+1] = k..'='..v end end
table.sort(tl)
p(table.concat(tl, ' '))

rcon.print(table.concat(out, '\n'))
