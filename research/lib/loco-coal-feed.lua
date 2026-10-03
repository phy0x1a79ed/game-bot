-- loco-coal-feed.lua: infra-b train-independent coal for the lead loco of train 29: fast inserter (placed by hand) (120.5,-140.5) lifts coal off the band backup line x=119.5, belt y=-142.5 west (UG under column x=117.5) to side-load the loco tap belt x=44.5 at (45.5,-142.5).
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{44, -145}, {124, -137}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('transport-belt', 121.5, -140.5, N); add('transport-belt', 121.5, -141.5, N)
for x = 121.5, 119.5, -1 do add('transport-belt', x, -142.5, W) end
add('underground-belt', 118.5, -142.5, W, {type = 'input'}); add('underground-belt', 116.5, -142.5, W, {type = 'output'})
for x = 115.5, 45.5, -1 do add('transport-belt', x, -142.5, W) end
add('medium-electric-pole', 121.5, -138.5)
-- RUNNER
