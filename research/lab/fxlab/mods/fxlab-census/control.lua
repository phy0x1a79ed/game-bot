-- Items vanish with an entity that enemies destroy. Record them so the balance gate can excuse them.
local belts = {["transport-belt"] = true, ["underground-belt"] = true, splitter = true, loader = true,
  ["loader-1x1"] = true, ["linked-belt"] = true, ["lane-splitter"] = true}

local function add(name, n)
  storage.died[name] = (storage.died[name] or 0) + n
end

local function add_contents(list) for _, it in pairs(list) do add(it.name, it.count) end end

script.on_init(function() storage.died = {} end)
script.on_configuration_changed(function() storage.died = storage.died or {} end)

script.on_event(defines.events.on_entity_died, function(ev)
  local e = ev.entity
  if not (e.valid and e.force.name == "player" and ev.force and ev.force.name == "enemy") then return end
  for i = 1, (e.get_max_inventory_index() or 0) do
    local inv = e.get_inventory(i)
    if inv then add_contents(inv.get_contents()) end
  end
  if belts[e.type] then
    for i = 1, e.get_max_transport_line_index() do add_contents(e.get_transport_line(i).get_contents()) end
  elseif e.type == "inserter" and e.held_stack.valid_for_read then
    add(e.held_stack.name, e.held_stack.count)
  end
end)

remote.add_interface("fxlab", {died = function() return storage.died end})
