-- ug-column.lua: re-lay the two UG outputs of the B1 column x=162.5 at y=2.5 and y=-3.5 after purging coal.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{161, -5}, {164, 4}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('underground-belt', 162.5, 2.5, N, {type = 'output'}); add('underground-belt', 162.5, -3.5, N, {type = 'output'})
-- RUNNER
