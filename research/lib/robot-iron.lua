-- robot-iron.lua: UG hop of the robot-cell iron belt x=63.5 over the pipe row y=12.5.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{62, 10}, {65, 15}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('underground-belt', 63.5, 13.5, N, {type = 'input'}); add('underground-belt', 63.5, 11.5, N, {type = 'output'})
-- RUNNER
