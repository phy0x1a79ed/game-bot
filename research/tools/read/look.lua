--- tool: look
--- kind: call
--- effect: read
--- summary: entities in an area as short records, filtered by name, type or ghost; count = true tallies names only
--- args: x0, y0, x1, y1 (numbers); name, type (a string or a list); ghosts (true: only ghosts, false: none); count (bool); limit (default 200, max 1000), offset; surface (default nauvis), force (default player)
--- returns: {entities = {{name, x, y, dir, recipe, status, ghost, deconstruct, pickup = {x, y}, drop = {x, y}, io}, ...}, total, more, next} or {counts = {name = n}, ghost_counts, total}; {error, hint} on bad args
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {area = true, paged = true, extra = {"name", "type", "ghosts", "count"}})
if not c then return err end

local filter = {}
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
if a.ghosts ~= nil then
  if type(a.ghosts) ~= "boolean" then return rd.fail("ghosts must be true or false", "true: only ghosts, false: none") end
  filter.ghosts = a.ghosts
end

local found = rd.find(c, filter)

if a.count then
  local counts, ghost_counts = {}, {}
  for _, e in ipairs(found) do
    if e.type == "entity-ghost" then
      ghost_counts[e.ghost_name] = (ghost_counts[e.ghost_name] or 0) + 1
    else
      counts[e.name] = (counts[e.name] or 0) + 1
    end
  end
  return {counts = counts, ghost_counts = next(ghost_counts) and ghost_counts or nil, total = #found}
end

local page = rd.page({}, "entities", found, c)
for i, e in ipairs(page.entities) do page.entities[i] = rd.record(e) end
return page
