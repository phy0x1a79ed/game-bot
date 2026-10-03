-- util-30-j.lua: STAGE 2 LDS and pack block additions (plastic plant 2, LDS 7-11, packs 4-5).
-- Same grid as file g.
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
ams(71.5, 'low-density-structure', {202.5, 206.5, 210.5, 214.5, 218.5})
ams(71.5, 'utility-science-pack', {254.5, 258.5})
chems(71.5, 'plastic-bar', {174.5}, N)
ins('inserter', {{202.5, 69.5, N}, {206.5, 69.5, N}, {210.5, 69.5, N}, {214.5, 69.5, N}, {218.5, 69.5, N}, {254.5, 69.5, S}, {258.5, 69.5, S}, {173.5, 73.5, N}, {201.5, 73.5, N}, {205.5, 73.5, N}, {209.5, 73.5, N}, {213.5, 73.5, N}, {217.5, 73.5, N}, {253.5, 73.5, N}, {257.5, 73.5, N}})
ins('long-handed-inserter', {{175.5, 73.5, S}, {202.5, 73.5, N}, {206.5, 73.5, N}, {210.5, 73.5, N}, {214.5, 73.5, N}, {218.5, 73.5, N}, {255.5, 73.5, S}, {259.5, 73.5, S}})
poles({{204.5, 70.5}, {212.5, 70.5}, {220.5, 70.5}, {260.5, 70.5}})
-- RUNNER
