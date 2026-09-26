local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

-- BFS over a can_place_entity grid to find a real belt path from the coal-patch
-- side of the map into the boiler/feed-chest area, avoiding every collision.
local x0, x1 = -65, 10
local y0, y1 = -40, 10
local W, H = x1-x0+1, y1-y0+1

local function idx(x,y) return (y-y0)*W + (x-x0) end
local open = {}
for y = y0, y1 do
  for x = x0, x1 do
    open[idx(x,y)] = surf.can_place_entity{name='transport-belt', position={x+0.5,y+0.5}, direction=defines.direction.west, force='player'}
  end
end

-- start: anywhere on the wide-open band near x=-58,y=-21 (already confirmed clear, one hop from
-- the long haul from the coal patch which arrives via y=-21.5).
-- goal: (-46.5,-8.5), the open tile immediately EAST of the feed chest (-47.5,-8.5).
local sx, sy = -58, -21
local gx, gy = -47, -9

-- open the one identified choke point (small-electric-pole @ -48.5,-13.5 relocated 1 tile)
-- grid cell whose tile-centre is (-48.5,-13.5): x+0.5=-48.5,y+0.5=-13.5 -> x=-49,y=-14
open[idx(-49,-14)] = true

if not open[idx(sx,sy)] then p('START BLOCKED') end
if not open[idx(gx,gy)] then p('GOAL BLOCKED') end
-- debug: neighbours of goal
for _, d in pairs({{0,-1,'N'},{0,1,'S'},{1,0,'E'},{-1,0,'W'}}) do
  local nx, ny = gx+d[1], gy+d[2]
  p('goal-neighbour ' .. d[3] .. ' (' .. nx .. ',' .. ny .. ') open=' .. tostring(open[idx(nx,ny)]))
end

local prev = {}
local visited = {}
local q = {{sx,sy}}
visited[idx(sx,sy)] = true
local qi = 1
local found = false
while qi <= #q do
  local cur = q[qi]; qi = qi + 1
  local cx, cy = cur[1], cur[2]
  if cx == gx and cy == gy then found = true; break end
  local neigh = {{cx+1,cy},{cx-1,cy},{cx,cy+1},{cx,cy-1}}
  for _, n in pairs(neigh) do
    local nx, ny = n[1], n[2]
    if nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1 then
      local ni = idx(nx,ny)
      if open[ni] and not visited[ni] then
        visited[ni] = true
        prev[ni] = idx(cx,cy)
        q[#q+1] = {nx,ny}
      end
    end
  end
end

if not found then
  p('NO PATH FOUND from (' .. sx .. ',' .. sy .. ') to (' .. gx .. ',' .. gy .. ') within scanned box')
else
  -- reconstruct
  local path = {}
  local cur = idx(gx,gy)
  local startI = idx(sx,sy)
  while cur ~= startI do
    local cy = math.floor(cur / W) + y0
    local cx = (cur % W) + x0
    path[#path+1] = {cx,cy}
    cur = prev[cur]
  end
  path[#path+1] = {sx,sy}
  -- reverse
  local n = #path
  for i=1,math.floor(n/2) do path[i], path[n-i+1] = path[n-i+1], path[i] end
  p('PATH LENGTH: ' .. #path .. ' tiles')
  -- compress into straight segments + direction (direction = travel direction from this tile to next)
  local function dirname(dx,dy)
    if dx==1 then return 'E' elseif dx==-1 then return 'W'
    elseif dy==1 then return 'S' elseif dy==-1 then return 'N' end
    return '?'
  end
  for i=1,#path-1 do
    local dx = path[i+1][1]-path[i][1]
    local dy = path[i+1][2]-path[i][2]
    p(string.format('%d: tile(%.1f,%.1f) -> %s', i, path[i][1]+0.5, path[i][2]+0.5, dirname(dx,dy)))
  end
  p(string.format('%d: tile(%.1f,%.1f) [END]', #path, path[#path][1]+0.5, path[#path][2]+0.5))
end

rcon.print(table.concat(out, '\n'))
