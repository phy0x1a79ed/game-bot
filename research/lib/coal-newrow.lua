-- coal-newrow.lua: infra-b band-coal top-up for the new boiler row: fast inserter (95.5,-67.5) (ghost) off the band belt y=-66.5, belt x=95.5 north (UG under trunk y=-87.5), west along y=-104.5, south side-loading the row y=-103.5 at (77.5,-103.5).
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{77, -106}, {98, -66}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('fast-inserter', 95.5, -67.5, S); add('medium-electric-pole', 94.5, -68.5)
for y = -68.5, -85.5, -1 do add('transport-belt', 95.5, y, N) end
add('underground-belt', 95.5, -86.5, N, {type = 'input'}); add('underground-belt', 95.5, -88.5, N, {type = 'output'})
for y = -89.5, -103.5, -1 do add('transport-belt', 95.5, y, N) end
add('transport-belt', 95.5, -104.5, W)
for x = 94.5, 78.5, -1 do add('transport-belt', x, -104.5, W) end
add('transport-belt', 77.5, -104.5, S)
-- RUNNER
