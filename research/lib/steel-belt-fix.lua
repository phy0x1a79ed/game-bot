-- steel-belt-fix.lua: UG hop of the steel belt under Join 2 column x=101.5 at y=-40.5.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{99, -42}, {104, -39}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('underground-belt', 100.5, -40.5, E, {type = 'input'}); add('underground-belt', 102.5, -40.5, E, {type = 'output'})
-- RUNNER
