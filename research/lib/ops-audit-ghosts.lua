-- ops-audit-ghosts: READ-ONLY. Counts entity/tile ghosts by 30-tile cell and ghost_name; for each ghost name checks the construction network covering the ghost (logistic cells with construction radius) and the item stock (get_item_count of the first item that places it). Reports ghosts outside any construction network, or whose item count is 0, and available_construction_robots per network.
local s = game.surfaces[1]
local f = game.forces.player
local function cell(p) return string.format("(%d,%d)", math.floor(p.x/30)*30, math.floor(p.y/30)*30) end
local ghosts = s.find_entities_filtered{force="player", type={"entity-ghost","tile-ghost"}}
local byname, bycell, nets = {}, {}, {}
local ntot = 0
for _, g in pairs(ghosts) do
  ntot = ntot + 1
  local nm = g.ghost_name
  local item
  local ok, r = pcall(function() return g.ghost_prototype.items_to_place_this end)
  if ok and r and r[1] then item = r[1].name or r[1][1] end
  local rec = byname[nm]
  if not rec then rec = {n=0, item=item or nm, innet=0, out=0, ex=nil, outex=nil, type=g.type} byname[nm]=rec end
  rec.n = rec.n + 1
  local q = g.position
  rec.x1 = math.min(rec.x1 or q.x, q.x); rec.y1 = math.min(rec.y1 or q.y, q.y); rec.x2 = math.max(rec.x2 or q.x, q.x); rec.y2 = math.max(rec.y2 or q.y, q.y)
  rec.ex = rec.ex or g.position
  local nl = s.find_logistic_networks_by_construction_area(g.position, f)
  local net = nl and nl[1] or nil
  if net then
    rec.innet = rec.innet + 1
    nets[net.network_id] = nets[net.network_id] or net
    rec.netid = net.network_id
  else rec.out = rec.out + 1; rec.outex = rec.outex or g.position end
  local c = cell(g.position); bycell[c] = (bycell[c] or 0) + 1
end
rcon.print("TICK "..game.tick.." ghosts "..ntot)
local cl = {} for c, n in pairs(bycell) do cl[#cl+1] = {c, n} end
table.sort(cl, function(a,b) return a[2] > b[2] end)
local l = {} for i, v in ipairs(cl) do if i <= 25 then l[#l+1] = v[1]..":"..v[2] end end
rcon.print("cells(30t): "..table.concat(l, " "))
for nm, r in pairs(byname) do
  local stock = "n/a"
  local net = nil
  if r.netid and nets[r.netid] then
    local ok, v = pcall(function() return nets[r.netid].get_item_count(r.item) end)
    if ok then stock = v end
  end
  rcon.print(string.format("%s %s n=%d innet=%d outnet=%d item=%s stock=%s bbox=(%.0f,%.0f)-(%.0f,%.0f)%s", r.type=="tile-ghost" and "T" or "E", nm, r.n, r.innet, r.out, r.item, tostring(stock), r.x1, r.y1, r.x2, r.y2, r.outex and string.format(" outex=(%.0f,%.0f)", r.outex.x, r.outex.y) or ""))
end
for id, n in pairs(nets) do
  rcon.print(string.format("net %d construction_robots avail=%d all=%d logistic avail=%d cells=%d storages=%d", id, n.available_construction_robots, n.all_construction_robots, n.available_logistic_robots, #n.cells, #n.storage_points))
end
