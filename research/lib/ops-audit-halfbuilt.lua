-- ops-audit-halfbuilt: READ-ONLY. Inserters with no entity at pickup or drop (dropping to ground), assemblers with no recipe, chests full, item-entity (ground items) clusters. Grouped by 30-tile cell.
local s = game.surfaces[1]
local function cell(x,y) return string.format("(%d,%d)", math.floor(x/30)*30, math.floor(y/30)*30) end
local function has(pos)
  local r = s.find_entities_filtered{position=pos, radius=0.3}
  for _, e in pairs(r) do
    if e.type ~= "item-entity" and e.type ~= "entity-ghost" and e.type ~= "resource" and e.type ~= "corpse" and e.type ~= "tree" and e.type~="cliff" and e.type~="fish" then return e end
  end
  return nil
end
local nodrop, nopick, norecipe, ground, fullch = {}, {}, {}, {}, {}
local function add(t, x, y, ex) local c = cell(x,y); local r = t[c]; if not r then r = {n=0, x=x, y=y, ex=ex} t[c] = r end r.n = r.n + 1 end
local ins = s.find_entities_filtered{force="player", type="inserter"}
for _, i in pairs(ins) do
  local d = i.drop_target
  if not d then
    local belt = s.find_entities_filtered{position=i.drop_position, radius=0.3, type={"transport-belt","underground-belt","splitter","loader","loader-1x1","linked-belt"}}
    if #belt == 0 then add(nodrop, i.position.x, i.position.y, i.name) end
  end
  if not i.pickup_target then
    local belt = s.find_entities_filtered{position=i.pickup_position, radius=0.3, type={"transport-belt","underground-belt","splitter","loader","loader-1x1","linked-belt"}}
    if #belt == 0 then add(nopick, i.position.x, i.position.y, i.name) end
  end
end
for _, a in pairs(s.find_entities_filtered{force="player", type="assembling-machine"}) do
  if not a.get_recipe() then add(norecipe, a.position.x, a.position.y, a.name) end
end
for _, c in pairs(s.find_entities_filtered{force="player", type="container"}) do
  local inv = c.get_inventory(defines.inventory.chest)
  if inv and inv.is_full() then add(fullch, c.position.x, c.position.y, c.name) end
end
local ie = s.find_entities_filtered{type="item-entity"}
local gtot = 0
for _, e in pairs(ie) do
  if math.abs(e.position.x) < 300 and math.abs(e.position.y) < 400 then gtot = gtot + 1; add(ground, e.position.x, e.position.y, e.stack.name) end
end
local function dump(title, t)
  local l = {} for c, r in pairs(t) do l[#l+1] = {c, r} end
  table.sort(l, function(a,b) return a[2].n > b[2].n end)
  rcon.print(title.." cells="..#l)
  for i, v in ipairs(l) do if i <= 25 then rcon.print(string.format("  %s n=%d ex=(%.1f,%.1f) %s", v[1], v[2].n, v[2].x, v[2].y, v[2].ex or "")) end end
end
rcon.print("TICK "..game.tick.." inserters "..#ins.." ground-items "..gtot)
dump("INSERTER NO DROP", nodrop) dump("INSERTER NO PICKUP", nopick) dump("AM NO RECIPE", norecipe) dump("CHEST FULL", fullch) dump("GROUND ITEMS", ground)
