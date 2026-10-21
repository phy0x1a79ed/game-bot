-- Reads what a rectangle holds, the same way on a slice and on the source surface.
-- Input: global ARGS = {{key, surface, area, closers}, ...}, where `closers` lists {name, x, y} of the entities that port
-- closers placed (read from the sandbox ledger). Prints one JSON object keyed by `key`:
--   tick, stock = {item = count},
--   recipes = {name = {energy, products, ingredients}},
--   machines = {["name@x,y"] = {r = recipe, pf = products_finished, pg = crafting_progress, sp = crafting_speed,
--                                pb = productivity_bonus}}.
-- products_finished already counts the productivity bonus, so it is in product units, and the craft under way counts
-- crafting_progress x (1 + pb). The caller takes deltas per machine and only for a machine that kept its recipe.
-- A machine counts when its centre lies inside the rectangle. Closers hold nothing that belongs to the module, so the
-- stock leaves them out.

local MACHINES = {"assembling-machine", "furnace", "rocket-silo"}
-- defines.inventory has aliases (several names for one index): read each index once, and none that holds modules
local MODULE_INDEX, STOCK_INVENTORIES, seen = {}, {}, {}
for key, index in pairs(defines.inventory) do
  if key:find("module") then MODULE_INDEX[index] = true end
end
for _, index in pairs(defines.inventory) do
  if not MODULE_INDEX[index] and not seen[index] then
    seen[index] = true
    STOCK_INVENTORIES[#STOCK_INVENTORIES + 1] = index
  end
end

local function spot(name, x, y) return string.format("%s@%.2f,%.2f", name, x, y) end

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

local function read(surface, a, closers)
  local skip = {}
  for _, c in ipairs(closers) do skip[spot(c[1], c[2], c[3])] = true end
  local out = {tick = game.tick, recipes = {}, machines = {}, stock = {}}
  for _, e in pairs(surface.find_entities_filtered{area = a, type = MACHINES}) do
    if inside(e, a) then
      local recipe = e.get_recipe()
      if not recipe and e.type == "furnace" then recipe = e.previous_recipe end
      if recipe then
        local name = name_of(recipe.name or recipe)
        out.recipes[name] = out.recipes[name] or recipe_info(name)
        out.machines[spot(e.name, e.position.x, e.position.y)] = {
          r = name, pf = e.products_finished, pg = e.crafting_progress, sp = e.crafting_speed, pb = e.productivity_bonus}
      end
    end
  end
  for _, e in pairs(surface.find_entities_filtered{area = a}) do
    if inside(e, a) and not skip[spot(e.name, e.position.x, e.position.y)] and e.type ~= "entity-ghost"
       and e.type ~= "resource" then
      stock_of(e, out.stock)
    end
  end
  return out
end

local out = {}
for _, q in ipairs(ARGS) do out[q[1]] = read(game.surfaces[q[2]], q[3], q[4] or {}) end
rcon.print(helpers.table_to_json(out))
