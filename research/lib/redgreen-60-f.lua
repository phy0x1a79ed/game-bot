-- redgreen-60-f.lua: STAGE 2 machines (30/min -> 60/min each): gear 3, red 5-7, green 5-8 plus inserters and poles. Needs stage 1 standing (its pole chain and belts).
-- Check alone: the poles join stage 1's pole (132.5,-30.5) etc.; they list as disconnected until e is built.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
-- Inserter dirs below name the side items GO TO; the game's direction names the pickup side, so add() turns inserters 180.
local function add(name, x, y, dir, extra) dir = dir or N if name:find('inserter') then dir = (dir + 8) % 16 end L[#L + 1] = {name = name, x = x, y = y, dir = dir, extra = extra} end
local function belts(x0, x1, y, dir) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add('transport-belt', x, y, dir) end end
local function beltsy(x, y0, y1, dir) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add('transport-belt', x, y, dir) end end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
local function am(x, y, recipe) add('assembling-machine-2', x, y, N, {recipe = recipe}) end
local function poles(list) for _, p in pairs(list) do add('medium-electric-pole', p[1], p[2]) end end
local AREA = {{95, -45}, {160, 30}}
local function gearm(x) am(x, -32.5, 'iron-gear-wheel') add('fast-inserter', x - 1, -30.5, N) add('long-handed-inserter', x + 1, -30.5, S) end
local function redm(x) am(x, -32.5, 'automation-science-pack') add('inserter', x - 1, -30.5, N) add('long-handed-inserter', x + 1, -30.5, N) add('inserter', x, -34.5, N) end
local function greenm(x) am(x, -18.5, 'logistic-science-pack') add('inserter', x - 1, -20.5, S) add('long-handed-inserter', x + 1, -20.5, S) add('inserter', x, -16.5, S) end
gearm(120.5)
for x = 135.5, 141.5, 3 do redm(x) end
for x = 140.5, 149.5, 3 do greenm(x) end
poles({{136.5, -34.5}, {142.5, -34.5}, {138.5, -30.5}, {141.5, -30.5}, {146.5, -23.5}, {149.5, -23.5}, {141.5, -16.5}, {147.5, -16.5}})
-- RUNNER
