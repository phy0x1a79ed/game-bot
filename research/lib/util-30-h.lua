-- util-30-h.lua: STAGE 2 chem hub + robot-frame block additions (rest of the engine cluster, 3rd EEU, battery plants 2-3, FRF 4-5).
-- Same grid as file e.
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
ams(39.5, 'electric-engine-unit', {206.5})
ams(46.5, 'engine-unit', {202.5})
ams(46.5, 'flying-robot-frame', {226.5, 230.5})
ams(46.5, 'pipe', {206.5})
chems(39.5, 'battery', {214.5, 218.5}, N)
ins('inserter', {{214.5, 37.5, S}, {218.5, 37.5, S}, {205.5, 41.5, N}, {207.5, 41.5, S}, {202.5, 44.5, N}, {225.5, 44.5, S}, {229.5, 44.5, S}, {206.5, 48.5, N}, {227.5, 48.5, S}, {231.5, 48.5, S}})
ins('fast-inserter', {{200.5, 46.5, E}, {204.5, 46.5, W}})
ins('long-handed-inserter', {{206.5, 41.5, N}, {214.5, 41.5, S}, {218.5, 41.5, S}, {226.5, 44.5, S}, {230.5, 44.5, S}, {202.5, 48.5, N}, {225.5, 48.5, N}, {229.5, 48.5, N}})
poles({{220.5, 38.5}, {200.5, 45.5}, {204.5, 45.5}, {228.5, 45.5}})
-- RUNNER
