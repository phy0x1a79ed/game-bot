-- steel-coal.lua: coal feed for the steel cell. The splitter (102,43.5) filters coal off the loop column x=101.5, so lane 2 north of it is empty.
-- Long-handed inserter (100.5,42.5) lifts coal off the coal-only belt (102.5,42.5) over the loop onto (98.5,42.5); belt carries it to (99.5,41.5); inserter (100.5,41.5) drops it on x=101.5 from the west = east lane = lane 2.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
local AREA = {{95, 35}, {110, 48}}
add('long-handed-inserter', 100.5, 42.5, E); add('inserter', 100.5, 41.5, W)
add('transport-belt', 98.5, 42.5, N); add('transport-belt', 98.5, 41.5, E); add('transport-belt', 99.5, 41.5, E)
-- RUNNER
