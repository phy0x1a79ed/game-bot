-- util-30-e.lua: STAGE 1 chem hub + robot-frame block machines (lubricant, sulfur, acid, EC cell, engine cluster G E P E G, 2 EEU, 1 battery plant, 3 flying-robot-frame AM2).
-- Rows: CH y=26.5; FB X row y=39.5 (EEU k7..9, battery k10..12), FB Y row y=46.5 (EC cell k0..2, cluster k3..9, FRF k11..15). Slot k centre x=170.5+4k.
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
ams(39.5, 'electric-engine-unit', {198.5, 202.5})
ams(46.5, 'copper-cable', {170.5, 178.5})
ams(46.5, 'electronic-circuit', {174.5})
ams(46.5, 'engine-unit', {186.5, 194.5})
ams(46.5, 'flying-robot-frame', {214.5, 218.5, 222.5})
ams(46.5, 'iron-gear-wheel', {182.5, 198.5})
ams(46.5, 'pipe', {190.5})
chems(26.5, 'lubricant', {170.5}, N)
chems(26.5, 'sulfur', {178.5}, N)
chems(26.5, 'sulfuric-acid', {182.5}, N)
chems(39.5, 'battery', {210.5}, N)
ins('inserter', {{182.5, 28.5, N}, {210.5, 37.5, S}, {197.5, 41.5, N}, {199.5, 41.5, S}, {201.5, 41.5, N}, {203.5, 41.5, S}, {186.5, 44.5, N}, {194.5, 44.5, N}, {213.5, 44.5, S}, {217.5, 44.5, S}, {221.5, 44.5, S}, {170.5, 48.5, N}, {174.5, 48.5, N}, {178.5, 48.5, N}, {182.5, 48.5, N}, {190.5, 48.5, N}, {198.5, 48.5, N}, {215.5, 48.5, S}, {219.5, 48.5, S}, {223.5, 48.5, S}})
ins('fast-inserter', {{180.5, 26.5, E}, {172.5, 46.5, E}, {176.5, 46.5, W}, {184.5, 46.5, E}, {188.5, 46.5, W}, {192.5, 46.5, E}, {196.5, 46.5, W}})
ins('long-handed-inserter', {{198.5, 41.5, N}, {202.5, 41.5, N}, {210.5, 41.5, S}, {174.5, 44.5, N}, {214.5, 44.5, S}, {218.5, 44.5, S}, {222.5, 44.5, S}, {186.5, 48.5, N}, {194.5, 48.5, N}, {213.5, 48.5, N}, {217.5, 48.5, N}, {221.5, 48.5, N}})
poles({{172.5, 25.5}, {180.5, 25.5}, {196.5, 38.5}, {204.5, 38.5}, {212.5, 38.5}, {172.5, 45.5}, {176.5, 45.5}, {180.5, 45.5}, {184.5, 45.5}, {188.5, 45.5}, {192.5, 45.5}, {196.5, 45.5}, {212.5, 45.5}, {220.5, 45.5}})
-- RUNNER
