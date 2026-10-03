-- loco-ug-fix.lua: UG exit (44.5,-139.5) facing south for the lead-loco tap belt.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{43, -141}, {46, -138}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('underground-belt', 44.5, -139.5, S, {type = 'output'})
-- RUNNER
