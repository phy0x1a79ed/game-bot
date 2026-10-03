-- loco-coal-feed2.lua: tap inserter for loco-coal-feed.lua.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{119, -142}, {123, -139}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('fast-inserter', 120.5, -140.5, W)
-- RUNNER
