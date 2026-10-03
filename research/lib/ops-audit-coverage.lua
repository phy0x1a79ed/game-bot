-- ops-audit-coverage.lua (read-only): per enabled player recipe, the machines set to it, how many work, their summed products_finished, and the stock of its item products in chests (human chests excluded) and the part robots can reach.
-- Output: "tick N", then "R|recipe|items|amounts|machines|working|crafts|stocks|status:count of the idle machines|robot-reachable stocks". Run twice and diff crafts for rates.
local surf = game.surfaces[1]
local force = game.forces.player
local W = defines.entity_status.working
local ST = {} for k, v in pairs(defines.entity_status) do ST[v] = k end
local function rname(r)
  if not r then return nil end
  if type(r) == 'string' then return r end
  local ok, n = pcall(function() return r.name end)
  if ok and n then
    if type(n) == 'string' then return n end
    local ok2, n2 = pcall(function() return n.name end)
    if ok2 then return n2 end
  end
  return nil
end
local mac = {}
for _, e in pairs(surf.find_entities_filtered{force = 'player', type = {'assembling-machine', 'furnace', 'rocket-silo'}}) do
  local r
  local ok, rr = pcall(function() return e.get_recipe() end)
  if ok then r = rname(rr) end
  if not r and e.type == 'furnace' then
    local ok2, pr = pcall(function() return e.previous_recipe end)
    if ok2 then r = rname(pr) end
  end
  if r then
    local m = mac[r] or {n = 0, w = 0, c = 0, s = {}}
    m.n = m.n + 1
    if e.status == W then m.w = m.w + 1 elseif e.status then local k = ST[e.status] or '?' m.s[k] = (m.s[k] or 0) + 1 end
    m.c = m.c + (e.products_finished or 0)
    mac[r] = m
  end
end
local stock, netstock = {}, {}
local human = {['24.5,11.5'] = true, ['21.5,-13.5'] = true}
for _, e in pairs(surf.find_entities_filtered{force = 'player', type = {'container', 'logistic-container'}}) do
  local inv = e.get_inventory(defines.inventory.chest)
  if inv and not human[e.position.x .. ',' .. e.position.y] then
    local robots = e.type == 'logistic-container' and e.logistic_network ~= nil
    for _, it in pairs(inv.get_contents()) do
      local n, c = it.name, it.count
      if type(n) ~= 'string' then n = rname(n) end
      if n then
        stock[n] = (stock[n] or 0) + c
        if robots then netstock[n] = (netstock[n] or 0) + c end
      end
    end
  end
end
local out = {'tick ' .. game.tick}
for name, r in pairs(force.recipes) do
  if r.enabled and not r.hidden then
    local items, amts, st, ns = {}, {}, {}, {}
    for _, p in pairs(r.products) do
      if p.type == 'item' then
        items[#items + 1] = p.name
        amts[#amts + 1] = tostring(p.amount or p.amount_max or 1)
        st[#st + 1] = tostring(stock[p.name] or 0)
        ns[#ns + 1] = tostring(netstock[p.name] or 0)
      end
    end
    if #items > 0 then
      local m = mac[name] or {n = 0, w = 0, c = 0, s = {}}
      local ss = {} for k, v in pairs(m.s) do ss[#ss + 1] = k .. ':' .. v end
      out[#out + 1] = table.concat({'R', name, table.concat(items, ','), table.concat(amts, ','), m.n, m.w, m.c, table.concat(st, ','), table.concat(ss, ' '), table.concat(ns, ',')}, '|')
    end
  end
end
rcon.print(table.concat(out, '\n'))
