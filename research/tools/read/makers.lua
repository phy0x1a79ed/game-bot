--- tool: makers
--- kind: call
--- effect: read
--- summary: the machines whose recipe makes (or uses) an item, grouped into sites, with each site's ceiling per minute, statuses and short inputs, beside the measured rate
--- args: item (an item or fluid name); use (bool: the machines that consume it instead); x0, y0, x1, y1 (optional area; default the box around the robots' construction areas plus 32 tiles, or the whole surface when the force has no robot network); gap (tiles between machines of one site, default 8, max 32); limit (sites, default 50, max 300), offset; surface, force
--- returns: {item, scope = "area" | "robots" | "surface", area (the default box, when scope is robots), measured = {made, used} (per minute, 10-minute average), ceiling (per minute, all sites), machines, ghosts, recipes = {{name, energy, enabled, ingredients = {name = n}, products = {name = n}}, ...} (those the force can craft or a machine runs), locked (how many more recipes need research), sites = {{recipe, x0, y0, x1, y1, n, ghosts, speed, prod, ceiling, status = {status = n}, missing = {item = n}, full}, ...}, total, more, next}; sites run largest ceiling first; ceiling is what the site makes (or uses) of the item at full speed with its modules, beacons and recipe productivity; missing counts the machines short of each input; {error, hint} on bad args
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {either = true, bare = true, paged = true, limit = 50, extra = {"item", "use", "gap"}})
if not c then return err end

local item = a.item
if type(item) ~= "string" or not (prototypes.item[item] or prototypes.fluid[item]) then
  local _, e = rd.nameset({tostring(item)}, "item", "item")
  e.error = item == nil and "item is required" or e.error
  return e
end
local gap = a.gap == nil and 8 or a.gap
if type(gap) ~= "number" or gap < 0 or gap > 32 then return rd.fail("gap must be a number from 0 to 32", "got " .. tostring(a.gap)) end
local consume = a.use and true or false

-- expected amount of `name` per craft; productivity applies to the part not ignored by it
local function per_craft(list, name)
  local base, ignored = 0, 0
  for _, p in ipairs(list) do
    if p.name == name then
      local n = p.amount or ((p.amount_min or 0) + (p.amount_max or 0)) / 2
      n = n * (p.probability or 1) + (p.extra_count_fraction or 0)
      base = base + n
      ignored = ignored + math.min(n, p.ignored_by_productivity or 0)
    end
  end
  return base, ignored
end

local kind = prototypes.item[item] and "item" or "fluid"
local wanted = prototypes.get_recipe_filtered{{filter = (consume and "has-ingredient-" or "has-product-") .. kind,
  elem_filters = {{filter = "name", name = item}}}}

-- without an area, scan the box around the robots' construction areas: walking every chunk of a large map costs
-- about 15 ms, and a ghost outside that box never builds
local scope = c.area and "area" or "surface"
if not c.area then
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, net in pairs(c.f.logistic_networks[c.s.name] or {}) do
    for _, cell in pairs(net.cells) do
      local q, r = cell.owner.position, cell.construction_radius
      x0, y0 = math.min(x0, q.x - r), math.min(y0, q.y - r)
      x1, y1 = math.max(x1, q.x + r), math.max(y1, q.y + r)
    end
  end
  if x0 <= x1 then
    c.area = {{math.floor(x0) - 32, math.floor(y0) - 32}, {math.ceil(x1) + 32, math.ceil(y1) + 32}}
    scope = "robots"
  end
end

-- one scan for machines and ghosts together: on a large map the chunk walk, not the match, is the cost
local CAP = 4000
local CRAFTERS = {["assembling-machine"] = true, ["furnace"] = true, ["rocket-silo"] = true}
local found = c.s.find_entities_filtered{area = c.area, force = c.force, limit = CAP + 1,
  type = {"assembling-machine", "furnace", "rocket-silo", "entity-ghost"}}
if #found > CAP then
  return rd.fail(string.format("more than %d machines and ghosts in that area", CAP), "give a smaller area")
end

-- what a craft of each recipe makes or uses of the item, read once per recipe
local info = {}
local function recipe_info(name)
  local ri = info[name]
  if not ri then
    local r, fr = wanted[name], c.f.recipes[name]
    local base, ignored = per_craft(consume and r.ingredients or r.products, item)
    ri = {name = name, r = r, ingredients = r.ingredients, energy = r.energy, base = base, ignored = ignored,
      prod = fr and fr.productivity_bonus or 0}
    info[name] = ri
  end
  return ri
end

local MATCH_CAP = 600
local I = defines.inventory
local machines, ghosts = {}, 0
for _, e in ipairs(found) do
  local ghost = e.type == "entity-ghost"
  if not ghost or CRAFTERS[e.ghost_type] then
    local r = e.get_recipe()
    if not r and e.type == "furnace" then r = e.previous_recipe and e.previous_recipe.name end
    local name = r and (type(r) == "string" and r or r.name)
    if name and wanted[name] then
      if #machines == MATCH_CAP then
        return rd.fail(string.format("more than %d machines run a recipe with %s", MATCH_CAP, item), "give an area")
      end
      local p = e.position
      machines[#machines + 1] = {e = e, recipe = recipe_info(name), x = p.x, y = p.y, ghost = ghost}
      if ghost then ghosts = ghosts + 1 end
    end
  end
end

-- sites: machines of one recipe whose centres lie within gap tiles of each other, joined transitively
local parent = {}
local function root(i)
  while parent[i] ~= i do parent[i] = parent[parent[i]] i = parent[i] end
  return i
end
for i = 1, #machines do parent[i] = i end
local CELL = math.max(gap, 4) + 6
local grid = {}
for i, m in ipairs(machines) do
  local gx, gy = math.floor(m.x / CELL), math.floor(m.y / CELL)
  for dx = -1, 1 do
    for dy = -1, 1 do
      local cell = grid[(gx + dx) .. ":" .. (gy + dy)]
      if cell then
        for _, j in ipairs(cell) do
          local o = machines[j]
          if o.recipe == m.recipe and math.abs(o.x - m.x) <= gap + 6 and math.abs(o.y - m.y) <= gap + 6 then
            parent[root(i)] = root(j)
          end
        end
      end
    end
  end
  local key = gx .. ":" .. gy
  grid[key] = grid[key] or {}
  table.insert(grid[key], i)
end

local function short_inputs(e, r, missing)
  local inv = e.get_inventory(I.crafter_input)
  for _, ing in ipairs(r.ingredients) do
    local have = ing.type == "fluid" and e.get_fluid_count(ing.name) or (inv and inv.get_item_count(ing.name) or 0)
    if have < ing.amount then missing[ing.name] = (missing[ing.name] or 0) + 1 end
  end
end

local by_root, sites, total_ceiling = {}, {}, 0
for i, m in ipairs(machines) do
  local k = root(i)
  local s = by_root[k]
  if not s then
    s = {recipe = m.recipe.name, x0 = m.x, y0 = m.y, x1 = m.x, y1 = m.y, n = 0, ghosts = 0, speed = 0, prod = 0,
      ceiling = 0, status = {}, missing = {}, full = 0}
    by_root[k] = s
    sites[#sites + 1] = s
  end
  s.x0, s.y0 = math.min(s.x0, m.x), math.min(s.y0, m.y)
  s.x1, s.y1 = math.max(s.x1, m.x), math.max(s.y1, m.y)
  if m.ghost then
    s.ghosts = s.ghosts + 1
  else
    local e, r = m.e, m.recipe
    s.n = s.n + 1
    local prod = e.productivity_bonus + r.prod
    local amount = consume and r.base or (r.base - r.ignored) * (1 + prod) + r.ignored
    local rate = e.crafting_speed * 60 / r.energy * amount
    s.speed, s.prod, s.ceiling = s.speed + e.crafting_speed, s.prod + prod, s.ceiling + rate
    local st = rd.status(e) or "unknown"
    s.status[st] = (s.status[st] or 0) + 1
    if st == "full_output" then s.full = s.full + 1
    elseif st ~= "working" then short_inputs(e, r, s.missing) end
  end
end

for _, s in ipairs(sites) do
  total_ceiling = total_ceiling + s.ceiling
  s.x0, s.y0, s.x1, s.y1 = math.floor(s.x0), math.floor(s.y0), math.ceil(s.x1), math.ceil(s.y1)
  s.speed, s.ceiling = rd.r2(s.speed), rd.r2(s.ceiling)
  s.prod = s.n > 0 and rd.r2(s.prod / s.n) or 0
  if s.full == 0 then s.full = nil end
  if next(s.missing) == nil then s.missing = nil end
end
table.sort(sites, function(p, q)
  if p.ceiling ~= q.ceiling then return p.ceiling > q.ceiling end
  if p.y0 ~= q.y0 then return p.y0 < q.y0 end
  return p.x0 < q.x0
end)

-- list the recipes the force can craft or a machine runs; count the locked ones, leaving out hidden ones like recycling
local used, recipes, locked = {}, {}, 0
for _, s in ipairs(sites) do used[s.recipe] = true end
for name, r in pairs(wanted) do
  local fr = c.f.recipes[name]
  local enabled = fr and fr.enabled or false
  if enabled or used[name] then
    local ing, out = {}, {}
    for _, i in ipairs(r.ingredients) do ing[i.name] = rd.r2(i.amount) end
    for _, p in ipairs(r.products) do out[p.name] = rd.r2((per_craft(r.products, p.name))) end
    recipes[#recipes + 1] = {name = name, energy = r.energy, enabled = enabled, ingredients = ing, products = out}
  elseif not r.hidden then
    locked = locked + 1
  end
end
table.sort(recipes, function(p, q) return p.name < q.name end)
while #recipes > 20 do recipes[#recipes] = nil end

local stats = prototypes.item[item] and c.f.get_item_production_statistics(c.s) or c.f.get_fluid_production_statistics(c.s)
local P = defines.flow_precision_index.ten_minutes
local res = rd.page({}, "sites", sites, c)
res.item, res.ceiling, res.machines, res.ghosts, res.recipes = item, rd.r2(total_ceiling), #machines - ghosts, ghosts, recipes
if locked > 0 then res.locked = locked end
res.measured = {
  made = rd.r2(stats.get_flow_count{name = item, category = "input", precision_index = P, count = false}),
  used = rd.r2(stats.get_flow_count{name = item, category = "output", precision_index = P, count = false}),
}
res.scope = scope
if scope == "robots" then res.area = c.area end
if consume then res.use = true end
return res
