--- tool: place
--- kind: call
--- effect: act
--- summary: place a build list as ghosts after the whole list passes check; one bad entry places nothing
--- args: list (the check format); surface (default nauvis); force (default player); accept (codes allowed on every entry)
--- returns: {ok, placed = {{i, name, position, direction, unit_number}}, bom, issues = {{i, name, position, code, msg}}, summary, warn} or {error, hint}
--- uses: intent
-- Only entity-ghosts are created, so robots build from stock. A ghost the engine refuses after a clean check
-- rolls back every ghost this call made.
local I = use("intent")
local a, err = I.prepare(...)
if not a then return err end
local ok, res = pcall(I.check, a.surface, a.force, a.list, {accept = a.accept})
if not ok then
  return {error = "the check failed on this list: " .. tostring(res):sub(1, 200), hint = "check each entry has a name and a position {x, y}"}
end
if not res.ok then
  return {ok = false, placed = {}, issues = I.failures(a.list, res), summary = "nothing placed: " .. res.summary}
end

local made, placed = {}, {}
local function rollback(i, why)
  for _, g in ipairs(made) do if g.valid then g.destroy() end end
  local raw = a.list[i]
  return {ok = false, placed = {}, summary = "nothing placed: the engine refused entry " .. i,
    issues = {{i = i, name = raw.name, position = res.entries[i].position, code = "ENGINE_REFUSED", msg = why}}}
end
for i, r in ipairs(res.entries) do
  local raw = a.list[i]
  local spec = {name = "entity-ghost", inner_name = raw.name, position = r.position, direction = r.direction, force = a.force}
  if r.type then spec.type = r.type end
  local g = a.surface.create_entity(spec)
  if not g then return rollback(i, "create_entity returned nothing for the ghost of " .. raw.name) end
  made[#made + 1] = g
  local recipe = raw.intent and raw.intent.recipe
  if recipe then
    local set, why = pcall(g.set_recipe, recipe)
    if not set then return rollback(i, "recipe " .. recipe .. ": " .. tostring(why)) end
  end
  placed[#placed + 1] = {i = i, name = raw.name, position = r.position, direction = r.direction, unit_number = g.unit_number}
end

local uncovered = 0
for _, g in ipairs(made) do
  if #a.surface.find_logistic_networks_by_construction_area(g.position, a.force) == 0 then uncovered = uncovered + 1 end
end
return {ok = true, placed = placed, bom = res.bom, summary = string.format("placed %d ghosts; %s", #placed, res.summary),
  warn = uncovered > 0 and string.format("%d of %d ghosts are outside every roboport's construction area: robots will not build them", uncovered, #placed) or nil}
