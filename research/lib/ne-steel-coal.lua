-- ne-steel-coal.lua: infra-b band-coal feed for the NE steel cell: fast inserter (88.5,-67.5) (placed by hand) lifts coal off the band belt y=-66.5, belt x=88.5 north, y=-79.5 west, UG under x=79.5..77.5 into the cell fuel belt (76.5,-79.5).
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{76, -82}, {92, -66}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
for y = -68.5, -78.5, -1 do add('transport-belt', 88.5, y, N) end
for x = 88.5, 81.5, -1 do add('transport-belt', x, -79.5, W) end
add('underground-belt', 80.5, -79.5, W, {type = 'input'}); add('underground-belt', 77.5, -79.5, W, {type = 'output'})
add('medium-electric-pole', 84.5, -77.5); add('medium-electric-pole', 87.5, -72.5); add('medium-electric-pole', 89.5, -69.5)
-- RUNNER
