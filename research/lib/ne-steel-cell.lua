-- ne-steel-cell.lua: infra-b NE steel cell on Join 2 plates belt y=-73.5 (x54..76): 11 furnaces y=-76, coal belt y=-79.5, steel belt y=-78.5 west into a passive provider chest (52.5,-78.5) in net 5. Furnaces are placed by hand, not ghosted.
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{50, -82}, {80, -73}}
local function add(name, x, y, dir) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N} end
for i = 0, 10 do
  local fx = 55 + 2 * i
  add('fast-inserter', fx - 0.5, -74.5, S)
  add('fast-inserter', fx - 0.5, -77.5, S)
  add('long-handed-inserter', fx + 0.5, -77.5, N)
end
for x = 76.5, 54.5, -1 do add('transport-belt', x, -79.5, W) end
for x = 76.5, 54.5, -1 do add('transport-belt', x, -78.5, W) end
add('fast-inserter', 77.5, -79.5, E)
add('fast-inserter', 53.5, -78.5, E)
add('passive-provider-chest', 52.5, -78.5)
for _, x in pairs({55.5, 61.5, 67.5, 73.5}) do add('medium-electric-pole', x, -74.5) end
add('medium-electric-pole', 77.5, -77.5); add('medium-electric-pole', 53.5, -76.5); add('medium-electric-pole', 51.5, -77.5)
-- RUNNER
