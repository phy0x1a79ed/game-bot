-- util-30-f.lua: STAGE 1 processing-unit block machines (plastic plant, 3 EC cells, 2 adv groups, 3 PU AM2).
-- PU row y=55.5 (plastic k0, PU k18..22), cells row y=62.5 (EC cells k0..17, adv groups k18..26).
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
ams(55.5, 'processing-unit', {242.5, 246.5, 250.5})
ams(62.5, 'advanced-circuit', {242.5, 250.5, 254.5, 262.5})
ams(62.5, 'copper-cable', {170.5, 178.5, 182.5, 190.5, 194.5, 202.5, 246.5, 258.5})
ams(62.5, 'electronic-circuit', {174.5, 186.5, 198.5})
chems(55.5, 'plastic-bar', {170.5}, N)
ins('inserter', {{169.5, 57.5, N}, {241.5, 57.5, N}, {245.5, 57.5, N}, {249.5, 57.5, N}, {241.5, 60.5, S}, {249.5, 60.5, S}, {253.5, 60.5, S}, {261.5, 60.5, S}, {170.5, 64.5, N}, {174.5, 64.5, N}, {178.5, 64.5, N}, {182.5, 64.5, N}, {186.5, 64.5, N}, {190.5, 64.5, N}, {194.5, 64.5, N}, {198.5, 64.5, N}, {202.5, 64.5, N}, {246.5, 64.5, N}, {258.5, 64.5, N}})
ins('fast-inserter', {{174.5, 60.5, N}, {186.5, 60.5, N}, {198.5, 60.5, N}, {172.5, 62.5, E}, {176.5, 62.5, W}, {184.5, 62.5, E}, {188.5, 62.5, W}, {196.5, 62.5, E}, {200.5, 62.5, W}, {244.5, 62.5, W}, {248.5, 62.5, E}, {256.5, 62.5, W}, {260.5, 62.5, E}})
ins('long-handed-inserter', {{243.5, 53.5, N}, {247.5, 53.5, N}, {251.5, 53.5, N}, {171.5, 57.5, S}, {242.5, 57.5, N}, {246.5, 57.5, N}, {250.5, 57.5, N}, {243.5, 60.5, N}, {251.5, 60.5, N}, {255.5, 60.5, N}, {263.5, 60.5, N}})
poles({{172.5, 54.5}, {244.5, 54.5}, {252.5, 54.5}, {172.5, 61.5}, {176.5, 61.5}, {180.5, 61.5}, {184.5, 61.5}, {188.5, 61.5}, {196.5, 61.5}, {200.5, 61.5}, {204.5, 61.5}, {212.5, 61.5}, {220.5, 61.5}, {228.5, 61.5}, {236.5, 61.5}, {244.5, 61.5}, {248.5, 61.5}, {252.5, 61.5}, {256.5, 61.5}, {260.5, 61.5}})
-- RUNNER
