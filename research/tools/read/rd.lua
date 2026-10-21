--- tool: rd
--- kind: lib
--- effect: read
--- summary: shared argument checks, paging and entity records for the read tools
--- args: none
--- returns: {ctx, fail, page, nameset, typeset, record, inventories, belt_items, merge, dir, status, r2}
local rd = {}

local DIR, STATUS = {}, {}
for k, v in pairs(defines.direction) do DIR[v] = k end
for k, v in pairs(defines.entity_status) do STATUS[v] = k end

local MAX_LIMIT, MAX_SIDE = 300, 4000

function rd.r2(v) return math.floor(v * 100 + 0.5) / 100 end
function rd.dir(d) return DIR[d] end
function rd.status(e) return e.status and STATUS[e.status] or nil end
function rd.fail(msg, hint) return {error = msg, hint = hint} end

local function sorted_keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function number(a, k)
  local v = a[k]
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    return nil, rd.fail(k .. " must be a number", "got " .. tostring(v))
  end
  return v
end

-- an integer addresses the tile whose top-left corner it is, so aim at that tile's centre
local function centre(v) return v == math.floor(v) and v + 0.5 or v end

local function whole(a, k, default, min, max)
  local v = a[k]
  if v == nil then return default end
  if type(v) ~= "number" or v ~= math.floor(v) or v < min then
    return nil, rd.fail(k .. " must be a whole number >= " .. min, "got " .. tostring(v))
  end
  if max and v > max then
    return nil, rd.fail(k .. " must be at most " .. max, "page through a longer list with offset")
  end
  return v
end

--- Check the args of a read tool and resolve surface, force, area or point and paging.
--- spec: area (x0,y0,x1,y1 required), point (x,y with optional r), either (area or point), bare (no location), paged,
--- r (default radius of a point), extra (further accepted keys).
--- Returns the context table, or nil and an {error, hint} table.
function rd.ctx(a, spec)
  if a == nil then a = {} end
  if type(a) ~= "table" then return nil, rd.fail("args must be a table of named arguments") end
  local known = {surface = true, force = true}
  if spec.paged then known.limit, known.offset = true, true end
  if spec.area or spec.either then known.x0, known.y0, known.x1, known.y1 = true, true, true, true end
  if spec.point or spec.either then known.x, known.y, known.r = true, true, true end
  for _, k in ipairs(spec.extra or {}) do known[k] = true end
  for k in pairs(a) do
    if not known[k] then
      return nil, rd.fail("unknown argument '" .. tostring(k) .. "'", "accepted: " .. table.concat(sorted_keys(known), ", "))
    end
  end

  local c = {surface = a.surface or "nauvis", force = a.force or "player"}
  if type(c.surface) ~= "string" then return nil, rd.fail("surface must be a name", "got " .. type(c.surface)) end
  if type(c.force) ~= "string" then return nil, rd.fail("force must be a name", "got " .. type(c.force)) end
  c.s = game.surfaces[c.surface]
  if not c.s then
    local names = {}
    for _, s in pairs(game.surfaces) do names[#names + 1] = s.name end
    table.sort(names)
    return nil, rd.fail("no surface named '" .. tostring(c.surface) .. "'", "surfaces: " .. table.concat(names, ", "))
  end
  c.f = game.forces[c.force]
  if not c.f then return nil, rd.fail("no force named '" .. tostring(c.force) .. "'") end

  local err
  if spec.paged then
    c.limit, err = whole(a, "limit", spec.limit or 200, 1, MAX_LIMIT)
    if err then return nil, err end
    c.offset, err = whole(a, "offset", 0, 0)
    if err then return nil, err end
  end

  local has_area = a.x0 ~= nil or a.y0 ~= nil or a.x1 ~= nil or a.y1 ~= nil
  local has_point = a.x ~= nil or a.y ~= nil
  if (spec.area or spec.either) and has_area then
    for _, k in ipairs{"x0", "y0", "x1", "y1"} do
      c[k], err = number(a, k)
      if err then return nil, err end
    end
    if c.x1 < c.x0 or c.y1 < c.y0 then
      return nil, rd.fail("the area runs backwards", "give the top-left corner (x0, y0), then the bottom-right (x1, y1)")
    end
    if c.x1 - c.x0 > MAX_SIDE or c.y1 - c.y0 > MAX_SIDE then
      return nil, rd.fail("the area is larger than " .. MAX_SIDE .. " tiles on a side", "split it, or ask for counts")
    end
  elseif (spec.point or spec.either) and has_point then
    c.x, err = number(a, "x")
    if err then return nil, err end
    c.y, err = number(a, "y")
    if err then return nil, err end
    c.x, c.y = centre(c.x), centre(c.y)
    c.r = a.r == nil and (spec.r or 0) or a.r
    if type(c.r) ~= "number" or c.r ~= c.r or c.r < 0 or c.r > MAX_SIDE then
      return nil, rd.fail("r must be a number from 0 to " .. MAX_SIDE, "got " .. tostring(a.r))
    end
    c.point = true
    c.x0, c.y0, c.x1, c.y1 = c.x - c.r - 0.01, c.y - c.r - 0.01, c.x + c.r + 0.01, c.y + c.r + 0.01
  elseif spec.bare then
    return c
  elseif spec.area then
    return nil, rd.fail("x0, y0, x1 and y1 are required", "an area is the top-left corner (x0, y0) and the bottom-right (x1, y1)")
  elseif spec.point then
    return nil, rd.fail("x and y are required", "a point is x, y")
  else
    return nil, rd.fail("x0, y0, x1, y1 or x, y are required", "an area, or a point with optional r")
  end
  c.area = {{c.x0, c.y0}, {c.x1, c.y1}}
  return c
end

--- Put a slice of `list` into res[key], with the total, and `more` and `next` (the next offset) when the cap cut it.
function rd.page(res, key, list, c)
  local total = #list
  local last = math.min(total, c.offset + c.limit)
  local out = {}
  for i = c.offset + 1, last do out[#out + 1] = list[i] end
  res[key], res.total = out, total
  if last < total then res.more, res.next = true, last end
  return res
end

local function suggest(name, kind)
  local hits = {}
  for n in pairs(prototypes[kind]) do
    if n:find(name, 1, true) or (#n > 3 and name:find(n, 1, true)) then hits[#hits + 1] = n end
  end
  table.sort(hits)
  while #hits > 5 do hits[#hits] = nil end
  return #hits > 0 and ("similar: " .. table.concat(hits, ", ")) or "names are prototype ids such as 'iron-plate' or 'transport-belt'"
end

--- A name or a list of names, checked against prototypes[kind] ("item", "entity", "fluid", "recipe").
--- Returns the set and the list, or nil and an error table.
function rd.nameset(v, kind, field)
  if type(v) == "string" then v = {v} end
  if type(v) ~= "table" or #v == 0 then
    return nil, rd.fail(field .. " must be a name or a list of names")
  end
  local set, list = {}, {}
  for _, n in ipairs(v) do
    if type(n) ~= "string" or not prototypes[kind][n] then
      return nil, rd.fail("unknown " .. kind .. " name '" .. tostring(n) .. "' in " .. field, suggest(tostring(n), kind))
    end
    if not set[n] then set[n] = true list[#list + 1] = n end
  end
  return set, list
end

--- An entity type or a list of types, checked against the types of the entity prototypes.
function rd.typeset(v, field)
  if type(v) == "string" then v = {v} end
  if type(v) ~= "table" or #v == 0 then return nil, rd.fail(field .. " must be a type or a list of types") end
  local known = {}
  for _, p in pairs(prototypes.entity) do known[p.type] = true end
  local set, list = {}, {}
  for _, t in ipairs(v) do
    if type(t) ~= "string" or not known[t] then
      return nil, rd.fail("unknown entity type '" .. tostring(t) .. "' in " .. field,
        "types are such as 'inserter', 'assembling-machine', 'transport-belt'")
    end
    if not set[t] then set[t] = true list[#list + 1] = t end
  end
  return set, list
end

--- Add the counts of the item -> count table `from` into `into`.
function rd.add(into, from)
  for n, v in pairs(from) do into[n] = (into[n] or 0) + v end
  return into
end

--- Add the contents of `inv` (an inventory) into the item -> count table `into`.
function rd.merge(into, inv)
  for _, it in pairs(inv.get_contents()) do into[it.name] = (into[it.name] or 0) + it.count end
  return into
end

local I = defines.inventory
local ROLES = {
  ["container"] = {{"chest", I.chest}},
  ["logistic-container"] = {{"chest", I.chest}},
  ["infinity-container"] = {{"chest", I.chest}},
  ["linked-container"] = {{"chest", I.linked_container_main}},
  ["cargo-wagon"] = {{"chest", I.cargo_wagon}},
  ["assembling-machine"] = {{"fuel", I.fuel}, {"input", I.crafter_input}, {"output", I.crafter_output},
    {"modules", I.crafter_modules}, {"output", I.assembling_machine_dump}, {"burnt", I.burnt_result}},
  ["furnace"] = {{"fuel", I.fuel}, {"input", I.crafter_input}, {"output", I.crafter_output},
    {"modules", I.crafter_modules}, {"burnt", I.burnt_result}},
  ["lab"] = {{"fuel", I.fuel}, {"input", I.lab_input}, {"modules", I.lab_modules}},
  ["mining-drill"] = {{"fuel", I.fuel}, {"modules", I.mining_drill_modules}, {"burnt", I.burnt_result}},
  ["boiler"] = {{"fuel", I.fuel}, {"burnt", I.burnt_result}},
  ["burner-generator"] = {{"fuel", I.fuel}, {"burnt", I.burnt_result}},
  ["reactor"] = {{"fuel", I.fuel}, {"burnt", I.burnt_result}},
  ["inserter"] = {{"fuel", I.fuel}},
  ["locomotive"] = {{"fuel", I.fuel}},
  ["ammo-turret"] = {{"ammo", I.turret_ammo}},
  ["roboport"] = {{"robots", I.roboport_robot}, {"material", I.roboport_material}},
  ["beacon"] = {{"modules", I.beacon_modules}},
  ["agricultural-tower"] = {{"input", I.agricultural_tower_input}, {"output", I.agricultural_tower_output},
    {"modules", I.agricultural_tower_modules}},
  ["car"] = {{"fuel", I.fuel}, {"trunk", I.car_trunk}, {"ammo", I.car_ammo}},
}

rd.INVENTORY_TYPES = {}
for t in pairs(ROLES) do rd.INVENTORY_TYPES[#rd.INVENTORY_TYPES + 1] = t end
table.sort(rd.INVENTORY_TYPES)
-- electric inserters hold nothing, so only an explicit type reaches the burner ones
rd.STOCK_TYPES = {}
for _, t in ipairs(rd.INVENTORY_TYPES) do
  if t ~= "inserter" then rd.STOCK_TYPES[#rd.STOCK_TYPES + 1] = t end
end

--- The entity's inventories by kind (input, output, fuel, modules, chest, ...), each merged by item.
--- Empty kinds are left out. The result is nil when nothing is inside.
function rd.inventories(e)
  local roles = ROLES[e.type]
  if not roles then return nil end
  local out
  for _, role in ipairs(roles) do
    local inv = e.get_inventory(role[2])
    if inv then
      local contents = inv.get_contents()
      if contents[1] then
        out = out or {}
        local items = out[role[1]]
        if not items then items = {} out[role[1]] = items end
        for _, it in ipairs(contents) do items[it.name] = (items[it.name] or 0) + it.count end
      end
    end
  end
  return out
end

local BELT_TYPES = {["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true,
  ["loader"] = true, ["loader-1x1"] = true, ["linked-belt"] = true, ["lane-splitter"] = true}
rd.BELT_TYPES = BELT_TYPES

--- Items on a belt-like entity as left, right lane tables. Odd transport lines are the left lane.
--- An underground entrance also holds the items travelling under the ground, on its lines 3 and 4.
function rd.belt_items(e)
  local left, right = {}, {}
  local n = e.get_max_transport_line_index()
  if e.type == "underground-belt" and e.belt_to_ground_type == "output" then n = math.min(n, 2) end
  for i = 1, n do
    rd.merge(i % 2 == 1 and left or right, e.get_transport_line(i))
  end
  return left, right
end

local ROTATES = {}
local function rotates(name)
  local v = ROTATES[name]
  if v == nil then
    v = prototypes.entity[name].supports_direction and true or false
    ROTATES[name] = v
  end
  return v
end

local STATUS_TYPES = {}
for _, t in ipairs{"assembling-machine", "furnace", "lab", "mining-drill", "inserter", "boiler", "generator",
    "reactor", "burner-generator", "ammo-turret", "fluid-turret", "electric-turret", "radar", "roboport", "pump",
    "offshore-pump", "rocket-silo", "beacon", "accumulator", "solar-panel", "lamp", "agricultural-tower"} do
  STATUS_TYPES[t] = true
end
rd.STATUS_TYPES = STATUS_TYPES

local function point(p) return {rd.r2(p.x), rd.r2(p.y)} end

--- The short fixed record of an entity: name, x, y and only the fields that apply.
--- dir, recipe, status, ghost, deconstruct; pickup and drop on an inserter instead of dir (the engine direction of an
--- inserter is its pickup side), drop on a drill, io on an underground belt.
function rd.record(e)
  local p = e.position
  if e.type == "entity-ghost" then
    local r = {name = e.ghost_name, x = rd.r2(p.x), y = rd.r2(p.y), ghost = true}
    if rotates(e.ghost_name) and e.ghost_type ~= "inserter" then r.dir = DIR[e.direction] end
    return r
  end
  local r = {name = e.name, x = rd.r2(p.x), y = rd.r2(p.y)}
  local t = e.type
  if t ~= "inserter" and rotates(e.name) then r.dir = DIR[e.direction] end
  if t == "assembling-machine" or t == "furnace" then
    local recipe = e.get_recipe()
    if recipe then r.recipe = recipe.name end
  elseif t == "inserter" then
    r.pickup, r.drop = point(e.pickup_position), point(e.drop_position)
  elseif t == "mining-drill" then
    r.drop = point(e.drop_position)
  elseif t == "underground-belt" then
    r.io = e.belt_to_ground_type
  end
  if STATUS_TYPES[t] then
    local st = e.status
    if st then r.status = STATUS[st] end
  end
  if e.to_be_deconstructed() then r.deconstruct = true end
  return r
end

rd.READ_CAP = 2000

local function by_place(p, q)
  if p.y ~= q.y then return p.y < q.y end
  if p.x ~= q.x then return p.x < q.x end
  return p.u < q.u
end

--- Entities in c.area for c.force, ghosts included, sorted by y then x so a page stays put between calls.
--- filter: names and types (lists, from nameset and typeset), ghosts (true: only ghosts, false: none, nil: both),
--- unsorted (skip the sort and the position reads), cap (default READ_CAP), hint (for the error).
--- Ghosts match names and types by what they stand for.
--- The engine stops one past the cap: more than the cap returns nil and an error table, so no call reads more than that.
function rd.find(c, filter)
  filter = filter or {}
  local cap = filter.cap or rd.READ_CAP
  local names, types, ghosts = filter.names, filter.types, filter.ghosts
  local plain, ghost = {}, {}
  if ghosts ~= true then
    plain = c.s.find_entities_filtered{area = c.area, force = c.force, name = names, type = types, limit = cap + 1}
  end
  if ghosts ~= false then
    ghost = c.s.find_entities_filtered{area = c.area, force = c.force, name = "entity-ghost", limit = cap + 1}
  end
  if #plain + #ghost > cap then
    return nil, rd.fail(string.format("more than %d entities match in that area; a call reads at most %d", cap, cap),
      filter.hint or "narrow the area, or add name or type")
  end
  local name_set, type_set = {}, {}
  for _, n in ipairs(names or {}) do name_set[n] = true end
  for _, t in ipairs(types or {}) do type_set[t] = true end
  local found = {}
  local function take(list, ghost_only)
    for _, e in pairs(list) do
      local keep = not ghost_only or
        ((not names or name_set[e.ghost_name]) and (not types or type_set[e.ghost_type]))
      if keep and filter.unsorted then
        found[#found + 1] = e
      elseif keep then
        local p = e.position
        found[#found + 1] = {e = e, x = p.x, y = p.y, u = e.unit_number or 0}
      end
    end
  end
  take(plain, false)
  take(ghost, true)
  if filter.unsorted then return found end
  table.sort(found, by_place)
  local out = {}
  for i, f in ipairs(found) do out[i] = f.e end
  return out
end

return rd
