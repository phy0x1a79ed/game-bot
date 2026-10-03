-- ops-audit-defense: READ-ONLY. Turret ammo/fluid/power state grouped by 30-tile cell (gun-turrets with <10 ammo, laser/flame/other turrets in bad status), damaged walls/turrets/gates clustered by cell.
local ST = {} for k,v in pairs(defines.entity_status) do ST[v]=k end
local s = game.surfaces[1]
local function cell(p) return string.format("(%d,%d)", math.floor(p.x/30)*30, math.floor(p.y/30)*30) end
local zero, low, other, dmg = {}, {}, {}, {}
local total, ok_n = 0, 0
local function add(t, e, extra) local c = cell(e.position); local r = t[c]; if not r then r = {n=0, ex=e.position, extra=extra} t[c]=r end r.n = r.n + 1 end
for _, e in pairs(s.find_entities_filtered{force="player", type={"ammo-turret","electric-turret","fluid-turret"}}) do
  total = total + 1
  if e.type == "ammo-turret" then
    local inv = e.get_inventory(defines.inventory.turret_ammo)
    local n = inv and inv.get_item_count() or 0
    if n == 0 then add(zero, e) elseif n < 10 then add(low, e) else ok_n = ok_n + 1 end
  else
    local st = ST[e.status] or "?"
    if st == "working" or st == "waiting_for_target" or st == "normal" then ok_n = ok_n + 1
    elseif st == "no_ammo" or st == "no_power" or st == "low_power" or st == "no_fuel" or st == "fluid_ingredient_shortage" or st == "no_ingredients" then add(other, e, e.name..":"..st) end
  end
  if e.health and e.max_health and e.health < e.max_health * 0.95 then add(dmg, e, "turret") end
end
for _, e in pairs(s.find_entities_filtered{force="player", type={"wall","gate"}}) do
  if e.health and e.max_health and e.health < e.max_health * 0.95 then add(dmg, e, "wall") end
end
local function dump(title, t)
  local l = {} for c, r in pairs(t) do l[#l+1] = {c, r} end
  table.sort(l, function(a,b) return a[2].n > b[2].n end)
  rcon.print(title.." cells="..#l)
  for i, v in ipairs(l) do if i <= 30 then rcon.print(string.format("  %s n=%d ex=(%.0f,%.0f) %s", v[1], v[2].n, v[2].ex.x, v[2].ex.y, v[2].extra or "")) end end
end
rcon.print("TICK "..game.tick.." turrets "..total.." fine "..ok_n)
dump("AMMO ZERO", zero) dump("AMMO <10", low) dump("OTHER TURRET BAD", other) dump("DAMAGED", dmg)
