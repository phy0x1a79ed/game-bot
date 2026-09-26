local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

local x0, x1 = -65, 10
local y0, y1 = -40, 10
local W = x1-x0+1
local function idx(x,y) return (y-y0)*W + (x-x0) end
local open = {}
for y = y0, y1 do
  for x = x0, x1 do
    open[idx(x,y)] = surf.can_place_entity{name='transport-belt', position={x+0.5,y+0.5}, direction=defines.direction.west, force='player'}
  end
end

local function bfs(startx, starty)
  local seen = {}
  local q = {{startx,starty}}
  seen[idx(startx,starty)] = true
  local qi = 1
  while qi <= #q do
    local cur = q[qi]; qi = qi + 1
    local cx, cy = cur[1], cur[2]
    for _, n in pairs({{cx+1,cy},{cx-1,cy},{cx,cy+1},{cx,cy-1}}) do
      local nx, ny = n[1], n[2]
      if nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1 then
        local ni = idx(nx,ny)
        if open[ni] and not seen[ni] then seen[ni] = true; q[#q+1] = {nx,ny} end
      end
    end
  end
  return seen
end

local outer = bfs(-58, -21)
local pocket = bfs(-47, -9)
p('outer size=' .. (function() local n=0 for _ in pairs(outer) do n=n+1 end return n end)())
p('pocket size=' .. (function() local n=0 for _ in pairs(pocket) do n=n+1 end return n end)())

-- find blocked tiles touching both sets
local chokes = {}
for y = y0, y1 do
  for x = x0, x1 do
    local i = idx(x,y)
    if not open[i] then
      local touchesOuter, touchesPocket = false, false
      for _, n in pairs({{x+1,y},{x-1,y},{x,y+1},{x,y-1}}) do
        local nx, ny = n[1], n[2]
        if nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1 then
          local ni = idx(nx,ny)
          if outer[ni] then touchesOuter = true end
          if pocket[ni] then touchesPocket = true end
        end
      end
      if touchesOuter and touchesPocket then chokes[#chokes+1] = {x,y} end
    end
  end
end
p('choke tiles (blocked, adjacent to BOTH outer and pocket): ' .. #chokes)
for _, c in pairs(chokes) do
  local ents = surf.find_entities_filtered{position={c[1]+0.5,c[2]+0.5}, radius=0.9}
  local names = {}
  for _, e in pairs(ents) do names[#names+1] = e.name .. '@' .. string.format('%.1f,%.1f',e.position.x,e.position.y) end
  p(string.format('  choke tile (%.1f,%.1f): %s', c[1]+0.5, c[2]+0.5, table.concat(names, ' / ')))
end

rcon.print(table.concat(out, '\n'))
