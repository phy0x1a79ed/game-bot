--- tool: status
--- kind: call
--- effect: read
--- summary: machines in an area grouped by status; each one that is not working names its recipe and the inputs it lacks
--- args: x0, y0, x1, y1 (numbers); name, type (string or list; default: assemblers, furnaces, labs, drills, boilers, generators, reactors); working (bool: list working machines too); limit (default 200, max 300), offset; surface, force
--- returns: {counts = {status = n}, groups = {status = {{name, x, y, recipe, missing = {item}, output = {item = n}}, ...}}, total, more, next}; total counts the listed machines; {error, hint} on bad args
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {area = true, paged = true, extra = {"name", "type", "working"}})
if not c then return err end

local filter = {ghosts = false}
if a.name ~= nil then
  local set, list = rd.nameset(a.name, "entity", "name")
  if not set then return list end
  filter.names = list
end
if a.type ~= nil then
  local set, list = rd.typeset(a.type, "type")
  if not set then return list end
  filter.types = list
end
if not (filter.names or filter.types) then
  filter.types = {"assembling-machine", "furnace", "lab", "mining-drill", "boiler", "generator", "reactor",
    "burner-generator", "rocket-silo"}
end

local I = defines.inventory

local function lacking(e)
  local out = {}
  local recipe = (e.type == "assembling-machine" or e.type == "furnace") and e.get_recipe()
  if recipe then
    local inv = e.get_inventory(I.crafter_input)
    for _, ing in ipairs(recipe.ingredients) do
      local have = ing.type == "fluid" and e.get_fluid_count(ing.name) or (inv and inv.get_item_count(ing.name) or 0)
      if have < ing.amount then out[#out + 1] = ing.name end
    end
  elseif e.type == "lab" then
    local research = e.force.current_research
    local inv = e.get_inventory(I.lab_input)
    if research and inv then
      for _, ing in ipairs(research.research_unit_ingredients) do
        if inv.get_item_count(ing.name) == 0 then out[#out + 1] = ing.name end
      end
    end
  end
  return out
end

local found, cut = rd.find(c, filter)
if not found then return cut end

local counts, listed = {}, {}
for i, e in ipairs(found) do
  local st = rd.status(e) or "unknown"
  counts[st] = (counts[st] or 0) + 1
  if st ~= "working" or a.working then listed[#listed + 1] = {status = st, e = e, i = i} end
end
table.sort(listed, function(x, y)
  if x.status ~= y.status then return x.status < y.status end
  return x.i < y.i
end)

-- records are built for the page only
local page = rd.page({}, "list", listed, c)
local groups = {}
for _, item in ipairs(page.list) do
  local e, st = item.e, item.status
  local r = rd.record(e)
  r.status, r.dir = nil, nil
  if st == "no_fuel" then
    r.missing = {"fuel"}
  elseif st == "full_output" then
    local inv = e.get_output_inventory()
    if inv then r.output = rd.merge({}, inv) end
  else
    local m = lacking(e)
    if #m > 0 then r.missing = m end
  end
  local g = groups[st]
  if not g then g = {} groups[st] = g end
  g[#g + 1] = r
end
page.list = nil
page.counts, page.groups = counts, groups
return page
