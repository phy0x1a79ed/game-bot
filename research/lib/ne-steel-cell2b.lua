-- ne-steel-cell2b.lua: UG exit for cell 2 coal belt: output (75.5,-67.5).
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{74, -69}, {77, -66}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('underground-belt', 75.5, -67.5, W, {type = 'output'})
-- RUNNER
