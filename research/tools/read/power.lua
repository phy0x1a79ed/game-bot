--- tool: power
--- kind: call
--- effect: read
--- summary: electric networks that touch an area: production, demand, satisfaction, accumulator charge, and the fuel left in boilers
--- args: x0, y0, x1, y1 (numbers); limit (networks, default 200, max 300), offset; surface, force (default player)
--- returns: {networks = {{id, produced_kw, demand_kw, capacity_kw, satisfaction, accumulators = {charge, energy_mj, capacity_mj}, poles, generators = {name = n}, no_power, low_power}, ...}, unconnected = {n, examples = {{name, x, y}, ...}}, boilers = {n, working, status = {status = n}, fuel = {item = n}, fuel_mj, minutes_left, empty = {{x, y}, ...}}, total, more, next}; produced_kw is what was delivered last tick, capacity_kw what the producers could offer, satisfaction 0 to 1; no_power and low_power count machines (assemblers, furnaces, labs, drills, roboports, radars, pumps, beacons, turrets, lamps) in the area that sit on the network, unconnected those with no network at all; {error, hint} on bad args
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {area = true, paged = true})
if not c then return err end

local nets, order = {}, {}
local function net_of(e)
  local id = e.electric_network_id
  if not id then return nil end
  local n = nets[id]
  if not n then
    n = {id = id, poles = 0, generators = {}, no_power = 0, low_power = 0, sample = e}
    nets[id] = n
    order[#order + 1] = n
  end
  return n
end

local boilers, loose = {}, {n = 0, examples = {}}
local structure, cut = rd.find(c, {types = {"electric-pole", "generator", "solar-panel", "accumulator"}, ghosts = false,
  unsorted = true})
if not structure then return cut end
for _, e in ipairs(structure) do
  local n = net_of(e)
  if n and e.type == "electric-pole" then n.poles = n.poles + 1 end
  if n and e.type ~= "electric-pole" then n.generators[e.name] = (n.generators[e.name] or 0) + 1 end
end

-- machines short of power: on a network they count there, and off every network they are listed as unconnected
local consumers
consumers, cut = rd.find(c, {types = {"assembling-machine", "furnace", "lab", "mining-drill", "roboport",
  "radar", "pump", "beacon", "electric-turret", "lamp", "rocket-silo", "agricultural-tower"}, ghosts = false, unsorted = true})
if not consumers then return cut end
for _, e in ipairs(consumers) do
  local st = rd.status(e)
  local n = (st == "no_power" or st == "low_power") and net_of(e)
  if n then
    if st == "no_power" then n.no_power = n.no_power + 1 else n.low_power = n.low_power + 1 end
  elseif st == "no_power" and e.electric_network_id == nil then
    loose.n = loose.n + 1
    if #loose.examples < 10 then
      loose.examples[#loose.examples + 1] = {name = e.name, x = rd.r2(e.position.x), y = rd.r2(e.position.y)}
    end
  end
end

for _, e in ipairs(rd.find(c, {types = {"boiler"}, ghosts = false, unsorted = true}) or {}) do
  if e.burner then boilers[#boilers + 1] = e end
end

table.sort(order, function(p, q) return p.id < q.id end)
for _, n in ipairs(order) do
  local f = n.sample.electric_network.parent_network.flow_last_tick
  n.produced_kw = rd.r2(f.total_transfer * 60 / 1000)
  n.demand_kw = rd.r2(f.maximum_consumption * 60 / 1000)
  n.capacity_kw = rd.r2(f.maximum_production * 60 / 1000)
  n.satisfaction = rd.r2(f.consumption_satisfaction)
  if f.accumulator_capacity > 0 then
    n.accumulators = {charge = rd.r2(f.accumulator_energy / f.accumulator_capacity),
      energy_mj = rd.r2(f.accumulator_energy / 1e6), capacity_mj = rd.r2(f.accumulator_capacity / 1e6)}
  end
  n.sample = nil
  if not next(n.generators) then n.generators = nil end
  if n.no_power == 0 then n.no_power = nil end
  if n.low_power == 0 then n.low_power = nil end
end

local res = rd.page({}, "networks", order, c)

if loose.n > 0 then res.unconnected = loose end

if #boilers > 0 then
  local b = {n = #boilers, working = 0, status = {}, fuel = {}, empty = {}}
  local joules, burn = 0, 0
  for _, e in ipairs(boilers) do
    local st = rd.status(e) or "unknown"
    b.status[st] = (b.status[st] or 0) + 1
    if st == "working" then
      b.working = b.working + 1
      burn = burn + e.prototype.get_max_energy_usage(e.quality) * 60
    end
    local inv = e.get_fuel_inventory()
    local items = rd.merge({}, inv)
    rd.add(b.fuel, items)
    local mine = e.burner.remaining_burning_fuel
    for item, count in pairs(items) do mine = mine + count * prototypes.item[item].fuel_value end
    joules = joules + mine
    if mine == 0 and #b.empty < 20 then b.empty[#b.empty + 1] = {rd.r2(e.position.x), rd.r2(e.position.y)} end
  end
  b.fuel_mj = rd.r2(joules / 1e6)
  if burn > 0 then b.minutes_left = rd.r2(joules / burn / 60) end
  if #b.empty == 0 then b.empty = nil end
  res.boilers = b
end
return res
