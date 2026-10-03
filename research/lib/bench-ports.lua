local s = game.surfaces.nauvis
local A = {{115, -42}, {158, -10}}
local function inside(p) return p.x >= 115 and p.x <= 158 and p.y >= -42 and p.y <= -10 end
local function lanes(e)
  local t = {}
  for i = 1, 2 do
    local c = e.get_transport_line(i).get_contents()
    local names = {}
    for _, it in pairs(c) do names[#names + 1] = it.name end
    t[i] = (#names > 0) and table.concat(names, "+") or "-"
  end
  return t[1] .. "|" .. t[2]
end
local out = {}
for _, e in pairs(s.find_entities_filtered{area = A, type = {"transport-belt", "underground-belt", "splitter"}}) do
  local n = e.belt_neighbours
  for _, i in pairs(n.inputs) do
    if not inside(i.position) then out[#out + 1] = string.format("IN  %s (%.1f,%.1f) dir %d from (%.1f,%.1f) lanes %s", e.name, e.position.x, e.position.y, e.direction, i.position.x, i.position.y, lanes(e)) end
  end
  for _, o in pairs(n.outputs) do
    if not inside(o.position) then out[#out + 1] = string.format("OUT %s (%.1f,%.1f) dir %d to (%.1f,%.1f) lanes %s", e.name, e.position.x, e.position.y, e.direction, o.position.x, o.position.y, lanes(e)) end
  end
end
-- chests in area (hand/robot-fed inputs?) and inserters reaching outside
for _, e in pairs(s.find_entities_filtered{area = A, type = {"container", "logistic-container"}}) do
  local c = e.get_inventory(defines.inventory.chest).get_contents()
  local names = {}
  for _, it in pairs(c) do names[#names + 1] = it.name .. "=" .. it.count end
  out[#out + 1] = string.format("CHEST %s (%.1f,%.1f) %s", e.name, e.position.x, e.position.y, table.concat(names, ","))
end
local h = {}
for _, e in pairs(s.find_entities_filtered{area = A, force = "player"}) do h[e.name] = (h[e.name] or 0) + 1 end
local t = {}
for k, v in pairs(h) do t[#t + 1] = k .. "=" .. v end
table.sort(t)
out[#out + 1] = "CENSUS " .. table.concat(t, " ")
local rc = {}
for _, e in pairs(s.find_entities_filtered{area = A, type = "assembling-machine"}) do local r = e.get_recipe() local n = r and r.name or "none" rc[n] = (rc[n] or 0) + 1 end
t = {}
for k, v in pairs(rc) do t[#t + 1] = k .. "=" .. v end
out[#out + 1] = "RECIPES " .. table.concat(t, " ")
rcon.print(table.concat(out, "\n"))
