-- coal-home2.lua: infra-b +4 drills, south row y=-60.5 (x199.5..208.5, facing S) onto belt y=-58.5 west to x=194.5, north x=194.5 into band belt (194.5,-66.5) from the south.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{190, -70}, {216, -56}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
for _, x in pairs({199.5, 202.5, 205.5, 208.5}) do add('electric-mining-drill', x, -60.5, S) end
for x = 209.5, 194.5, -1 do add('transport-belt', x, -58.5, W) end
for y = -59.5, -65.5, -1 do add('transport-belt', 194.5, y, N) end
add('medium-electric-pole', 201.5, -57.5); add('medium-electric-pole', 207.5, -57.5)
-- RUNNER
