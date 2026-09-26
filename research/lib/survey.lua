local surface = player.surface
local iron_line = {x=-24, y=-50}

local function cluster(ents, radius)
  -- greedy clustering: group entities within `radius` of each other's centroid
  local clusters = {}
  for _,e in pairs(ents) do
    local placed = false
    for _,c in pairs(clusters) do
      local dx, dy = e.position.x - c.cx, e.position.y - c.cy
      if (dx*dx+dy*dy)^0.5 <= radius then
        table.insert(c.members, e)
        c.cx = (c.cx*(#c.members-1) + e.position.x)/#c.members
        c.cy = (c.cy*(#c.members-1) + e.position.y)/#c.members
        c.minx = math.min(c.minx, e.position.x); c.maxx = math.max(c.maxx, e.position.x)
        c.miny = math.min(c.miny, e.position.y); c.maxy = math.max(c.maxy, e.position.y)
        placed = true
        break
      end
    end
    if not placed then
      table.insert(clusters, {cx=e.position.x, cy=e.position.y, members={e},
        minx=e.position.x, maxx=e.position.x, miny=e.position.y, maxy=e.position.y})
    end
  end
  return clusters
end

-- coal patches
local coal = surface.find_entities_filtered{type="resource", name="coal", position={0,0}, radius=400}
local coal_clusters = cluster(coal, 15)
rcon.print("=== COAL PATCHES ("..#coal_clusters.." clusters, "..#coal.." tiles) ===")
for _,c in pairs(coal_clusters) do
  if #c.members >= 5 then
    local total = 0
    for _,e in pairs(c.members) do total = total + e.amount end
    local d_iron = ((c.cx-iron_line.x)^2+(c.cy-iron_line.y)^2)^0.5
    local d_spawn = (c.cx^2+c.cy^2)^0.5
    -- nearest enemy to this cluster
    local enemies = surface.find_entities_filtered{position={c.cx,c.cy}, radius=60, force="enemy"}
    local neard = 1e9
    for _,en in pairs(enemies) do
      local d = ((en.position.x-c.cx)^2+(en.position.y-c.cy)^2)^0.5
      if d<neard then neard=d end
    end
    rcon.print(string.format("coal centre=(%.0f,%.0f) tiles=%d amount=%d bbox=(%.0f,%.0f)-(%.0f,%.0f) dist_spawn=%.0f dist_ironline=%.0f nearest_enemy=%s",
      c.cx, c.cy, #c.members, total, c.minx, c.miny, c.maxx, c.maxy, d_spawn, d_iron, neard<1e8 and string.format("%.0f",neard) or "none_within_60"))
  end
end

-- unit spawners (nests) within 400
local spawners = surface.find_entities_filtered{type="unit-spawner", position={0,0}, radius=400}
rcon.print("=== SPAWNERS/NESTS ("..#spawners..") ===")
for _,s in pairs(spawners) do
  rcon.print(string.format("%s at (%.0f,%.0f) dist_spawn=%.0f", s.name, s.position.x, s.position.y, (s.position.x^2+s.position.y^2)^0.5))
end

-- good trees (wood:4 yield types), within 400
local good_names = {["tree-09-red"]=true, ["dry-tree"]=true}
local trees = surface.find_entities_filtered{type="tree", position={0,0}, radius=400}
local good_trees = {}
for _,t in pairs(trees) do if good_names[t.name] then table.insert(good_trees, t) end end
local tree_clusters = cluster(good_trees, 20)
rcon.print("=== GOOD TREE CLUSTERS ("..#tree_clusters.." clusters, "..#good_trees.." trees) ===")
for _,c in pairs(tree_clusters) do
  if #c.members >= 5 then
    local d_spawn = (c.cx^2+c.cy^2)^0.5
    local enemies = surface.find_entities_filtered{position={c.cx,c.cy}, radius=60, force="enemy"}
    rcon.print(string.format("trees centre=(%.0f,%.0f) count=%d bbox=(%.0f,%.0f)-(%.0f,%.0f) dist_spawn=%.0f nearby_enemies=%d",
      c.cx, c.cy, #c.members, c.minx, c.miny, c.maxx, c.maxy, d_spawn, #enemies))
  end
end
