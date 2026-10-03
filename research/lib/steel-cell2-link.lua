-- steel-cell2-link.lua: infra-b link cell 2's steel belt (y=-68.5, flowing west) to the head of cell 1's steel belt: west under belt column x=55.5, north along x=52.5 under the plate belts, east along y=-78.5 into (54.5,-78.5). Needs chest (52.5,-78.5), inserters (53.5,-78.5),(57.5,-68.5), chest (56.5,-68.5) deconstructed first.
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{50, -80}, {59, -67}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
add('transport-belt', 57.5, -68.5, W)
add('underground-belt', 56.5, -68.5, W, {type = 'input'}); add('underground-belt', 52.5, -68.5, W, {type = 'output'})
add('transport-belt', 51.5, -68.5, N)
add('transport-belt', 51.5, -69.5, N); add('transport-belt', 51.5, -70.5, N)
add('underground-belt', 51.5, -71.5, N, {type = 'input'}); add('underground-belt', 51.5, -74.5, N, {type = 'output'})
add('transport-belt', 51.5, -75.5, E)
add('transport-belt', 52.5, -75.5, N); add('transport-belt', 52.5, -76.5, N); add('transport-belt', 52.5, -77.5, N)
add('transport-belt', 52.5, -78.5, E); add('transport-belt', 53.5, -78.5, E)
-- RUNNER
