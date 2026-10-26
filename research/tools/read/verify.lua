--- tool: verify
--- kind: call
--- effect: read
--- summary: what the engine says about built entities in an area after a build: inserter pick and drop targets, belt and underground neighbours, fluid segments, power network and status; lists only what needs a look unless all = true
--- args: x0, y0, x1, y1 (an area) or x, y with r (a point); name, type (string or list; default: inserters, belts, machines, drills, labs, fluid entities); all (bool: list entities with nothing to report too); limit (default 200, max 300), offset; surface, force
--- returns: {entities = {{name, x, y, dir, recipe, status, issues = {CODE}, pick = {name, x, y, pending}, drop, belt = {inputs, outputs, pair = {x, y}}, fluids = {{fluid, segment, linked, open}}, network}, ...}, counts = {CODE = n}, checked, ghosts, total, more, next}; codes: PICKS_NOTHING, DROPS_ON_GROUND, UNDERGROUND_UNPAIRED, NO_NETWORK; pending = true marks a target the engine resolves on the inserter's next swing; ghosts counts entities still to be built in the area; {error, hint} on bad args
--- uses: core, rd
local C, rd = use("core"), use("rd")
local a = ...
local c, err = rd.ctx(a, {either = true, paged = true, extra = {"name", "type", "all"}})
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
  filter.types = {"inserter", "transport-belt", "underground-belt", "splitter", "loader", "loader-1x1",
    "assembling-machine", "furnace", "mining-drill", "lab", "pipe", "pipe-to-ground", "pump", "storage-tank",
    "boiler", "generator", "offshore-pump", "roboport", "radar", "beacon", "electric-turret", "rocket-silo"}
end
filter.hint = "narrow the area, or add name or type"
local found, cut = rd.find(c, filter)
if not found then return cut end

local FINE = {working = true, normal = true}

-- the inserter's target at p: the engine's own once resolved, else whatever stands there, marked pending
local function target(engine, p)
  local t, pending = engine, nil
  if not t then
    t = C.entities_at(c.s, p)[1]
    pending = t and true or nil
  end
  if not t then return nil end
  local q = t.position
  return {name = C.name_of(t), x = C.r2(q.x), y = C.r2(q.y), pending = pending, ghost = t.type == "entity-ghost" or nil}
end

local function fluids(e)
  local out = {}
  for i = 1, e.fluids_count do
    local f = {segment = e.has_fluid_segment(i) and e.get_fluid_segment_id(i) or nil, linked = 0, open = 0}
    local fl = e.get_fluid(i)
    f.fluid = fl and fl.name
    local ok, conns = pcall(function() return e.get_fluid_box_pipe_connections(i) end)
    for _, pc in pairs(ok and conns or {}) do
      if pc.target then f.linked = f.linked + 1 else f.open = f.open + 1 end
    end
    out[#out + 1] = f
  end
  return #out > 0 and out or nil
end

local function look(e)
  local r = rd.record(e)
  local issues = {}
  local t = e.type
  if t == "inserter" then
    r.pickup, r.drop = nil, nil
    r.pick = target(e.pickup_target, e.pickup_position)
    r.drop = target(e.drop_target, e.drop_position)
    if not r.pick then issues[#issues + 1] = "PICKS_NOTHING" end
    if not r.drop then issues[#issues + 1] = "DROPS_ON_GROUND" end
  elseif C.BELT_TYPES[t] then
    local nb = e.belt_neighbours
    r.belt = {inputs = #nb.inputs, outputs = #nb.outputs}
    if t == "underground-belt" then
      local pair = e.underground_belt_neighbour
      if pair then r.belt.pair = C.xy(pair.position) else issues[#issues + 1] = "UNDERGROUND_UNPAIRED" end
    end
  end
  r.fluids = fluids(e)
  if rd.STATUS_TYPES[t] then
    local ok, id = pcall(function() return e.electric_network_id end)
    id = ok and id or nil
    r.network = id
    if r.status == "no_power" and not id then issues[#issues + 1] = "NO_NETWORK" end
  end
  if #issues > 0 then r.issues = issues end
  return r, #issues > 0 or (r.status ~= nil and not FINE[r.status])
end

local rows, counts = {}, {}
for _, e in ipairs(found) do
  local r, notable = look(e)
  for _, code in ipairs(r.issues or {}) do counts[code] = (counts[code] or 0) + 1 end
  if notable or a.all then rows[#rows + 1] = r end
end
local res = rd.page({}, "entities", rows, c)
res.counts, res.checked = counts, #found
local ghosts = c.s.count_entities_filtered{area = c.area, name = "entity-ghost", force = c.force}
if ghosts > 0 then res.ghosts = ghosts end
return res
