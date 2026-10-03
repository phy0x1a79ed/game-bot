-- ops-audit-outposts: READ-ONLY. Clusters player machines (drills, assemblers, furnaces, labs, roboports, radars, pumpjacks, refineries, chemical plants) on 40-tile cells and lists the cells with 3+ machines and no ammo/flame turret within 40 tiles of the cell's mean position. Output: "cell n machines mean=(x,y) nearest_turret=d".
local s = game.surfaces[1]
local cells = {}
for _, e in pairs(s.find_entities_filtered{force="player", type={"mining-drill","assembling-machine","furnace","lab","roboport","radar","oil-refinery","chemical-plant"}}) do
  local k = math.floor(e.position.x/40)..","..math.floor(e.position.y/40)
  local c = cells[k] or {n=0,x=0,y=0}
  c.n=c.n+1; c.x=c.x+e.position.x; c.y=c.y+e.position.y; cells[k]=c
end
local tur = s.find_entities_filtered{force="player", type={"ammo-turret","electric-turret","fluid-turret"}}
rcon.print("TICK "..game.tick.." turrets "..#tur)
local out = {}
for k, c in pairs(cells) do
  if c.n >= 3 then
    local mx, my = c.x/c.n, c.y/c.n
    local best = 1e9
    for _, t in pairs(tur) do
      local d = math.sqrt((t.position.x-mx)^2+(t.position.y-my)^2)
      if d < best then best = d end
    end
    if best > 40 then out[#out+1] = string.format("cell %s n=%d mean=(%.0f,%.0f) nearest_turret=%.0f", k, c.n, mx, my, best) end
  end
end
table.sort(out)
rcon.print(table.concat(out, "\n"))
