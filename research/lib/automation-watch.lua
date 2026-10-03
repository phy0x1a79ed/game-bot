-- Read-only council watch for the automation & logistics seat.
-- HANDFUEL: burner machines fed by hand. An inserter tops fuel up to about 5,
-- so a machine holding more than 8 fuel, or with no inserter dropping into it,
-- is being fuelled by hand. Idle orphans (no_ingredients / no_minable_resources) are listed apart.
-- STOCK: building items across every chest. MALL: mall cell statuses.
local s = game.surfaces[1]
local st = {} for k, v in pairs(defines.entity_status) do st[v] = k end
local fed = {}
for _, i in pairs(s.find_entities_filtered{force = "player", type = "inserter"}) do
  local d = i.drop_target
  if d and d.valid then fed[d.unit_number] = true end
end
local live, idle = {}, {}
for _, e in pairs(s.find_entities_filtered{force = "player", type = {"furnace", "boiler", "mining-drill", "inserter"}}) do
  if e.burner then
    local fuel = e.burner.inventory.get_item_count()
    if fuel > 8 or not fed[e.unit_number] then
      local tag = string.format("%s(%.0f,%.0f)", e.name, e.position.x, e.position.y)
      local status = st[e.status] or "?"
      if status == "no_ingredients" or status == "no_minable_resources" then idle[#idle + 1] = tag
      else live[#live + 1] = tag end
    end
  end
end
rcon.print("HANDFUEL live=" .. #live .. " idle_orphans=" .. #idle)
rcon.print("  " .. table.concat(live, " "))
local want = {"stone-wall", "medium-electric-pole", "big-electric-pole", "steel-furnace", "assembling-machine-2",
  "fast-inserter", "splitter", "pipe", "gun-turret", "transport-belt", "underground-belt", "inserter",
  "electric-mining-drill", "assembling-machine-1", "construction-robot", "roboport"}
local tot = {}
for _, c in pairs(s.find_entities_filtered{force = "player", type = {"container", "logistic-container"}}) do
  local inv = c.get_inventory(defines.inventory.chest)
  for _, w in pairs(want) do tot[w] = (tot[w] or 0) + inv.get_item_count(w) end
end
local o = {} for _, w in pairs(want) do o[#o + 1] = w .. "=" .. tot[w] end
rcon.print("STOCK " .. table.concat(o, " "))
local short, full, work = 0, 0, 0
for _, e in pairs(s.find_entities_filtered{force = "player", type = "assembling-machine", area = {{-14, 3}, {26, 14}}}) do
  if e.status == defines.entity_status.item_ingredient_shortage then short = short + 1
  elseif e.status == defines.entity_status.full_output then full = full + 1
  else work = work + 1 end
end
local ghosts = #s.find_entities_filtered{force = "player", type = "entity-ghost"}
local bots = 0
for _, nets in pairs(game.forces.player.logistic_networks) do
  for _, n in pairs(nets) do bots = bots + n.all_construction_robots end
end
rcon.print(string.format("MALL(main) short=%d full=%d other=%d | ghosts=%d construction_bots=%d", short, full, work, ghosts, bots))
