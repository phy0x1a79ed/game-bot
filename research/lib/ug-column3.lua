-- ug-column3.lua: UG output (162.5,13.5) of the B1 column.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{161, 12}, {164, 15}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('underground-belt', 162.5, 13.5, N, {type = 'output'})
-- RUNNER
