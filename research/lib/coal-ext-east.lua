-- coal-ext-east.lua: infra-b +12 drills on the east coal field: collector belt x=361.5 north to y=-156.5, west to the existing corner (352.5,-156.5).
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{355, -159}, {370, -133}}
local function add(name, x, y, dir) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N} end
for y = -150.5, -135.5, 3 do add('electric-mining-drill', 359.5, y, E); if y ~= -144.5 and y ~= -141.5 and y ~= -135.5 then add('electric-mining-drill', 363.5, y, W) end end
for y = -134.5, -155.5, -1 do add('transport-belt', 361.5, y, N) end
for x = 361.5, 353.5, -1 do add('transport-belt', x, -156.5, W) end
for _, y in pairs({-149, -143, -137}) do add("medium-electric-pole", 357.5, y); add("medium-electric-pole", 366.5, y) end
-- RUNNER
