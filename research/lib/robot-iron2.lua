-- robot-iron2.lua: UG output (63.5,11.5) of the robot-cell iron belt.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{62, 10}, {65, 13}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('underground-belt', 63.5, 11.5, N, {type = 'output'})
-- RUNNER
