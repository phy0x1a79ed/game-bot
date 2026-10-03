-- ne-coal-backup.lua: infra-b band-coal backup for the NE yard: fast inserter (119.5,-67.5) lifts coal off band belt y=-66.5, belt x=119.5 north (UG under the two rails y=-131/-130), west at y=-141.5 to side-load the yard coal column x=117.5.
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{116, -144}, {122, -66}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('fast-inserter', 119.5, -67.5, S); add('medium-electric-pole', 118.5, -68.5)
for y = -68.5, -128.5, -1 do add('transport-belt', 119.5, y, N) end
add('underground-belt', 119.5, -129.5, N, {type = 'input'}); add('underground-belt', 119.5, -132.5, N, {type = 'output'})
for y = -133.5, -140.5, -1 do add('transport-belt', 119.5, y, N) end
add('transport-belt', 119.5, -141.5, W); add('transport-belt', 118.5, -141.5, W)
-- RUNNER
