-- oil-2-b.lua: STAGE O2 of oil 2: refinery 4 (95.5,-5.5), light cracking L1 (83.5,2.5), the pipes that join them to the stage O1 nets, and the pole for L1. Run after oil-2-a.lua and oil-2-c.lua are built.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
local function pp(x, y, f) add('pipe', x, y, N, {fluid = f}) end
local function pg(x, y, d, f) add('pipe-to-ground', x, y, d, {fluid = f}) end

add('oil-refinery', 95.5, -5.5, S, {recipe = 'advanced-oil-processing'})
add('chemical-plant', 83.5, 2.5, N, {recipe = 'light-oil-cracking'})
pp(96.5, -10.5, 'water')
pp(96.5, -9.5, 'water')
pp(77.5, -8.5, 'water')
pp(78.5, -8.5, 'water')
pp(79.5, -8.5, 'water')
pp(80.5, -8.5, 'water')
pp(81.5, -8.5, 'water')
pp(82.5, -8.5, 'water')
pg(88.5, -8.5, W, 'crude')
pg(93.5, -8.5, E, 'crude')
pp(94.5, -8.5, 'crude')
pp(96.5, -8.5, 'water')
pg(82.5, -7.5, N, 'water')
pg(87.5, -2.5, W, 'pg')
pg(92.5, -2.5, E, 'pg')
pp(93.5, -2.5, 'pg')
pp(95.5, -2.5, 'light')
pp(97.5, -2.5, 'heavy')
pp(94.5, -1.5, 'light')
pp(95.5, -1.5, 'light')
pp(93.5, -0.5, 'light')
pp(94.5, -0.5, 'light')
pg(82.5, 0.5, S, 'water')
pp(84.5, 0.5, 'light')
pp(85.5, 0.5, 'light')
pp(86.5, 0.5, 'light')
pp(87.5, 0.5, 'light')
pp(82.5, 4.5, 'pg')
pg(83.5, 4.5, W, 'pg')
pg(85.5, 4.5, E, 'pg')
add('medium-electric-pole', 87.5, -1.5, N)
-- RUNNER
