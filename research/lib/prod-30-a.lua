-- prod-30-a.lua: STAGE 0 of the production-science 30/min block (council/builder2/prod-30.md): 15 loaded gun turrets around x 160..281, y -28..16, two roboports on net 6, and the pole tie from the campus.
-- Roboport R1 (172,-22) joins net 6 (logistic areas overlap: 46 tiles from (126,-3)); R2 (220,-22) joins R1 (48). Together they cover x 117..275. Turrets carry 20 firearm-magazine each (stock 300 in net 6 first).
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
-- Inserter dirs name the side items GO TO; the game's direction names the pickup side, so add() turns inserters 180.
local function add(name, x, y, dir, extra) dir = dir or N if name:find('inserter') then dir = (dir + 8) % 16 end L[#L + 1] = {name = name, x = x, y = y, dir = dir, extra = extra} end
local function belts(x0, x1, y, dir) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add('transport-belt', x, y, dir) end end
local function beltsy(x, y0, y1, dir) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add('transport-belt', x, y, dir) end end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
local function am(x, y, recipe) add('assembling-machine-2', x, y, N, {recipe = recipe}) end
local function poles(list) for _, p in pairs(list) do add('medium-electric-pole', p[1], p[2]) end end
local AREA = {{158, -30}, {280, 16}}
for _, t in pairs({{170, -27}, {190, -27}, {210, -27}, {230, -27}, {250, -27}, {270, -27}, {170, 14}, {190, 14}, {210, 14}, {230, 14}, {250, 14}, {270, 14}, {280, -18}, {280, -4}, {280, 10}}) do
  add('gun-turret', t[1], t[2], N, {ammo = 'firearm-magazine', n = 20})
end
add('roboport', 172, -22) add('roboport', 220, -22)
poles({{145.5, 1.5}, {153.5, 1.5}, {159.5, 1.5}, {163.5, -8.5}, {163.5, -14.5}, {163.5, -19.5}, {172.5, -19.5}, {180.5, -19.5}, {188.5, -19.5}, {196.5, -19.5}, {204.5, -19.5}, {212.5, -19.5}, {220.5, -19.5}})
-- RUNNER
