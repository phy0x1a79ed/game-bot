-- redgreen-60-d.lua: STAGE 1 pack route: red pack belt P_r y=-35.5 and green pack belt P_g y=-15.5 flow west to the column x=108.5, which runs south into the campus RG belt at (108.5,0.5)->(109.5,0.5).
-- Red rides the column's west lane, green side-loads onto the east lane at (108.5,-15.5).
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
belts(141.5, 109.5, -35.5, W)
belts(149.5, 109.5, -15.5, W)
beltsy(108.5, -35.5, -0.5, S)
add('transport-belt', 108.5, 0.5, E)
-- RUNNER
