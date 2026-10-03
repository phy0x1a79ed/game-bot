-- cell3-split.lua: splitter on Plate Main E x=10.5 for cell 3's iron tap.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{9, -84}, {13, -81}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('splitter', 11, -82.5, S)
-- RUNNER
