local b = game.surfaces.bench
local red, green, st = 0, 0, {}
local inv = {}
for k, v in pairs(defines.entity_status) do inv[v] = k end
for _, e in pairs(b.find_entities_filtered{type = "assembling-machine"}) do
  local r = e.get_recipe()
  local n = r and r.name or "none"
  if n == "automation-science-pack" then red = red + e.products_finished end
  if n == "logistic-science-pack" then green = green + e.products_finished end
  local k = n .. ":" .. (inv[e.status] or "?")
  st[k] = (st[k] or 0) + 1
end
local t = {}
for k, v in pairs(st) do t[#t + 1] = k .. "=" .. v end
table.sort(t)
rcon.print(game.tick .. " red=" .. red .. " green=" .. green .. " | " .. table.concat(t, " "))
