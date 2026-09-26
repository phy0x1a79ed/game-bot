local surf = game.surfaces["nauvis"]
local out = {}
local function fuel(e)
  local ok, inv = pcall(function() return e.get_fuel_inventory() end)
  if not ok or not inv then return -1 end
  return inv.get_item_count()
end
out[#out+1] = "tick=" .. game.tick
for _, e in pairs(surf.find_entities_filtered{force="player", name="burner-mining-drill"}) do
  out[#out+1] = string.format("drill (%.1f,%.1f) fuel=%d status=%d", e.position.x, e.position.y, fuel(e), e.status)
end
for _, e in pairs(surf.find_entities_filtered{force="player", name="stone-furnace"}) do
  out[#out+1] = string.format("furnace (%.1f,%.1f) fuel=%d status=%d", e.position.x, e.position.y, fuel(e), e.status)
end
rcon.print(table.concat(out, "\n"))
