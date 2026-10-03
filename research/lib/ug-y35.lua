-- ug-y35.lua: re-lay the UG output of builder2's y=3.5 belt at x=181.5 (east) after the lane-2 purge.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{180, 2}, {184, 5}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('underground-belt', 181.5, 3.5, E, {type = 'output'})
-- RUNNER
