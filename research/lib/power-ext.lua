-- power-ext.lua: infra-b power extension: 5 boilers + 10 engines on EACH flank of the train coal line x=78.5 (y -103..-88), fed by inserters straight off it; water from the east block's east port via PTG (85.5,-21.5), column x=96.5, trunk y=-87.5.
-- Inserter dir = PICKUP side. Boiler dir = steam output side.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{62, -105}, {98, -20}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
for k = 0, 4 do
  local y = -101.5 + 3 * k
  add('inserter', 79.5, y, W); add('boiler', 81, y, E); add('pipe', 82.5, y)
  add('steam-engine', 85.5, y, E); add('pipe', 88.5, y); add('steam-engine', 91.5, y, E)
  add('inserter', 77.5, y, E); add('boiler', 76, y, W); add('pipe', 74.5, y)
  add('steam-engine', 71.5, y, E); add('pipe', 68.5, y); add('steam-engine', 65.5, y, E)
  if k % 2 == 0 then
    for _, x in pairs({82.5, 88.5, 74.5, 68.5}) do add('medium-electric-pole', x, y + 1) end
  end
end
add('medium-electric-pole', 82.5, -83.5)
add('pipe', 76.5, -87.5); add('pipe-to-ground', 77.5, -87.5, W); add('pipe-to-ground', 79.5, -87.5, E)
for x = 80.5, 96.5 do add('pipe', x, -87.5) end
for y = -86.5, -22.5 do
  if y == -67.5 then add('pipe-to-ground', 96.5, y, N)
  elseif y == -65.5 then add('pipe-to-ground', 96.5, y, S)
  elseif y == -55.5 then add('pipe-to-ground', 96.5, y, N)
  elseif y == -53.5 then add('pipe-to-ground', 96.5, y, S)
  elseif y ~= -66.5 and y ~= -54.5 then add('pipe', 96.5, y) end
end
add('pipe', 96.5, -21.5); add('pipe-to-ground', 95.5, -21.5, E); add('pipe-to-ground', 85.5, -21.5, W)
-- RUNNER
