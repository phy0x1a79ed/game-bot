local surf = game.surfaces["nauvis"]
local out = {}
local function fuel(e)
  local ok, inv = pcall(function() return e.get_fuel_inventory() end)
  if not ok or not inv then return nil end
  return inv.get_item_count()
end
local rows = {}
for _, e in pairs(surf.find_entities_filtered{force="player"}) do
  local n = e.name
  if n=="burner-mining-drill" or n=="stone-furnace" or n=="burner-inserter" or n=="boiler" or n=="electric-mining-drill" then
    rows[#rows+1] = string.format("%s (%.1f,%.1f) f=%s st=%s dir=%s", n, e.position.x, e.position.y, tostring(fuel(e)), tostring(e.status), tostring(e.direction))
  elseif n=="iron-chest" then
    local c = {}
    for _, it in pairs(e.get_inventory(defines.inventory.chest).get_contents()) do c[#c+1]=it.name..":"..it.count end
    rows[#rows+1] = string.format("chest (%.1f,%.1f) %s", e.position.x, e.position.y, table.concat(c," "))
  end
  if e.health and e.max_health and e.health < e.max_health and e.type ~= "character" then
    rows[#rows+1] = string.format("DAMAGED %s (%.1f,%.1f) %d/%d", n, e.position.x, e.position.y, e.health, e.max_health)
  end
end
table.sort(rows)
rcon.print(table.concat(rows, "\n"))
