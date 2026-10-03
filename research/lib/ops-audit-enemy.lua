-- ops-audit-enemy: READ-ONLY. Enemy units/worms/spawners clustered on 10-tile cells; for each cluster with a player structure (non-wall, non-rail) within 40 tiles, counts loaded gun-turrets within 18 and fueled flame turrets within 30 of the nearest such structure. Lines flagged GAP = no loaded turret reaches the cluster's nearest structure.
local s = game.surfaces[1]
local en = s.find_entities_filtered{force="enemy", type={"unit","unit-spawner","turret"}}
local cells = {}
for _, e in pairs(en) do
  local k = math.floor(e.position.x/10)..","..math.floor(e.position.y/10)
  local c = cells[k]; if not c then c = {n=0, units=0, nests=0, worms=0, x=e.position.x, y=e.position.y}; cells[k] = c end
  c.n = c.n + 1
  if e.type == "unit" then c.units = c.units + 1 elseif e.type == "unit-spawner" then c.nests = c.nests + 1 else c.worms = c.worms + 1 end
end
local STRUCT = {"assembling-machine","furnace","mining-drill","lab","inserter","electric-pole","roboport","pumpjack","boiler","generator","storage-tank","container","logistic-container","radar","offshore-pump","pump","ammo-turret","electric-turret","fluid-turret","transport-belt","pipe","pipe-to-ground","underground-belt","splitter","locomotive","car"}
local out, tot, near = {}, 0, 0
for k, c in pairs(cells) do
  tot = tot + 1
  local st = s.find_entities_filtered{position={c.x,c.y}, radius=40, force="player", type=STRUCT, limit=40}
  if #st > 0 then
    near = near + 1
    local best, bd = nil, 1e9
    for _, e in pairs(st) do local d = (e.position.x-c.x)^2 + (e.position.y-c.y)^2; if d < bd then bd = d; best = e end end
    local ts = s.find_entities_filtered{position={c.x,c.y}, radius=60, force="player", type={"ammo-turret","fluid-turret","electric-turret"}}
    local loaded = 0
    for _, t in pairs(ts) do
      local r = (t.type == "ammo-turret") and 18 or 30
      local d = math.sqrt((t.position.x-c.x)^2 + (t.position.y-c.y)^2)
      if d <= r + 2 then
        if t.type == "ammo-turret" then local inv = t.get_inventory(defines.inventory.turret_ammo); if inv and not inv.is_empty() then loaded = loaded + 1 end
        elseif t.type == "fluid-turret" then local ok, f = pcall(function() return t.get_fluid_count() end); if ok and f and f > 0 then loaded = loaded + 1 end
        else loaded = loaded + 1 end
      end
    end
    out[#out+1] = string.format("%s|(%.0f,%.0f)|units=%d nests=%d worms=%d|nearest=%s(%.1f,%.1f) d=%.0f|loaded_in_reach=%d", loaded == 0 and "GAP" or "ok", c.x, c.y, c.units, c.nests, c.worms, best.name, best.position.x, best.position.y, math.sqrt(bd), loaded)
  end
end
table.sort(out)
rcon.print("TICK "..game.tick.." enemy_cells "..tot.." near_structure "..near)
rcon.print(table.concat(out, "\n"))
