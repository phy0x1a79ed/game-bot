-- coal-home.lua: infra-b +9 drills on the home coal field: north row y=-73.5 (5 drills, x199.5..211.5) onto belt y=-71.5 west, down x=195.5 into the head of band belt y=-66.5 (straight), south row y=-60.5 (4 drills) onto belt y=-62.5?? (see check).
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{190, -80}, {216, -56}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
for _, x in pairs({199.5, 202.5, 205.5, 208.5, 211.5}) do add('electric-mining-drill', x, -73.5, S) end
for x = 212.5, 195.5, -1 do add('transport-belt', x, -71.5, W) end
for y = -70.5, -67.5 do add('transport-belt', 195.5, y, S) end
add('medium-electric-pole', 200.5, -70.5); add('medium-electric-pole', 207.5, -70.5)
-- RUNNER
