-- cell3.lua: infra-b NE steel cell 3: 10 steel furnaces y=-84 x57..75; iron from a splitter on Plate Main E x=10.5 (y=-82.5) east along y=-81.5; coal from cell 1's fuel belt end (54.5,-79.5) north/east along y=-87.5; steel belt y=-86.5 east to x=91.5 then south to side-load Q (91.5,-78.5) north lane.
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{9, -90}, {94, -78}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
add('splitter', 11, -82.5, S)
local hop = {[20.5] = 22.5, [23.5] = 26.5, [30.5] = 32.5, [34.5] = 36.5}
local skip = {}
for a, b in pairs(hop) do skip[a] = 'in'; skip[b] = 'out'; for x = a + 1, b - 1 do skip[x] = 'gap' end end
for x = 11.5, 75.5 do
  if skip[x] == 'in' then ug(x, -81.5, E, 'input') elseif skip[x] == 'out' then ug(x, -81.5, E, 'output') elseif not skip[x] then add('transport-belt', x, -81.5, E) end
end
for fx = 57, 75, 2 do
  add('steel-furnace', fx, -84)
  add('fast-inserter', fx - 0.5, -82.5, S); add('fast-inserter', fx - 0.5, -85.5, S); add('long-handed-inserter', fx + 0.5, -85.5, N)
end
for _, x in pairs({57.5, 63.5, 69.5, 75.5}) do add('medium-electric-pole', x, -82.5) end
for x = 56.5, 90.5 do add('transport-belt', x, -86.5, E) end
for y = -86.5, -79.5 do add('transport-belt', 91.5, y, S) end
ug(54.5, -80.5, N, 'input'); ug(54.5, -82.5, N, 'output')
for y = -83.5, -86.5, -1 do add('transport-belt', 54.5, y, N) end
for x = 54.5, 75.5 do add('transport-belt', x, -87.5, E) end
-- RUNNER
