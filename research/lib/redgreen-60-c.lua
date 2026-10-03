-- redgreen-60-c.lua: STAGE 1 site belts of the red+green block, all at full 60/min length: I (iron|copper) y=-29.5, G (gears) y=-28.5, IBn (belts) y=-22.5, IBf (inserters) y=-21.5; all flow east.
-- I crosses the pack column x=108.5 by the UG pair (107.5)->(109.5).
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
local function belts(x0, x1, y, dir) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add('transport-belt', x, y, dir) end end
local function beltsy(x, y0, y1, dir) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add('transport-belt', x, y, dir) end end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
local function am(x, y, recipe) add('assembling-machine-2', x, y, N, {recipe = recipe}) end
local function poles(list) for _, p in pairs(list) do add('medium-electric-pole', p[1], p[2]) end end
local AREA = {{95, -45}, {160, 30}}
ug(107.5, -29.5, E, 'input')
ug(109.5, -29.5, E, 'output')
belts(110.5, 142.5, -29.5, E)
belts(115.5, 142.5, -28.5, E)
belts(125.5, 150.5, -22.5, E)
belts(120.5, 150.5, -21.5, E)
-- RUNNER
