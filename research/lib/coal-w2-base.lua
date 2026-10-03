-- coal-w2-base.lua: infra-b wagon 2 coal unload at Unload Stone Base: 6 coal-filter fast inserters north of the track, belt y=-163.5, UG under rail y=-161 at x=42.5, joins coal belt (43.5,-158.5). Inserters + filters placed by hand.
-- Inserter dir = PICKUP side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{35, -166}, {44, -157}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
for x = 36.5, 41.5 do add('transport-belt', x, -163.5, E) end
add('transport-belt', 42.5, -163.5, S)
add('underground-belt', 42.5, -162.5, S, {type = 'input'}); add('underground-belt', 42.5, -159.5, S, {type = 'output'})
add('transport-belt', 42.5, -158.5, E)
add('medium-electric-pole', 39.5, -164.5)
-- RUNNER
