--- tool: network
--- kind: call
--- effect: read
--- summary: the logistic network that covers a point (or its construction area): robots, idle robots, roboports, stored items; the nearest roboport when none covers it
--- args: x, y (a point); limit (items listed, default 50, max 300), offset; surface, force (default player)
--- returns: {covered = true, covers = "logistic" | "construction", id, roboports, construction_robots, construction_idle, logistic_robots, logistic_idle, storages, requesters, providers, items = {name = n}, total, more, next} or {covered = false, nearest = {x, y, distance, logistic_radius, construction_radius, id}}; items are the biggest stacks first; {error, hint} on bad args
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {point = true, paged = true, limit = 50})
if not c then return err end

local p = {c.x, c.y}
local net, covers = c.s.find_logistic_network_by_position(p, c.force), "logistic"
if not net then
  net, covers = c.s.find_logistic_networks_by_construction_area(p, c.force)[1], "construction"
end

if not net then
  local ports = c.s.find_entities_filtered{type = "roboport", force = c.force}
  local near = c.s.get_closest(p, ports)
  if not near then return {covered = false} end
  local q = near.position
  return {covered = false, nearest = {x = rd.r2(q.x), y = rd.r2(q.y),
    distance = rd.r2(math.sqrt((q.x - c.x) ^ 2 + (q.y - c.y) ^ 2)),
    logistic_radius = near.prototype.logistic_radius, construction_radius = near.prototype.construction_radius,
    id = near.logistic_network and near.logistic_network.network_id}}
end

local stock = {}
for _, it in pairs(net.get_contents()) do stock[it.name] = (stock[it.name] or 0) + it.count end
local rows = {}
for name, count in pairs(stock) do rows[#rows + 1] = {name = name, count = count} end
table.sort(rows, function(x, y)
  if x.count ~= y.count then return x.count > y.count end
  return x.name < y.name
end)
local res = rd.page({}, "items", rows, c)
local items = {}
for _, row in ipairs(res.items) do items[row.name] = row.count end
res.items = items

res.covered, res.covers, res.id = true, covers, net.network_id
res.roboports = #net.cells
res.construction_robots, res.construction_idle = net.all_construction_robots, net.available_construction_robots
res.logistic_robots, res.logistic_idle = net.all_logistic_robots, net.available_logistic_robots
res.storages, res.requesters, res.providers = #net.storages, #net.requesters, #net.providers
return res
