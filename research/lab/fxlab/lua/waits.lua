-- waits.lua: what the factory is waiting for, per item. Expects WAITS = {surface, area = {{x0, y0}, {x1, y1}} or nil}.
-- Prints JSON {waits = [...], blocked = [...], other = {status = count}}, waits largest first:
--   machines: machines whose status says an input is short, charged to each ingredient they lack
--   inserters: inserters waiting for source items, charged to what their drop target lacks (none: not a wait)
--   belts: of those inserters, the ones picking from a belt (a belt empty at the consumer)
--   ghosts: ghosts and item requests the robot network cannot cover
-- Output-blocked machines are a downstream signal: they go to `blocked`, charged to what they make.
-- A wait whose every local producer is itself short is `derived`: it ranks after the waits that cause it.
local W = WAITS
local s = game.surfaces[W.surface]
local f = game.forces.player
local filter = {force = "player", area = W.area}
local status_name = {} for k, v in pairs(defines.entity_status) do status_name[v] = k end

local waits, blocked, other = {}, {}, {}
local function entry(t, item)
  local e = t[item]
  if not e then e = {item = item, machines = 0, inserters = 0, belts = 0, ghosts = 0, at = {}} t[item] = e end
  return e
end
local function charge(t, item, field, ent)
  local e = entry(t, item)
  e[field] = e[field] + 1
  if #e.at < 5 then e.at[#e.at + 1] = {ent.name, math.floor(ent.position.x), math.floor(ent.position.y)} end
end

local SHORT = {no_ingredients = true, item_ingredient_shortage = true, no_input_fluid = true,
  fluid_ingredient_shortage = true, low_input_fluid = true, missing_science_packs = true}
local OUT_BLOCKED = {full_output = true, waiting_for_space_in_destination = true, full_burnt_result_output = true}

local CRAFTERS = {["assembling-machine"] = true, furnace = true, ["rocket-silo"] = true}
local function recipe_of(e)
  if not CRAFTERS[e.type] then return end
  local r = e.get_recipe()
  if r then return r end
  if e.type == "furnace" and e.previous_recipe then
    local name = e.previous_recipe.name
    if type(name) ~= "string" then name = name.name end
    return prototypes.recipe[name]
  end
end

local function input_inventory(e)
  if e.type == "lab" then return e.get_inventory(defines.inventory.lab_input) end
  return e.get_inventory(defines.inventory.crafter_input)
end

local function fluid_amount(e, name)
  local n = 0
  local ok, boxes = pcall(function() return e.fluidbox end)
  if not ok then return 0 end
  for i = 1, #boxes do
    local fl = boxes[i]
    if fl and fl.name == name then n = n + fl.amount end
  end
  return n
end

-- the inputs e lacks for one more craft: item names, fluids prefixed "fluid:", unknown furnace input "?"
local function lacking(e)
  local out = {}
  if e.type == "lab" then
    local r = f.current_research
    if not r then return {"(no research)"} end
    local inv = input_inventory(e)
    for _, ing in pairs(r.research_unit_ingredients) do
      if inv.get_item_count(ing.name) == 0 then out[#out + 1] = ing.name end
    end
    return out
  end
  local r = recipe_of(e)
  if not r then return {"?"} end
  local inv = input_inventory(e)
  for _, ing in pairs(r.ingredients) do
    if ing.type == "fluid" then
      if fluid_amount(e, ing.name) < ing.amount then out[#out + 1] = "fluid:" .. ing.name end
    elseif inv.get_item_count(ing.name) < ing.amount then
      out[#out + 1] = ing.name
    end
  end
  return out
end

local function products(e)
  local r = recipe_of(e)
  local out = {}
  if r then for _, p in pairs(r.products) do out[#out + 1] = (p.type == "fluid" and "fluid:" or "") .. p.name end end
  if e.type == "mining-drill" then
    local res = e.mining_target
    out[#out + 1] = res and res.name or "ore"
  end
  return out
end

local function fuel_name(e)
  local cats = {}
  for c in pairs(e.burner and e.burner.fuel_categories or {}) do cats[#cats + 1] = c end
  table.sort(cats)
  return "fuel:" .. (#cats > 0 and table.concat(cats, "+") or "?")
end

local function thing_at(p)
  for _, t in pairs(s.find_entities_filtered{position = p, force = "player"}) do
    if t.type ~= "inserter" then return t end
  end
end

local machines = {"assembling-machine", "furnace", "lab", "mining-drill", "boiler", "generator", "reactor",
  "rocket-silo", "beacon", "radar", "roboport"}
local producers = {}
for _, e in pairs(s.find_entities_filtered{force = filter.force, area = filter.area, type = machines}) do
  local st = status_name[e.status] or "?"
  for _, item in pairs(products(e)) do
    local p = producers[item] or {total = 0, short = 0}
    p.total = p.total + 1
    if SHORT[st] or st == "no_fuel" or st == "no_power" then p.short = p.short + 1 end
    producers[item] = p
  end
  if SHORT[st] then
    for _, item in pairs(lacking(e)) do charge(waits, item, "machines", e) end
  elseif OUT_BLOCKED[st] then
    for _, item in pairs(products(e)) do charge(blocked, item, "machines", e) end
  elseif st == "no_fuel" then
    charge(waits, fuel_name(e), "machines", e)
  elseif st == "no_power" or st == "low_power" then
    charge(waits, "electricity", "machines", e)
  elseif st ~= "working" and st ~= "normal" then
    other[st] = (other[st] or 0) + 1
  end
end

local BELTS = {["transport-belt"] = true, ["underground-belt"] = true, splitter = true}
for _, ins in pairs(s.find_entities_filtered{force = filter.force, area = filter.area, type = "inserter"}) do
  local st = status_name[ins.status] or "?"
  if st == "waiting_for_source_items" then
    local drop = ins.drop_target or thing_at(ins.drop_position)
    local want = {}
    if drop and (drop.type == "assembling-machine" or drop.type == "furnace" or drop.type == "lab") then
      want = lacking(drop)
    end
    local pick = ins.pickup_target or thing_at(ins.pickup_position)
    for _, item in pairs(want) do
      charge(waits, item, "inserters", ins)
      if pick and BELTS[pick.type] then entry(waits, item).belts = entry(waits, item).belts + 1 end
    end
  elseif st == "no_power" or st == "low_power" then
    charge(waits, "electricity", "inserters", ins)
  end
end

-- ghosts and item requests: count what each needs, then subtract what its robot network holds
local need = {}
local function want_item(item, n, net, ent)
  local key = item .. "|" .. (net and net.network_id or "none")
  local w = need[key]
  if not w then w = {item = item, net = net, n = 0, ent = ent} need[key] = w end
  w.n = w.n + n
end
for _, g in pairs(s.find_entities_filtered{area = filter.area, force = "player", type = {"entity-ghost", "tile-ghost"}}) do
  local items = g.ghost_prototype.items_to_place_this
  if items and items[1] then
    local net = s.find_logistic_networks_by_construction_area(g.position, f)[1]
    want_item(items[1].name, items[1].count or 1, net, g)
  end
end
for _, p in pairs(s.find_entities_filtered{area = filter.area, force = "player", type = "item-request-proxy"}) do
  local ok, reqs = pcall(function() return p.item_requests end)
  if ok and reqs then
    local net = s.find_logistic_networks_by_construction_area(p.position, f)[1]
    for _, r in pairs(reqs) do want_item(r.name, r.count, net, p) end
  end
end
for _, w in pairs(need) do
  local have = w.net and w.net.get_item_count(w.item) or 0
  local short = w.n - have
  if short > 0 then
    local e = entry(waits, w.item)
    e.ghosts = e.ghosts + short
    if #e.at < 5 then e.at[#e.at + 1] = {w.ent.name, math.floor(w.ent.position.x), math.floor(w.ent.position.y)} end
  end
end

local function ranked(t)
  local list = {}
  for _, e in pairs(t) do
    local p = producers[e.item]
    e.made_here = p and p.total or 0
    e.derived = p ~= nil and p.short == p.total
    list[#list + 1] = e
  end
  table.sort(list, function(a, b)
    if a.derived ~= b.derived then return b.derived end
    if a.machines ~= b.machines then return a.machines > b.machines end
    if a.inserters ~= b.inserters then return a.inserters > b.inserters end
    if a.ghosts ~= b.ghosts then return a.ghosts > b.ghosts end
    return a.item < b.item
  end)
  return list
end
rcon.print(helpers.table_to_json{tick = game.tick, waits = ranked(waits), blocked = ranked(blocked), other = other})
