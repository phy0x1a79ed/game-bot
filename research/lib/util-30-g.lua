-- util-30-g.lua: STAGE 1 LDS and pack block machines (plastic plant 1, 6 LDS AM2, 3 pack AM2).
-- Row y=71.5 (plastic k0..1, LDS k2..12, packs k18..22).
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
ams(71.5, 'low-density-structure', {178.5, 182.5, 186.5, 190.5, 194.5, 198.5})
ams(71.5, 'utility-science-pack', {242.5, 246.5, 250.5})
chems(71.5, 'plastic-bar', {170.5}, N)
ins('inserter', {{178.5, 69.5, N}, {182.5, 69.5, N}, {186.5, 69.5, N}, {190.5, 69.5, N}, {194.5, 69.5, N}, {198.5, 69.5, N}, {242.5, 69.5, S}, {246.5, 69.5, S}, {250.5, 69.5, S}, {169.5, 73.5, N}, {177.5, 73.5, N}, {181.5, 73.5, N}, {185.5, 73.5, N}, {189.5, 73.5, N}, {193.5, 73.5, N}, {197.5, 73.5, N}, {241.5, 73.5, N}, {245.5, 73.5, N}, {249.5, 73.5, N}})
ins('long-handed-inserter', {{171.5, 73.5, S}, {178.5, 73.5, N}, {182.5, 73.5, N}, {186.5, 73.5, N}, {190.5, 73.5, N}, {194.5, 73.5, N}, {198.5, 73.5, N}, {243.5, 73.5, S}, {247.5, 73.5, S}, {251.5, 73.5, S}})
poles({{172.5, 70.5}, {180.5, 70.5}, {188.5, 70.5}, {196.5, 70.5}, {244.5, 70.5}, {252.5, 70.5}})
-- RUNNER
