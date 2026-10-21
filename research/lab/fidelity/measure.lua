-- Reads what a rectangle has made so far, the same way on a slice and on the source surface.
-- Input: global ARGS = {{key, surface, area}, ...}. Prints one JSON object keyed by `key`:
--   tick, recipes = {name = {n, working, speed, cap, crafts, pcrafts, energy, products, ingredients}}, stock = {item = count}.
-- `working` is how many of the `n` machines have the status working at this tick.
-- crafts counts finished crafts plus the progress of the craft under way, so a short window has no integer noise.
-- A machine counts when its centre lies inside the rectangle. Port closers (loaders, infinity chests and pipes,
-- the energy interface) hold nothing that belongs to the module, so the stock leaves them out.

local CLOSERS = {["loader-1x1"] = true, ["infinity-chest"] = true, ["infinity-pipe"] = true,
                 ["electric-energy-interface"] = true}
local MACHINES = {"assembling-machine", "furnace", "rocket-silo"}
local STOCK_INVENTORIES = {}
for key, index in pairs(defines.inventory) do
  if not key:find("module") then STOCK_INVENTORIES[#STOCK_INVENTORIES + 1] = index end
end

local function name_of(x)
  if type(x) == "string" then return x end
  return x.name
end

local function inside(e, a)
  local p = e.position
  return p.x >= a[1][1] and p.x < a[2][1] and p.y >= a[1][2] and p.y < a[2][2]
end

local function expected(entry)
  return (entry.amount or ((entry.amount_min + entry.amount_max) / 2)) * (entry.probability or 1)
end

local function recipe_info(name)
  local proto = prototypes.recipe[name]
  local info = {energy = proto.energy, products = {}, ingredients = {}}
  for _, p in ipairs(proto.products) do
    info.products[p.name] = (info.products[p.name] or 0) + expected(p)
  end
  for _, i in ipairs(proto.ingredients) do info.ingredients[i.name] = (info.ingredients[i.name] or 0) + i.amount end
  return info
end

local function add(t, k, v) t[k] = (t[k] or 0) + v end

local function contents(into, list)
  for _, c in pairs(list) do add(into, c.name, c.count) end
end

local function stock_of(e, into)
  if e.type == "transport-belt" or e.type == "underground-belt" or e.type == "splitter" or e.type == "linked-belt" then
    for i = 1, e.get_max_transport_line_index() do contents(into, e.get_transport_line(i).get_contents()) end
    return
  end
  for _, index in ipairs(STOCK_INVENTORIES) do
    local ok, inv = pcall(e.get_inventory, index)
    if ok and inv and inv.valid then contents(into, inv.get_contents()) end
  end
  if e.type == "inserter" then
    local hand = e.held_stack
    if hand and hand.valid_for_read then add(into, hand.name, hand.count) end
  end
  if e.fluids_count > 0 then
    for fluid, amount in pairs(e.get_fluid_contents()) do add(into, fluid, amount) end
  end
end

local function read(surface, a)
  local out = {tick = game.tick, recipes = {}, stock = {}}
  for _, e in pairs(surface.find_entities_filtered{area = a, type = MACHINES}) do
    if inside(e, a) then
      local recipe = e.get_recipe()
      if not recipe and e.type == "furnace" then recipe = e.previous_recipe end
      if recipe then
        local name = name_of(recipe.name or recipe)
        local r = out.recipes[name]
        if not r then
          r = recipe_info(name)
          r.n, r.speed, r.cap, r.crafts, r.pcrafts, r.working = 0, 0, 0, 0, 0, 0
          out.recipes[name] = r
        end
        local done = e.products_finished + e.crafting_progress
        r.n = r.n + 1
        if e.status == defines.entity_status.working then r.working = r.working + 1 end
        r.speed = r.speed + e.crafting_speed
        r.cap = r.cap + e.crafting_speed * (1 + e.productivity_bonus)
        r.crafts = r.crafts + done
        r.pcrafts = r.pcrafts + done * (1 + e.productivity_bonus)
      end
    end
  end
  for _, e in pairs(surface.find_entities_filtered{area = a}) do
    if inside(e, a) and not CLOSERS[e.name] and e.type ~= "entity-ghost" and e.type ~= "resource" then
      stock_of(e, out.stock)
    end
  end
  return out
end

local out = {}
for _, q in ipairs(ARGS) do out[q[1]] = read(game.surfaces[q[2]], q[3]) end
rcon.print(helpers.table_to_json(out))
