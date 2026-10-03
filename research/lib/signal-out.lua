-- signal-out.lua: infra-b outputs for the rail-signal (38.5,-97.5) and chain-signal (42.5,-97.5) makers: north inserters into passive provider chests, pole between.
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{36, -102}, {46, -98}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
for _, x in pairs({38.5, 42.5}) do add('fast-inserter', x, -99.5, S); add('passive-provider-chest', x, -100.5) end
add('medium-electric-pole', 40.5, -99.5)
-- RUNNER
