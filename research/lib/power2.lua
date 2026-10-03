-- power2.lua: infra-b POWER-2 A2: 10 boilers + engines on a new line x=99.5 (east flank only), coal from 4 band-belt taps at (100.5..103.5,-67.5) via collector y=-68.5, water from the trunk end (96.5,-87.5) by a PTG hop under the coal line.
-- Inserter dir = PICKUP side. Boiler dir = steam output side. Part 1: all 10 boilers, 10 first engines, 4 second engines (rows without a blocker at x112.5).
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local AREA = {{96, -120}, {118, -66}}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
local free2 = {[-90.5] = 1, [-96.5] = 1, [-102.5] = 1, [-105.5] = 1}
for k = 0, 9 do
  local y = -90.5 - 3 * k
  add('inserter', 100.5, y, W); add('boiler', 102, y, E); add('pipe', 103.5, y)
  add('steam-engine', 106.5, y, E)
  if free2[y] then add('pipe', 109.5, y); add('steam-engine', 112.5, y, E) end
  if k % 2 == 0 then add('medium-electric-pole', 103.5, y - 1); if free2[y] then add('medium-electric-pole', 109.5, y - 1) end end
end
for y = -68.5, -117.5, -1 do add('transport-belt', 99.5, y, N) end
for x = 103.5, 100.5, -1 do add('transport-belt', x, -68.5, W) end
for x = 100.5, 103.5 do add('fast-inserter', x, -67.5, S) end
add('medium-electric-pole', 102.5, -69.5); add('medium-electric-pole', 100.5, -75.5); add('medium-electric-pole', 100.5, -82.5); add('medium-electric-pole', 103.5, -88.5)
for x = 97.5, 97.5 do add('pipe', x, -87.5) end
add('pipe-to-ground', 98.5, -87.5, W); add('pipe-to-ground', 100.5, -87.5, E)
add('pipe', 101.5, -87.5); add('pipe', 101.5, -88.5)
-- RUNNER
