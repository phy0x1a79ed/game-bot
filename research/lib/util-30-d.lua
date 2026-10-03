-- util-30-d.lua: Belts of the LDS and pack block, the PU/FRF routes to the packs and the pack route to the production PO head.
-- LDM edge tiles (x=164.5): c1 y=74.5 (red, copper|coal), c2 y=75.5 (steel). Pack belt joins PO by sideload at (255.5,-10.5), south lane; the production packs use the north lane.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
-- Inserter dirs name the side items GO TO; the game's direction names the pickup side, so add() turns inserters 180 (the prod-30 convention).
local function add(name, x, y, dir, extra) dir = dir or N if name:find('inserter') then dir = (dir + 8) % 16 end L[#L + 1] = {name = name, x = x, y = y, dir = dir, extra = extra} end
local function belts(x0, x1, y, dir, nm) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add(nm or 'transport-belt', x, y, dir) end end
local function beltsy(x, y0, y1, dir, nm) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add(nm or 'transport-belt', x, y, dir) end end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
local function ams(y, recipe, xs) for _, x in pairs(xs) do add('assembling-machine-2', x, y, N, {recipe = recipe}) end end
local function chems(y, recipe, xs, dir) for _, x in pairs(xs) do add('chemical-plant', x, y, dir, {recipe = recipe}) end end
local function ins(nm, list) for _, p in pairs(list) do add(nm, p[1], p[2], p[3]) end end
local function poles(list) for _, p in pairs(list) do add('medium-electric-pole', p[1], p[2]) end end
local function pipes(x0, x1, y) for x = x0, x1 do add('pipe', x, y) end end
local function pipesy(x, y0, y1) for y = y0, y1 do add('pipe', x, y) end end
local function ptgs(list) for _, p in pairs(list) do add('pipe-to-ground', p[1], p[2], p[3]) end end
local AREA = {{158, -14}, {292, 90}}
belts(256.5, 255.5, -10.5, W)
belts(287.5, 256.5, -9.5, W)
belts(243.5, 277.5, 51.5, E)
belts(177.5, 259.5, 68.5, E)
belts(279.5, 240.5, 74.5, W)
belts(164.5, 219.5, 75.5, E)
belts(243.5, 262.5, 75.5, E)
belts(283.5, 278.5, 76.5, W)
belts(263.5, 286.5, 78.5, E)
beltsy(255.5, -9.5, -9.5, N)
beltsy(263.5, 75.5, 77.5, S)
beltsy(277.5, 76.5, 75.5, N)
beltsy(283.5, 51.5, 75.5, S)
beltsy(287.5, 78.5, -8.5, N)
belts(164.5, 219.5, 74.5, E, 'fast-transport-belt')
ug(278.5, 51.5, E, 'input')
ug(282.5, 51.5, E, 'output')
-- RUNNER
