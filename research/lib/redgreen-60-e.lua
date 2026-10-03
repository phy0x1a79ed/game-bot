-- redgreen-60-e.lua: STAGE 1 machines at 30/min each: 2 gear, 4 red, cable, EC, inserter, belt, 4 green AM2 with all inserters, plus the pole network (trunk x=109.5 from the pole (110.5,-0.5), rows y=-34.5/-30.5/-23.5/-16.5).
-- Rows: red+gear y=-32.5 (north of I/G), producers y=-25.5 (south of I/G), green y=-18.5. Stage 2 (redgreen-60-f.lua) adds the rest. Check alone: expect the splitter-free file clean.
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
gearm(114.5) gearm(117.5)
for x = 123.5, 132.5, 3 do redm(x) end
for x = 128.5, 137.5, 3 do greenm(x) end
am(113.5, -25.5, 'copper-cable') am(117.5, -25.5, 'electronic-circuit') am(121.5, -25.5, 'inserter') am(125.5, -25.5, 'transport-belt')
for _, x in pairs({112.5, 113.5, 117.5, 122.5, 126.5}) do add('long-handed-inserter', x, -27.5, S) end
add('fast-inserter', 120.5, -27.5, S) add('inserter', 124.5, -27.5, S)
add('fast-inserter', 115.5, -26.5, E) add('fast-inserter', 115.5, -25.5, E) add('fast-inserter', 119.5, -25.5, E)
add('long-handed-inserter', 120.5, -23.5, S) add('long-handed-inserter', 122.5, -23.5, S) add('fast-inserter', 125.5, -23.5, S)
poles({{109.5, -8.5}, {109.5, -16.5}, {109.5, -24.5}, {114.5, -30.5}, {120.5, -30.5}, {126.5, -30.5}, {132.5, -30.5}, {124.5, -34.5}, {130.5, -34.5},
  {117.5, -23.5}, {123.5, -23.5}, {128.5, -23.5}, {134.5, -23.5}, {140.5, -23.5}, {129.5, -16.5}, {135.5, -16.5}})
-- RUNNER
