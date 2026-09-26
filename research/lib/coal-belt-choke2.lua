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
-- known fixes: pole relocation opens (-49,-14); furnace removal opens the chain-1 tap 2x2
open[idx(-49,-14)] = true
for _, t in pairs({{79,-47},{80,-47},{79,-46},{80,-46}}) do open[idx(t[1],t[2])] = true end

local function bfs(sx,sy)
  local seen = {}
  local q = {{sx,sy}}
  seen[idx(sx,sy)] = true
  local qi = 1
  while qi <= #q do
    local cur = q[qi]; qi = qi + 1
    for _, n in pairs({{cur[1]+1,cur[2]},{cur[1]-1,cur[2]},{cur[1],cur[2]+1},{cur[1],cur[2]-1}}) do
      if n[1]>=x0 and n[1]<=x1 and n[2]>=y0 and n[2]<=y1 then
        local ni = idx(n[1],n[2])
        if open[ni] and not seen[ni] then seen[ni]=true; q[#q+1]=n end
      end
    end
  end
  return seen
end

local patch = bfs(79,-47)
local westside = bfs(-58,-21) -- outer+pocket already merged via the pole fix
p('patch size=' .. (function() local n=0 for _ in pairs(patch) do n=n+1 end return n end)())
p('westside size=' .. (function() local n=0 for _ in pairs(westside) do n=n+1 end return n end)())

local chokes = {}
for y = y0, y1 do
  for x = x0, x1 do
    local i = idx(x,y)
    if not open[i] then
      local tp, tw = false, false
      for _, n in pairs({{x+1,y},{x-1,y},{x,y+1},{x,y-1}}) do
        if n[1]>=x0 and n[1]<=x1 and n[2]>=y0 and n[2]<=y1 then
          local ni = idx(n[1],n[2])
          if patch[ni] then tp = true end
          if westside[ni] then tw = true end
        end
      end
      if tp and tw then chokes[#chokes+1] = {x,y} end
    end
  end
end
p('choke tiles between patch and westside: ' .. #chokes)
for _, c in pairs(chokes) do
  local ents = surf.find_entities_filtered{position={c[1]+0.5,c[2]+0.5}, radius=1.0}
  local names = {}
  for _, e in pairs(ents) do names[#names+1] = e.name end
  p(string.format('  choke (%.1f,%.1f): %s', c[1]+0.5, c[2]+0.5, table.concat(names, '/')))
end

rcon.print(table.concat(out, '\n'))
