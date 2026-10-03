-- ne-steel-cell2.lua: infra-b NE steel cell 2 south of Join 2 plates belt y=-73.5 (x58..72): 7 stone furnaces y=-71 (placed by hand), steel belt y=-68.5 west to provider chest (56.5,-68.5), coal belt y=-67.5 from a splitter on coal line x=88.5. Splitter placed by hand.
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{55, -76}, {90, -66}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
for fx = 59, 71, 2 do
  add('fast-inserter', fx - 0.5, -72.5, N)
  add('fast-inserter', fx - 0.5, -69.5, N)
  add('long-handed-inserter', fx + 0.5, -69.5, S)
end
for x = 71.5, 58.5, -1 do add('transport-belt', x, -68.5, W) end
add('fast-inserter', 57.5, -68.5, E); add('passive-provider-chest', 56.5, -68.5)
for x = 75.5, 58.5, -1 do add('transport-belt', x, -67.5, W) end
add('underground-belt', 76.5, -67.5, W, {type = 'output'}); add('underground-belt', 81.5, -67.5, W, {type = 'input'})
for x = 87.5, 82.5, -1 do add('transport-belt', x, -75.5, W) end
for y = -75.5, -68.5 do add('transport-belt', 81.5, y, S) end
for _, x in pairs({59.5, 65.5, 71.5}) do add('medium-electric-pole', x, -72.5) end
add('medium-electric-pole', 57.5, -67.5)
-- RUNNER
