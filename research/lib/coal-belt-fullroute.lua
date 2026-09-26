local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

local x0, x1 = -65, 81
local y0, y1 = -47, 10
local W = x1-x0+1
local function idx(x,y) return (y-y0)*W + (x-x0) end
local open = {}
for y = y0, y1 do
  for x = x0, x1 do
    open[idx(x,y)] = surf.can_place_entity{name='transport-belt', position={x+0.5,y+0.5}, direction=defines.direction.west, force='player'}
  end
end
-- treat the two identified choke points (poles to be relocated 1 tile) as passable
open[idx(-49,-14)] = true   -- pole @ -48.5,-13.5 (power-block approach)
open[idx(-38,-7)]  = true   -- pole @ -37.5,-6.5 (iron-belt-corner crossing)
-- treat chain-2's own footprint (not yet built) as passable: C2/A2/B2 drill tiles at (77,-42)(77,-40)(77,-38) 2x2 each
for _, d in pairs({{77,-42},{77,-40},{77,-38}}) do
  for dx=0,1 do for dy=0,1 do open[idx(d[1]+dx,d[2]+dy)] = false end end -- drills themselves are NOT belt tiles, keep blocked; route must avoid them (already does, real collision)
end

local start = {79, -47}   -- tile (79.5,-46.5): chain-1 tap point (mine furnace here first)
local goal  = {-46, -9}   -- tile (-45.5,-8.5): last belt tile before the hand-off inserter

if not open[idx(start[1],start[2])] then p('START BLOCKED (expected -- furnace still there; treat as open for planning)') end
-- the whole 2x2 footprint of the furnace @ (80,-46), to be mined and replaced by belt
for _, t in pairs({{79,-47},{80,-47},{79,-46},{80,-46}}) do open[idx(t[1],t[2])] = true end

-- debug waypoints
local wps = {{79,-34,'patch-side y=-33.5 near x=79.5'},{-21,-34,'y=-33.5 near iron col edge'},{-58,-22,'west corridor'},{-46,-9,'goal'},{79,-47,'start'}}
for _, w in pairs(wps) do
  p(string.format('waypoint %s (%d,%d) open=%s', w[3], w[1], w[2], tostring(open[idx(w[1],w[2])])))
end

local prev = {}
local visited = {}
local q = {start}
visited[idx(start[1],start[2])] = true
local qi = 1
local found = false
while qi <= #q do
  local cur = q[qi]; qi = qi + 1
  if cur[1] == goal[1] and cur[2] == goal[2] then found = true; break end
  for _, n in pairs({{cur[1]+1,cur[2]},{cur[1]-1,cur[2]},{cur[1],cur[2]+1},{cur[1],cur[2]-1}}) do
    if n[1] >= x0 and n[1] <= x1 and n[2] >= y0 and n[2] <= y1 then
      local ni = idx(n[1],n[2])
      if open[ni] and not visited[ni] then
        visited[ni] = true; prev[ni] = idx(cur[1],cur[2]); q[#q+1] = n
      end
    end
  end
end

if not found then
  p('NO PATH FOUND')
  -- report the component actually reachable from start
  local minx,maxx,miny,maxy,cnt = 1e9,-1e9,1e9,-1e9,0
  for k in pairs(visited) do
    local cy = math.floor(k / W) + y0
    local cx = (k % W) + x0
    minx=math.min(minx,cx); maxx=math.max(maxx,cx); miny=math.min(miny,cy); maxy=math.max(maxy,cy)
    cnt = cnt + 1
  end
  p(string.format('start-reachable component: size=%d bbox=(%.1f,%.1f)-(%.1f,%.1f)', cnt, minx+0.5, miny+0.5, maxx+0.5, maxy+0.5))
  -- diagnostic grid around the suspected wall
  p('=== diagnostic grid x=-50..-15 y=-10..5 (V=visited/reachable, .=open-not-reached, #=blocked) ===')
  for y = -10, 5 do
    local row = {}
    for x = -50, -15 do
      local i = idx(x,y)
      if visited[i] then row[#row+1]='V' elseif open[i] then row[#row+1]='.' else row[#row+1]='#' end
    end
    p(string.format('y=%4d %s', y, table.concat(row)))
  end
else
  local path = {}
  local cur = idx(goal[1],goal[2])
  local startI = idx(start[1],start[2])
  while cur ~= startI do
    local cy = math.floor(cur / W) + y0
    local cx = (cur % W) + x0
    path[#path+1] = {cx,cy}
    cur = prev[cur]
  end
  path[#path+1] = start
  local n = #path
  for i=1,math.floor(n/2) do path[i], path[n-i+1] = path[n-i+1], path[i] end
  p('FULL PATH LENGTH: ' .. #path .. ' tiles')
  local function dirname(dx,dy)
    if dx==1 then return 'east' elseif dx==-1 then return 'west'
    elseif dy==1 then return 'south' elseif dy==-1 then return 'north' end
    return '?'
  end
  -- compress into straight runs for readability
  local segs = {}
  local i = 1
  while i < #path do
    local dx = path[i+1][1]-path[i][1]
    local dy = path[i+1][2]-path[i][2]
    local runstart = i
    while i < #path and (path[i+1][1]-path[i][1])==dx and (path[i+1][2]-path[i][2])==dy do i = i + 1 end
    segs[#segs+1] = {sx=path[runstart][1]+0.5, sy=path[runstart][2]+0.5, ex=path[i][1]+0.5, ey=path[i][2]+0.5, dir=dirname(dx,dy), len=i-runstart+1}
  end
  for _, s in pairs(segs) do
    p(string.format('SEG dir=%-5s from (%.1f,%.1f) to (%.1f,%.1f) len=%d', s.dir, s.sx, s.sy, s.ex, s.ey, s.len))
  end
end

rcon.print(table.concat(out, '\n'))
