-- census.lua: every item that exists in the world, by name, plus the player force's lifetime item statistics.
-- Placed entities and placed tiles count as the item that places them. Quality is folded into the name.
-- Statistics skip hidden items: "science" counts research progress and never exists in the world.
-- Prints JSON: {tick, world, made, used (item = n), lost (entity = n), placers (entity = item), spent (items used up in use)}
local world, made, used, lost = {}, {}, {}, {}
local function add(t, name, n) if n ~= 0 then t[name] = (t[name] or 0) + n end end
local function add_contents(list) for _, it in pairs(list) do add(world, it.name, it.count) end end

local place_item = {}
local function item_of(proto)
  local v = place_item[proto.name]
  if v == nil then
    local items = proto.items_to_place_this
    v = (items and items[1]) and items[1].name or false
    place_item[proto.name] = v
  end
  return v
end

local belt_types = {["transport-belt"] = true, ["underground-belt"] = true, splitter = true, loader = true,
  ["loader-1x1"] = true, ["linked-belt"] = true, ["lane-splitter"] = true}
local skip = {["entity-ghost"] = true, ["tile-ghost"] = true, ["item-request-proxy"] = true,
  ["resource"] = true, ["corpse"] = true, ["character-corpse"] = true}

for _, s in pairs(game.surfaces) do
  for _, e in pairs(s.find_entities_filtered{}) do
    local t = e.type
    if t == "item-entity" then
      if e.stack.valid_for_read then add(world, e.stack.name, e.stack.count) end
    elseif not skip[t] and e.force.name ~= "enemy" and e.force.name ~= "neutral" then
      local placer = item_of(e.prototype)
      if placer then add(world, placer, 1) end
      for i = 1, (e.get_max_inventory_index() or 0) do
        local inv = e.get_inventory(i)
        if inv then add_contents(inv.get_contents()) end
      end
      if belt_types[t] then
        for i = 1, e.get_max_transport_line_index() do add_contents(e.get_transport_line(i).get_contents()) end
      elseif t == "inserter" then
        if e.held_stack.valid_for_read then add(world, e.held_stack.name, e.held_stack.count) end
      end
    end
  end
  for _, tile in pairs(prototypes.get_tile_filtered{{filter = "item-to-place"}}) do
    local n = s.count_tiles_filtered{name = tile.name}
    if n > 0 then add(world, tile.items_to_place_this[1].name, n) end
  end
end
for _, p in pairs(game.players) do
  if p.cursor_stack and p.cursor_stack.valid_for_read then add(world, p.cursor_stack.name, p.cursor_stack.count) end
end

local force = game.forces.player
local function real(name) local p = prototypes.item[name] return p and not p.hidden end
for _, s in pairs(game.surfaces) do
  local st = force.get_item_production_statistics(s)
  for name, n in pairs(st.input_counts) do if real(name) then add(made, name, n) end end
  for name, n in pairs(st.output_counts) do if real(name) then add(used, name, n) end end
  local kills = game.forces.enemy.get_kill_count_statistics(s)
  for name, n in pairs(kills.input_counts) do add(lost, name, n) end
end
local placers, spent = {}, {}
for name in pairs(lost) do placers[name] = prototypes.entity[name] and item_of(prototypes.entity[name]) or nil end
-- ammo fired, repair packs worn and capsules thrown leave the world without passing through the statistics
local spent_types = {ammo = true, ["repair-tool"] = true, capsule = true}
for name in pairs(world) do if spent_types[prototypes.item[name].type] then spent[name] = true end end
rcon.print(helpers.table_to_json{tick = game.tick, world = world, made = made, used = used, lost = lost,
  placers = placers, spent = spent})
