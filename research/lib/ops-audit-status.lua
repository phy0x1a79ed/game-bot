-- ops-audit-status: READ-ONLY. One line per player entity in a stuck status (no_power, low_power, no_fuel, no_ingredients, missing_science_packs, full_output, waiting_for_space_in_destination, no_recipe, no_minable_resources, *_shortage). Run twice ~10 min apart and intersect.
local ST = {} for k,v in pairs(defines.entity_status) do ST[v]=k end
local BAD = {no_power=1,low_power=1,no_fuel=1,no_ingredients=1,missing_science_packs=1,full_output=1,waiting_for_space_in_destination=1,no_recipe=1,no_minable_resources=1,item_ingredient_shortage=1,fluid_ingredient_shortage=1}
local s = game.surfaces[1]
local types = {"assembling-machine","furnace","mining-drill","lab","boiler","inserter","pump","offshore-pump","radar","roboport","ammo-turret","electric-turret","fluid-turret","generator","pumpjack","rocket-silo"}
local out = {}
for _, e in pairs(s.find_entities_filtered{force="player", type=types}) do
  local st = e.status
  local n = st and ST[st]
  if n and BAD[n] then
    local r = ""
    if e.type == "assembling-machine" or e.type == "furnace" then
      local ok, rec = pcall(function() return e.get_recipe() or e.previous_recipe end)
      if ok and rec then r = rec.name or rec end
    end
    out[#out+1] = string.format("%s|%s|%.1f|%.1f|%s|%s", e.type, e.name, e.position.x, e.position.y, n, r)
  end
end
rcon.print("TICK " .. game.tick .. " N " .. #out)
rcon.print(table.concat(out, "\n"))
