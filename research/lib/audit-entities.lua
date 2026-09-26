-- Read-only full audit of every player-force entity: status, fuel, I/O contents,
-- and inserter pickup/drop target validation (an inserter whose pickup or drop
-- tile holds no entity is a bug -- coal-on-the-ground pattern from the diary).
local surf = game.surfaces["nauvis"]
local out = {}
local function p(s) out[#out+1] = s end

local function inv_str(e, idx)
  local ok, inv = pcall(function() return e.get_inventory(idx) end)
  if not ok or not inv then return "n/a" end
  local ok2, contents = pcall(function() return inv.get_contents() end)
  if not ok2 then return "n/a" end
  local parts = {}
  for _, it in pairs(contents) do parts[#parts+1] = it.name .. ":" .. it.count end
  return #parts > 0 and table.concat(parts, ",") or "empty"
end

local function fuel_str(e)
  local ok, inv = pcall(function() return e.get_fuel_inventory() end)
  if not ok or not inv then return "n/a" end
  local ok2, c = pcall(function() return inv.get_item_count() end)
  return ok2 and tostring(c) or "n/a"
end

-- Burner drills, furnaces: status + fuel + output/result
p("=== BURNER-MINING-DRILL ===")
for _, e in pairs(surf.find_entities_filtered{force="player", name="burner-mining-drill"}) do
  p(string.format("(%.1f,%.1f) dir=%d status=%d fuel=%s", e.position.x, e.position.y, e.direction, e.status, fuel_str(e)))
end

p("=== STONE-FURNACE ===")
for _, e in pairs(surf.find_entities_filtered{force="player", name="stone-furnace"}) do
  p(string.format("(%.1f,%.1f) status=%d fuel=%s result=%s", e.position.x, e.position.y, e.status, fuel_str(e), inv_str(e, defines.inventory.furnace_result)))
end

p("=== ELECTRIC-MINING-DRILL ===")
for _, e in pairs(surf.find_entities_filtered{force="player", name="electric-mining-drill"}) do
  p(string.format("(%.1f,%.1f) dir=%d status=%d", e.position.x, e.position.y, e.direction, e.status))
end

p("=== LAB ===")
for _, e in pairs(surf.find_entities_filtered{force="player", name="lab"}) do
  p(string.format("(%.1f,%.1f) status=%d input=%s", e.position.x, e.position.y, e.status, inv_str(e, defines.inventory.lab_input)))
end

p("=== ASSEMBLING-MACHINE ===")
local asm_found = 0
for _, e in pairs(surf.find_entities_filtered{force="player", type="assembling-machine"}) do
  asm_found = asm_found + 1
  local recipe = e.get_recipe()
  p(string.format("(%.1f,%.1f) status=%d recipe=%s", e.position.x, e.position.y, e.status, recipe and recipe.name or "NONE"))
end
if asm_found == 0 then p("none built") end

-- Chests: contents summary (only non-trivial)
p("=== IRON-CHEST (contents) ===")
for _, e in pairs(surf.find_entities_filtered{force="player", name="iron-chest"}) do
  p(string.format("(%.1f,%.1f) %s", e.position.x, e.position.y, inv_str(e, defines.inventory.chest)))
end

-- Inserters: pickup/drop validation
p("=== BURNER-INSERTER pickup/drop check ===")
for _, e in pairs(surf.find_entities_filtered{force="player", name="burner-inserter"}) do
  local pp, dp = e.pickup_position, e.drop_position
  local pe = surf.find_entities_filtered{position=pp, radius=0.15}
  local de = surf.find_entities_filtered{position=dp, radius=0.15}
  local pn = #pe > 0 and pe[1].name or "NOTHING"
  local dn = #de > 0 and de[1].name or "NOTHING"
  local bug = (pn == "NOTHING" or dn == "NOTHING") and " <<BUG>>" or ""
  p(string.format("(%.1f,%.1f) dir=%d status=%d fuel=%s pickup(%.2f,%.2f)=%s drop(%.2f,%.2f)=%s%s",
    e.position.x, e.position.y, e.direction, e.status, fuel_str(e), pp.x, pp.y, pn, dp.x, dp.y, dn, bug))
end

p("=== INSERTER (electric) pickup/drop check ===")
local ins_found = 0
for _, e in pairs(surf.find_entities_filtered{force="player", name="inserter"}) do
  ins_found = ins_found + 1
  local pp, dp = e.pickup_position, e.drop_position
  local pe = surf.find_entities_filtered{position=pp, radius=0.15}
  local de = surf.find_entities_filtered{position=dp, radius=0.15}
  local pn = #pe > 0 and pe[1].name or "NOTHING"
  local dn = #de > 0 and de[1].name or "NOTHING"
  local bug = (pn == "NOTHING" or dn == "NOTHING") and " <<BUG>>" or ""
  p(string.format("(%.1f,%.1f) dir=%d status=%d pickup=%s drop=%s%s", e.position.x, e.position.y, e.direction, e.status, pn, dn, bug))
end
if ins_found == 0 then p("none built") end

p("=== GUN-TURRET ===")
for _, e in pairs(surf.find_entities_filtered{force="player", name="gun-turret"}) do
  local ammo = e.get_inventory(defines.inventory.turret_ammo)
  p(string.format("(%.1f,%.1f) status=%d ammo=%d", e.position.x, e.position.y, e.status, ammo and ammo.get_item_count() or -1))
end

p("=== POWER ===")
for _, e in pairs(surf.find_entities_filtered{force="player", name="boiler"}) do
  p(string.format("boiler (%.1f,%.1f) status=%d fuel=%s", e.position.x, e.position.y, e.status, fuel_str(e)))
end
for _, e in pairs(surf.find_entities_filtered{force="player", name="steam-engine"}) do
  p(string.format("engine (%.1f,%.1f) status=%d gen_last_tick=%.0f", e.position.x, e.position.y, e.status, e.energy_generated_last_tick))
end
for _, e in pairs(surf.find_entities_filtered{force="player", name="small-electric-pole"}) do
  p(string.format("pole (%.1f,%.1f) network=%s", e.position.x, e.position.y, tostring(e.electric_network_id)))
end

rcon.print(table.concat(out, "\n"))
