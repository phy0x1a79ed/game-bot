-- bench-build.lua: build a blueprint on an empty surface "bench" and wire every port it exposes.
-- Expects a prelude that sets BENCH = {bp = "<blueprint string>", fuel = "coal", ports = {...} or nil, swap = {["x,y"] = true}}.
-- swap names the input ports whose two lanes are exchanged.
-- Ports come from BENCH.ports when the caller declares them (capture-ports.lua records them from a live base,
-- positions relative to the smallest entity position). Otherwise they are guessed from the design:
--   a belt with no upstream belt is an input; it gets a tee fed from both sides by loaders on infinity chests,
--     one item per lane, chosen from what the consumers along that belt need;
--   a belt with no downstream belt, that nothing picks from, is an output; it gets a loader into a voiding chest;
--   an inserter whose pickup or drop lands on nothing gets an infinity chest there (source or void);
--   a burner gets fuel.
-- Prints JSON: {entities, ports = [...], unhandled = [...]}. Editor-style: run it only in a lab.
local B = BENCH
-- delete_surface lands at the end of the tick, so a rebuild in the same tick reuses the surface instead
local s = game.surfaces.bench
if not s then
  s = game.create_surface("bench", {width = 256, height = 256, peaceful_mode = true, no_enemies_mode = true})
  s.request_to_generate_chunks({0, 0}, 4)
  s.force_generate_chunk_requests()
  local tiles = {}
  for x = -110, 109 do for y = -110, 109 do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end end
  s.set_tiles(tiles)
end
for _, e in pairs(s.find_entities_filtered{}) do e.destroy() end
s.always_day = true
local force = game.forces.player
force.enable_all_recipes()

local inv = game.create_inventory(1)
assert(inv[1].import_stack(B.bp) == 0, "blueprint import failed")
local ghosts = inv[1].build_blueprint{surface = s, force = force, position = {0, 0}, build_mode = defines.build_mode.forced}
inv.destroy()
-- the anchor capture-ports uses: the smallest belt position
local gx, gy = math.huge, math.huge
for _, g in pairs(ghosts) do
  if g.valid and g.ghost_type == "transport-belt" then gx = math.min(gx, g.position.x) gy = math.min(gy, g.position.y) end
end
local built = {}
for _, g in pairs(ghosts) do if g.valid then local _, e = g.revive() if e then built[#built + 1] = e end end end
local design = {}
for _, e in pairs(built) do design[e.unit_number] = true end

local D = defines.direction
local V = {[D.north] = {0, -1}, [D.east] = {1, 0}, [D.south] = {0, 1}, [D.west] = {-1, 0}}
local LEFT = {[D.north] = D.west, [D.east] = D.north, [D.south] = D.east, [D.west] = D.south}
local OPP = {[D.north] = D.south, [D.east] = D.west, [D.south] = D.north, [D.west] = D.east}
local ports, unhandled = {}, {}
local function at(p, k, d) local v = V[d] return {x = p.x + k * v[1], y = p.y + k * v[2]} end
local function put(t)
  t.force = force
  if not s.can_place_entity{name = t.name, position = t.position, direction = t.direction, force = force} then return nil end
  return s.create_entity(t)
end
local function source(p, items)
  local c = put{name = "infinity-chest", position = p}
  if not c then return nil end
  local f = {}
  for i, it in ipairs(items) do f[i] = {name = it, count = 100, mode = "exactly", index = i} end
  c.infinity_container_filters = f
  return c
end
local function void(p)
  local c = put{name = "infinity-chest", position = p}
  if c then c.remove_unfiltered_items = true end
  return c
end

-- pickup_target and drop_target fill in only on a later tick, so find what sits at a point instead
local function thing_at(p, self)
  for _, e in pairs(s.find_entities_filtered{position = p}) do
    if e ~= self and e.type ~= "item-entity" then return e end
  end
end

-- what a machine wants as input items
local function wants(e)
  local out = {}
  if e.type == "assembling-machine" then
    local r = e.get_recipe()
    if r then for _, i in pairs(r.ingredients) do if i.type == "item" then out[#out + 1] = i.name end end end
  elseif e.type == "furnace" then
    local r = e.previous_recipe and prototypes.recipe[e.previous_recipe.name]
    if r then for _, i in pairs(r.ingredients) do if i.type == "item" then out[#out + 1] = i.name end end
    else out[#out + 1] = "iron-ore" end
  elseif e.type == "lab" then
    for _, i in pairs(e.prototype.lab_inputs) do out[#out + 1] = i end
  elseif e.type == "ammo-turret" then out[#out + 1] = "firearm-magazine"
  end
  return out
end

-- what a machine puts out
local function makes(e)
  local out = {}
  if e.type == "assembling-machine" or e.type == "furnace" then
    local r = e.get_recipe()
    if r then for _, p in pairs(r.products) do if p.type == "item" then out[#out + 1] = p.name end end end
  end
  return out
end

-- items the design drops onto this belt or any belt feeding it
local function supplied_upstream(start)
  local supplied, seen, queue = {}, {}, {start}
  while #queue > 0 do
    local b = table.remove(queue, 1)
    if b.valid and not seen[b.unit_number] then
      seen[b.unit_number] = true
      for _, ins in pairs(s.find_entities_filtered{type = "inserter", area = {{b.position.x - 3, b.position.y - 3}, {b.position.x + 3, b.position.y + 3}}}) do
        local pick = thing_at(ins.pickup_position, ins)
        if pick and thing_at(ins.drop_position, ins) == b then for _, it in pairs(makes(pick)) do supplied[it] = true end end
      end
      for _, n in pairs(b.belt_neighbours.inputs) do queue[#queue + 1] = n end
    end
  end
  return supplied
end

-- follow a belt downstream: the items inserters take off it, minus the items the design itself puts on it
local function demand_along(start)
  local need, seen, order, supplied = {}, {}, {}, {}
  local queue = {start}
  while #queue > 0 do
    local b = table.remove(queue, 1)
    if b.valid and not seen[b.unit_number] then
      seen[b.unit_number] = true
      for _, ins in pairs(s.find_entities_filtered{type = "inserter", area = {{b.position.x - 3, b.position.y - 3}, {b.position.x + 3, b.position.y + 3}}}) do
        local pick, drop = thing_at(ins.pickup_position, ins), thing_at(ins.drop_position, ins)
        if pick == b and drop then
          for _, it in pairs(wants(drop)) do if not need[it] then need[it] = true order[#order + 1] = it end end
        elseif drop == b and pick then
          for _, it in pairs(makes(pick)) do supplied[it] = true end
        end
      end
      for _, n in pairs(b.belt_neighbours.outputs) do queue[#queue + 1] = n end
      for _, n in pairs(b.belt_neighbours.inputs) do
        if not seen[n.unit_number] then for it in pairs(supplied_upstream(n)) do supplied[it] = true end end
      end
      if b.type == "underground-belt" and b.neighbours then queue[#queue + 1] = b.neighbours end
    end
  end
  local external = {}
  for _, it in ipairs(order) do if not supplied[it] then external[#external + 1] = it end end
  return external
end

-- a dead end is an output only when no inserter takes from that belt upstream of it: a supply line just stops
local function consumed_upstream(stop)
  local seen, queue = {}, {stop}
  while #queue > 0 do
    local b = table.remove(queue, 1)
    if b.valid and not seen[b.unit_number] then
      seen[b.unit_number] = true
      for _, ins in pairs(s.find_entities_filtered{type = "inserter", area = {{b.position.x - 3, b.position.y - 3}, {b.position.x + 3, b.position.y + 3}}}) do
        if thing_at(ins.pickup_position, ins) == b then return true end
      end
      for _, n in pairs(b.belt_neighbours.inputs) do queue[#queue + 1] = n end
      if b.type == "underground-belt" and b.neighbours then queue[#queue + 1] = b.neighbours end
    end
  end
  return false
end

local function wire_declared()
  local ox, oy = gx, gy
  for _, p in pairs(B.ports) do
    local pos = {x = p.x + ox, y = p.y + oy}
    local ok
    if p.kind == "belt-in" then
      local tee = at(pos, 1, OPP[p.direction])
      ok = put{name = p.name == "underground-belt" and "transport-belt" or p.name, position = tee, direction = p.direction} ~= nil
      -- a lane that read empty in a starved base gets what this belt's consumers still lack
      local lanes = {p.lanes[1] or {}, p.lanes[2] or {}}
      local here = s.find_entities_filtered{position = pos, type = {"transport-belt", "underground-belt", "splitter"}}[1]
      if here and (#lanes[1] == 0 or #lanes[2] == 0) then
        local have = {}
        for _, l in pairs(lanes) do for _, it in pairs(l) do have[it] = true end end
        for _, it in ipairs(demand_along(here)) do
          if not have[it] then
            if #lanes[1] == 0 then lanes[1] = {it} elseif #lanes[2] == 0 then lanes[2] = {it} end
            have[it] = true
          end
        end
      end
      p.lanes = lanes
      for lane, d in ipairs{LEFT[p.direction], OPP[LEFT[p.direction]]} do
        local items = lanes[lane]
        if #items > 0 then
          local ld = put{name = "loader-1x1", position = at(tee, 1, d), direction = OPP[d], type = "output"}
          ok = ok and ld ~= nil and source(at(tee, 2, d), items) ~= nil
        end
      end
    elseif p.kind == "belt-out" then
      ok = put{name = "loader-1x1", position = at(pos, 1, p.direction), direction = p.direction, type = "input"} ~= nil
        and void(at(pos, 2, p.direction)) ~= nil
    elseif p.kind == "inserter-in" then
      ok = #p.items > 0 and source(pos, p.items) ~= nil
    elseif p.kind == "inserter-out" then
      ok = void(pos) ~= nil
    end
    ports[#ports + 1] = {kind = p.kind, x = pos.x, y = pos.y, items = p.items or p.lanes, ok = ok}
    if not ok then unhandled[#unhandled + 1] = string.format("%s (%.1f,%.1f)", p.kind, pos.x, pos.y) end
  end
end

-- Without declared ports, guess them from the design.
local function wire_guessed()
local belt_types = {"transport-belt", "fast-transport-belt", "express-transport-belt", "turbo-transport-belt"}
for _, b in pairs(s.find_entities_filtered{name = belt_types}) do
  local n = b.belt_neighbours
  local items = #n.inputs == 0 and demand_along(b) or {}
  if #items > 0 then
    local tee = at(b.position, 1, OPP[b.direction])
    local t = put{name = b.name, position = tee, direction = b.direction}
    local placed = t ~= nil
    if placed then
      local l, r = LEFT[b.direction], OPP[LEFT[b.direction]]
      local lanes = {items[1], items[2] or items[1]}
      if (B.swap or {})[string.format("%.1f,%.1f", b.position.x, b.position.y)] then lanes = {lanes[2], lanes[1]} end
      for side, d in ipairs{l, r} do
        if lanes[side] then
          local lp = at(tee, 1, d)
          local ld = put{name = "loader-1x1", position = lp, direction = OPP[d], type = "output"}
          local ch = ld and source(at(tee, 2, d), {lanes[side]})
          placed = placed and ld ~= nil and ch ~= nil
        end
      end
    end
    ports[#ports + 1] = {kind = "belt-in", x = b.position.x, y = b.position.y, items = items, ok = placed}
    if not placed then unhandled[#unhandled + 1] = string.format("belt-in (%.1f,%.1f) blocked", b.position.x, b.position.y) end
  end
  if #n.outputs == 0 and not consumed_upstream(b) then
    local lp = at(b.position, 1, b.direction)
    local ld = put{name = "loader-1x1", position = lp, direction = b.direction, type = "input"}
    local ch = ld and void(at(b.position, 2, b.direction))
    ports[#ports + 1] = {kind = "belt-out", x = b.position.x, y = b.position.y, ok = ch ~= nil}
    if not ch then unhandled[#unhandled + 1] = string.format("belt-out (%.1f,%.1f) blocked", b.position.x, b.position.y) end
  end
end

for _, ins in pairs(s.find_entities_filtered{type = "inserter"}) do
  if design[ins.unit_number] then
    local pick, drop = thing_at(ins.pickup_position, ins), thing_at(ins.drop_position, ins)
    if not pick and drop then
      local items = wants(drop)
      local ok = #items > 0 and source(ins.pickup_position, items) ~= nil
      ports[#ports + 1] = {kind = "inserter-in", x = ins.position.x, y = ins.position.y, items = items, ok = ok}
      if not ok then unhandled[#unhandled + 1] = string.format("inserter-in (%.1f,%.1f)", ins.position.x, ins.position.y) end
    elseif pick and not drop then
      local ok = void(ins.drop_position) ~= nil
      ports[#ports + 1] = {kind = "inserter-out", x = ins.position.x, y = ins.position.y, ok = ok}
      if not ok then unhandled[#unhandled + 1] = string.format("inserter-out (%.1f,%.1f)", ins.position.x, ins.position.y) end
    end
  end
end

end

if B.ports then wire_declared() else wire_guessed() end

for _, e in pairs(built) do
  if e.valid and e.burner then e.insert{name = B.fuel or "coal", count = 50} end
  local ok, fb = pcall(function() return e.fluidbox end)
  if e.valid and ok and fb and #fb > 0 then
    for i = 1, #fb do
      for _, c in pairs(fb.get_pipe_connections(i)) do
        if not c.target then unhandled[#unhandled + 1] = string.format("fluid %s (%.1f,%.1f)", e.name, c.target_position.x, c.target_position.y) end
      end
    end
  end
end

s.create_global_electric_network()
local eei = s.create_entity{name = "electric-energy-interface", position = {100, 100}, force = force}
eei.power_production = 1e10 eei.electric_buffer_size = 1e11 eei.energy = 1e11
rcon.print(helpers.table_to_json{entities = #built, ghosts = #ghosts, ports = ports, unhandled = unhandled})
