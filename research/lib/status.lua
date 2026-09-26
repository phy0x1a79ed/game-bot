local f = game.forces.player
local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
p('tick=' .. game.tick .. ' (' .. string.format('%.2f', game.tick/216000) .. 'h)')
local r = {}
for n, t in pairs(f.technologies) do if t.researched and t.enabled then r[#r+1] = n end end
table.sort(r)
p('researched=' .. table.concat(r, ','))
p('current=' .. tostring(f.current_research and (f.current_research.name .. ' ' .. string.format('%.0f%%', f.research_progress*100))))
local counts, idle = {}, {}
for _, e in pairs(surf.find_entities_filtered{force='player'}) do
  if e.type ~= 'character' then
    counts[e.name] = (counts[e.name] or 0) + 1
    local ok, st = pcall(function() return e.status end)
    local starved = ok and st and (st == defines.entity_status.no_ingredients or st == defines.entity_status.missing_science_packs)
    if starved and (e.type == 'assembling-machine' or e.type == 'lab') then idle[#idle+1] = 'STARVED:' .. e.name .. '@' .. math.floor(e.position.x) .. ',' .. math.floor(e.position.y) end
    if ok and st and (st == defines.entity_status.no_fuel or st == defines.entity_status.no_power or st == defines.entity_status.low_power) then
      idle[#idle+1] = e.name .. '@' .. math.floor(e.position.x) .. ',' .. math.floor(e.position.y)
    end
  end
end
local c = {}
for k, v in pairs(counts) do c[#c+1] = k .. '=' .. v end
table.sort(c)
p('entities: ' .. table.concat(c, ' '))
p('no_fuel/power/starved(' .. #idle .. '): ' .. table.concat(idle, ' '))
for _, pl in pairs(game.connected_players) do
  local inv = pl.get_main_inventory()
  local items = {}
  if inv then
    for _, it in pairs(inv.get_contents()) do
      if it.count >= 5 then items[#items+1] = it.name .. ':' .. it.count end
    end
  end
  p(pl.name .. ' @' .. (pl.character and (math.floor(pl.position.x) .. ',' .. math.floor(pl.position.y)) or 'nochar') .. ' craftq=' .. (pl.crafting_queue_size or 0) .. ' ' .. table.concat(items, ' '))
end
local stats = f.get_item_production_statistics(surf)
for _, n in pairs({'iron-plate', 'copper-plate', 'stone', 'coal', 'automation-science-pack'}) do
  p(n .. ' produced total=' .. stats.get_input_count(n) .. ' last10min=' .. math.floor(stats.get_flow_count{name=n, category='input', precision_index=defines.flow_precision_index.ten_minutes, count=true}))
end

local groups = {}
for _, e in pairs(surf.find_entities_filtered{force='enemy', type='unit', position={0,-20}, radius=150}) do
  local k = math.floor(e.position.x/20)*20 .. ',' .. math.floor(e.position.y/20)*20
  groups[k] = (groups[k] or 0) + 1
end
local g = {}
for k, v in pairs(groups) do g[#g+1] = k .. 'x' .. v end
p('enemies<150: ' .. (#g > 0 and table.concat(g, ' ') or 'none'))
local t = {}
for _, e in pairs(surf.find_entities_filtered{force='player', name='gun-turret'}) do
  t[#t+1] = math.floor(e.position.x) .. ',' .. math.floor(e.position.y) .. ':' .. e.get_inventory(defines.inventory.turret_ammo).get_item_count()
end
p('turrets(ammo): ' .. (#t > 0 and table.concat(t, ' ') or 'none'))
p('evolution=' .. string.format('%.3f', game.forces.enemy.get_evolution_factor(surf)))
rcon.print(table.concat(out, '\n'))
