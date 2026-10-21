-- Gives every electric network inside a rectangle one energy interface, the same way on any surface.
-- Input: global ARGS = {surface, force, area, remove}. With `remove` it destroys the interfaces it made earlier.
-- Prints the unit numbers it created, one per network.

local surface, force, a, remove = game.surfaces[ARGS[1]], ARGS[2], ARGS[3], ARGS[4]
storage.fid_power = storage.fid_power or {}
local made = storage.fid_power

if remove then
  for _, e in pairs(made) do if e.valid then e.destroy() end end
  storage.fid_power = {}
  rcon.print("[]")
  return
end

local poles = surface.find_entities_filtered{area = a, type = "electric-pole"}
table.sort(poles, function(p, q)
  if p.position.y ~= q.position.y then return p.position.y < q.position.y end
  return p.position.x < q.position.x
end)
local done, units = {}, {}
for _, pole in ipairs(poles) do
  local id = pole.electric_network_id
  if id and not done[id] then
    local ok, reach = pcall(pole.prototype.get_supply_area_distance, pole.quality)
    if not ok then reach = 3 end
    local spot = surface.find_non_colliding_position("electric-energy-interface", pole.position, reach, 0.5)
    local eei = spot and surface.create_entity{name = "electric-energy-interface", position = spot, force = force}
    if eei then
      eei.power_production = 1e10
      eei.electric_buffer_size = 1e11
      eei.energy = 1e11
      done[id] = true
      made[#made + 1] = eei
      units[#units + 1] = eei.unit_number
    end
  end
end
rcon.print(helpers.table_to_json(units))
