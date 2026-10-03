-- radar-out.lua: infra-b output path for the radar maker (-0.5,35.5): inserter (1.5,35.5) -> passive provider chest (2.5,35.5), pole (1.5,34.5).
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{0, 33}, {4, 38}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('fast-inserter', 1.5, 35.5, W); add('passive-provider-chest', 2.5, 35.5); add('medium-electric-pole', 1.5, 34.5)
-- RUNNER
