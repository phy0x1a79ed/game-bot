-- util-30-i.lua: STAGE 2 processing-unit block additions (EC cells 4-6, adv group 3, PU 4-5).
-- Same grid as file f.
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
ams(55.5, 'processing-unit', {254.5, 258.5})
ams(62.5, 'advanced-circuit', {266.5, 274.5})
ams(62.5, 'copper-cable', {206.5, 214.5, 218.5, 226.5, 230.5, 238.5, 270.5})
ams(62.5, 'electronic-circuit', {210.5, 222.5, 234.5})
ins('inserter', {{253.5, 57.5, N}, {257.5, 57.5, N}, {265.5, 60.5, S}, {273.5, 60.5, S}, {206.5, 64.5, N}, {210.5, 64.5, N}, {214.5, 64.5, N}, {218.5, 64.5, N}, {222.5, 64.5, N}, {226.5, 64.5, N}, {230.5, 64.5, N}, {234.5, 64.5, N}, {238.5, 64.5, N}, {270.5, 64.5, N}})
ins('fast-inserter', {{210.5, 60.5, N}, {222.5, 60.5, N}, {234.5, 60.5, N}, {208.5, 62.5, E}, {212.5, 62.5, W}, {220.5, 62.5, E}, {224.5, 62.5, W}, {232.5, 62.5, E}, {236.5, 62.5, W}, {268.5, 62.5, W}, {272.5, 62.5, E}})
ins('long-handed-inserter', {{255.5, 53.5, N}, {259.5, 53.5, N}, {254.5, 57.5, N}, {258.5, 57.5, N}, {267.5, 60.5, N}, {275.5, 60.5, N}})
poles({{260.5, 54.5}, {208.5, 61.5}, {224.5, 61.5}, {232.5, 61.5}, {268.5, 61.5}, {272.5, 61.5}, {276.5, 61.5}})
-- RUNNER
