--- tool: inventory
--- kind: call
--- effect: read
--- summary: what machines and chests hold, by inventory kind and item; sum = true gives item totals only
--- args: x0, y0, x1, y1 (an area) or x, y with r (a point, default r 0); name, type (string or list); item (string or list: report only these); belts (bool: include items on belts); sum (bool); limit (default 200, max 300), offset; surface, force; rows come in engine order
--- returns: {entities = {{name, x, y, input = {item = n}, output, fuel, modules, chest, ammo, belt, ...}, ...}, total, more, next} or {totals = {item = n}, entities = k}; {error, hint} on bad args
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {either = true, paged = true, extra = {"name", "type", "item", "belts", "sum"}})
if not c then return err end

local filter, want = {ghosts = false}, nil
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
if a.item ~= nil then
  local set, list = rd.nameset(a.item, "item", "item")
  if not set then return list end
  want = set
end
if not (filter.names or filter.types) then
  filter.types = {table.unpack(rd.STOCK_TYPES)}
  if a.belts then
    for t in pairs(rd.BELT_TYPES) do filter.types[#filter.types + 1] = t end
  end
end

local function keep(items)
  if not want then return items end
  local out
  for n, v in pairs(items) do
    if want[n] then out = out or {} out[n] = v end
  end
  return out
end

local rows, totals = {}, {}
filter.unsorted, filter.cap = true, 1200
local found, cut = rd.find(c, filter)
if not found then return cut end
for _, e in ipairs(found) do
  local row = {}
  local kinds = rd.inventories(e) or {}
  if a.belts and rd.BELT_TYPES[e.type] then
    local left, right = rd.belt_items(e)
    local belt = rd.add(rd.add({}, left), right)
    kinds.belt = next(belt) and belt or nil
  end
  local any = false
  for kind, items in pairs(kinds) do
    items = keep(items)
    if items then
      any = true
      row[kind] = items
      for n, v in pairs(items) do totals[n] = (totals[n] or 0) + v end
    end
  end
  if any or (c.point and not want) then
    if not a.sum then
      local p = e.position
      row.name, row.x, row.y = e.name, rd.r2(p.x), rd.r2(p.y)
    end
    rows[#rows + 1] = row
  end
end

if c.point and #rows == 0 then
  return rd.fail(string.format("nothing with an inventory within %.1f of (%.1f, %.1f)", c.r, c.x, c.y),
    "only entities that have inventories are listed; give r to widen, or use look to see what is there")
end
if a.sum then return {totals = totals, entities = #rows} end
return rd.page({}, "entities", rows, c)
