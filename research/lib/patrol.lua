-- patrol.lua -- read-only defense sweep, one exec_lua call.
-- Prints every gun-turret's ammo (flagging <15), enemy units within 200 of
-- (0,-20) clustered by 20-tile grid cell, and any enemy group within 60
-- tiles of a known polluting site.
local surf = game.surfaces["nauvis"]
local out = {}
local function p(s) out[#out+1] = s end

-- turrets
local low = {}
local all = {}
for _, e in pairs(surf.find_entities_filtered{force="player", name="gun-turret"}) do
  local ammo = e.get_inventory(defines.inventory.turret_ammo).get_item_count()
  local tag = string.format("(%.0f,%.0f):%d", e.position.x, e.position.y, ammo)
  table.insert(all, tag)
  if ammo < 15 then table.insert(low, tag) end
end
p("turrets(" .. #all .. "): " .. table.concat(all, " "))
p("LOW AMMO (<15): " .. (#low > 0 and table.concat(low, " ") or "none"))

-- enemies within 200 of spawn, clustered
local units = surf.find_entities_filtered{force="enemy", type="unit", position={0,-20}, radius=200}
local groups = {}
for _, e in pairs(units) do
  local k = math.floor(e.position.x/20)*20 .. "," .. math.floor(e.position.y/20)*20
  groups[k] = (groups[k] or 0) + 1
end
local g = {}
for k, v in pairs(groups) do g[#g+1] = k .. "x" .. v end
p("enemies<200 of spawn (" .. #units .. "): " .. (#g > 0 and table.concat(g, " ") or "none"))

-- known polluting sites -- enemy within 60
local sites = {
  {name="power-block/lab", x=-44, y=-18},
  {name="stone-drill", x=60, y=-30},
  {name="coal-ring", x=70, y=-47},
  {name="copper-module1", x=21, y=50},
  {name="copper-module2", x=21, y=57},
  {name="iron-column", x=-22, y=-50},
  {name="spawn/depot", x=0, y=-20},
}
local alerts = {}
for _, s in pairs(sites) do
  local n = surf.find_entities_filtered{force="enemy", type="unit", position={s.x, s.y}, radius=60}
  if #n > 0 then table.insert(alerts, s.name .. "@(" .. s.x .. "," .. s.y .. "):" .. #n) end
end
p("SITE ALERTS (enemy<60): " .. (#alerts > 0 and table.concat(alerts, " ") or "none"))

p("evolution=" .. string.format("%.3f", game.forces.enemy.get_evolution_factor(surf)))
p("tick=" .. game.tick)

rcon.print(table.concat(out, "\n"))
