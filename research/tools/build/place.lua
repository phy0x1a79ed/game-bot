--- tool: place
--- kind: call
--- effect: act
--- summary: place a build list as ghosts after the whole list passes check; one bad entry places nothing
--- args: list (the check format); surface (default nauvis); force (default player); accept (codes allowed on every entry)
--- returns: {ok, placed = {{i, name, position, direction, unit_number}}, bom, issues = {{i, name, position, code, msg}}, summary, warn} or {error, hint}
--- uses: intent
-- Only entity-ghosts are created, so robots build from stock. With a seat, the ghosts go through its drone's
-- act.ghost, as a player plans them from the map; the drone's force owns them. A ghost the engine refuses after a
-- clean check cancels every ghost this call made.
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

local function ghost(raw, r)
  local recipe = raw.intent and raw.intent.recipe
  if act then
    local done, g = pcall(act.ghost, {name = raw.name, x = r.position[1], y = r.position[2], direction = r.direction,
      type = r.type, recipe = recipe, surface = a.surface.name})
    if not done then return nil, tostring(g) end
    return g.unit_number
  end
  local g = a.surface.create_entity{name = "entity-ghost", inner_name = raw.name, position = r.position,
    direction = r.direction, force = a.force, type = r.type}
  if not g then return nil, "create_entity returned nothing for the ghost of " .. raw.name end
  if recipe then
    local set, why = pcall(g.set_recipe, recipe)
    if not set then g.destroy() return nil, "recipe " .. recipe .. ": " .. tostring(why) end
  end
  return g.unit_number
end

local function cancel(unit)
  if act then return pcall(act.unghost, {unit_number = unit}) end
  local g = game.get_entity_by_unit_number(unit)
  if g and g.valid then g.destroy() end
end

local placed = {}
for i, r in ipairs(res.entries) do
  local ran, unit, why = pcall(ghost, a.list[i], r)
  if not ran or not unit then
    for _, p in ipairs(placed) do cancel(p.unit_number) end
    return {ok = false, placed = {}, summary = "nothing placed: the engine refused entry " .. i,
      issues = {{i = i, name = a.list[i].name, position = r.position, code = "ENGINE_REFUSED", msg = tostring(ran and why or unit):sub(1, 300)}}}
  end
  placed[#placed + 1] = {i = i, name = a.list[i].name, position = r.position, direction = r.direction, unit_number = unit}
end

local uncovered = 0
for _, p in ipairs(placed) do
  if #a.surface.find_logistic_networks_by_construction_area(p.position, a.force) == 0 then uncovered = uncovered + 1 end
end
return {ok = true, placed = placed, bom = res.bom, summary = string.format("placed %d ghosts; %s", #placed, res.summary),
  warn = uncovered > 0 and string.format("%d of %d ghosts are outside every roboport's construction area: robots will not build them", uncovered, #placed) or nil}
