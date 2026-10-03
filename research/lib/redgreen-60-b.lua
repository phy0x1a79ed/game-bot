-- redgreen-60-b.lua: STAGE 1 iron|copper feed of the red+green block: splitter on M' (93.5,26) and the belt north on x=98.5 to the site's west edge (106.5,-29.5).
-- Route found with lib/belt-path2.lua (cost 77). One UG pair (98.5,11.5)->(98.5,6.5) goes under the pack belts y=9.5 and y=7.5. Lanes arrive as on M': iron lane 1, copper lane 2.
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
add('splitter', 93.5, 26.0, E)
belts(94.5, 97.5, 25.5, E)
beltsy(98.5, 25.5, 12.5, N)
ug(98.5, 11.5, N, 'input')
ug(98.5, 6.5, N, 'output')
beltsy(98.5, 5.5, -28.5, N)
belts(98.5, 106.5, -29.5, E)
-- RUNNER
