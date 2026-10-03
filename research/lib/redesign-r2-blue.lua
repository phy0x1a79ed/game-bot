-- redesign-r2-blue.lua: ghost layout of the 30 packs/min blue science block at S1 (redesign-r2.md).
-- MODE='check'   : can_place, self-overlap, power coverage and pole connectivity (a read).
-- MODE='place'   : create the ghosts (a Lua order; robots build them). Idempotent.
-- MODE='recipes' : set the recipe on every built machine of the layout that lacks it (a setting).
-- Manual, before 'place': mine the belt (98.5,45.5) and build a splitter at (98.5,46) facing east (the loop tap).
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra} end
local function belts(x0, x1, y, dir) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add('transport-belt', x, y, dir) end end
local function beltsy(x, y0, y1, dir) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add('transport-belt', x, y, dir) end end
local function pipes(x0, x1, y) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add('pipe', x, y) end end
local function pipesy(x, y0, y1) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add('pipe', x, y) end end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
local function am(name, x, y, recipe) add(name, x, y, N, {recipe = recipe}) end

-- FEED: M' (lane 1 iron, lane 2 copper) extended from (95.5,26.5) to the spur y=30.5
belts(96.5, 99.5, 26.5, E); ug(100.5, 26.5, E, 'input'); ug(103.5, 26.5, E, 'output')
belts(104.5, 109.5, 26.5, E); add('transport-belt', 110.5, 26.5, S); beltsy(110.5, 27.5, 29.5, S)
add('transport-belt', 110.5, 30.5, E); belts(111.5, 123.5, 30.5, E)
-- FEED: loop branch (lane 1 iron, lane 2 coal) from the splitter (98.5,46) [manual]
belts(99.5, 105.5, 46.5, E); add('transport-belt', 106.5, 46.5, N)
add('transport-belt', 106.5, 45.5, N); beltsy(106.5, 44.5, 28.5, N); ug(106.5, 27.5, N, 'input'); ug(106.5, 25.5, N, 'output')
beltsy(106.5, 24.5, 18.5, N); add('transport-belt', 106.5, 17.5, E); belts(107.5, 120.5, 17.5, E)   -- F
-- F and the column are one through path whose only consumers (furnaces, plastic coal) eat both lanes' items, so no lane can deadlock
-- FEED: water, pumped off (96.5,30.5)
add('pipe', 96.5, 29.5); add('pump', 98.0, 29.5, E)
add('pipe-to-ground', 99.5, 29.5, W); add('pipe-to-ground', 108.5, 29.5, E)
pipesy(109.5, 29.5, 38.5); add('pipe-to-ground', 110.5, 38.5, W); add('pipe-to-ground', 119.5, 38.5, E)
pipes(120.5, 148.5, 38.5); pipesy(148.5, 39.5, 41.5)
-- FEED: petroleum gas, tapped beside module 3's sulfur plant (94.5,44.5 stays a PTG, never a pipe), pumped
add('pipe-to-ground', 94.5, 44.5, W); add('pipe-to-ground', 99.5, 44.5, E)
add('pipe-to-ground', 100.5, 44.5, W); add('pipe-to-ground', 109.5, 44.5, E)
add('pump', 111.0, 44.5, E)
pipes(112.5, 144.5, 44.5); add('pipe', 112.5, 43.5); add('pipe', 112.5, 42.5); add('pipe-to-ground', 145.5, 44.5, W); add('pipe-to-ground', 148.5, 44.5, E)
add('pipe', 149.5, 44.5); add('pipe', 149.5, 43.5); add('pipe', 148.5, 43.5)

-- NORTH ZONE: 4 steel furnaces on F; gear AM2 and pipe AM2 on the spur (iron only, no coal)
for _, fx in pairs({112, 115, 118, 121}) do
  add('steel-furnace', fx, 20)
  add('inserter', fx - 0.5, 18.5, N)
  add('long-handed-inserter', fx - 0.5, 22.5, N)      -- steel -> Ein1 lane 2
end
am('assembling-machine-2', 117.5, 27.5, 'pipe'); add('fast-inserter', 117.5, 29.5, S)
add('long-handed-inserter', 117.5, 25.5, S); add('long-handed-inserter', 118.5, 25.5, S)   -- pipes -> Ein2
am('assembling-machine-2', 113.5, 27.5, 'iron-gear-wheel'); add('inserter', 113.5, 25.5, S); add('fast-inserter', 113.5, 29.5, S)
belts(111.5, 144.5, 24.5, E)  -- Ein1: lane 1 gears, lane 2 steel
belts(116.5, 145.5, 23.5, E)  -- Ein2: pipes

-- ENGINE ROW (7 AM2), MID, ADV ROW (6 AM2)
for k = 0, 6 do
  local cx = 127.5 + 3 * k
  am('assembling-machine-2', cx, 27.5, 'engine-unit')
  add('inserter', cx - 1, 25.5, N); add('long-handed-inserter', cx, 25.5, N); add('inserter', cx, 29.5, N)
  if k % 2 == 0 then add('medium-electric-pole', cx + 1, 25.5); add('medium-electric-pole', cx + 1, 29.5) end
end
belts(125.5, 149.5, 30.5, E); add('transport-belt', 150.5, 30.5, S); beltsy(150.5, 31.5, 45.5, S)
add('transport-belt', 150.5, 46.5, W); belts(149.5, 124.5, 46.5, W)   -- Mid2
for k = 0, 5 do
  local ax = 127.5 + 3 * k
  am('assembling-machine-2', ax, 33.5, 'advanced-circuit')
  add('inserter', ax, 31.5, S); add('inserter', ax - 1, 35.5, S); add('long-handed-inserter', ax, 35.5, S)
  if k % 2 == 0 then add('medium-electric-pole', ax + 1, 35.5) end
end
belts(111.5, 143.5, 36.5, E)  -- Ain1: lane 1 plastic, lane 2 EC
belts(111.5, 143.5, 37.5, E)  -- Ain2: cable

-- CABLE / EC CLUSTER on the spur
am('assembling-machine-2', 112.5, 33.5, 'copper-cable'); am('assembling-machine-2', 116.5, 33.5, 'electronic-circuit')
am('assembling-machine-1', 120.5, 33.5, 'copper-cable'); am('assembling-machine-2', 123.5, 33.5, 'copper-cable')
for _, x in pairs({112.5, 116.5, 120.5, 123.5}) do add('fast-inserter', x, 31.5, N) end
add('fast-inserter', 114.5, 32.5, W); add('fast-inserter', 114.5, 34.5, W)
add('fast-inserter', 118.5, 32.5, E); add('fast-inserter', 118.5, 34.5, E)
add('fast-inserter', 116.5, 35.5, N)                                    -- EC -> Ain1 lane 2
for _, x in pairs({122.5, 123.5, 124.5}) do add('long-handed-inserter', x, 35.5, N) end -- cable -> Ain2

-- PLASTIC (south-facing) and SULFUR (east-facing) plants
add('chemical-plant', 111.5, 40.5, S, {recipe = 'plastic-bar'})
add('long-handed-inserter', 111.5, 38.5, S); add('long-handed-inserter', 112.5, 38.5, S)   -- plastic -> Ain1 lane 1
add('long-handed-inserter', 108.5, 40.5, W)                                                -- coal off the column x=106.5
add('chemical-plant', 146.5, 42.5, E, {recipe = 'sulfur'}); add('inserter', 146.5, 44.5, N)
belts(149.5, 124.5, 45.5, W)  -- sulfur belt

-- PACK ROW (8 AM2) and the pack belt into module 3's pack route (97.5,47.5)
for k = 0, 7 do
  local px = 125.5 + 3 * k
  am('assembling-machine-2', px, 49.5, 'chemical-science-pack')
  add('inserter', px - 1, 47.5, N); add('long-handed-inserter', px, 47.5, N); add('inserter', px, 51.5, N)
  if k % 2 == 0 then add('medium-electric-pole', px + 1, 47.5); add('medium-electric-pole', px + 1, 51.5) end
end
belts(146.5, 110.5, 52.5, W); add('transport-belt', 109.5, 52.5, N); beltsy(109.5, 51.5, 48.5, N)
add('transport-belt', 109.5, 47.5, W); belts(108.5, 98.5, 47.5, W)

-- POLES (west zone and links)
for _, p in pairs({{108.5, 22.5}, {113.5, 20.5}, {119.5, 20.5}, {122.5, 20.5}, {115.5, 27.5}, {114.5, 33.5}, {118.5, 33.5},
  {121.5, 35.5}, {124.5, 31.5}, {116.5, 38.5}, {120.5, 42.5}, {109.5, 41.5}, {144.5, 42.5}, {99.5, 28.5}}) do
  add('medium-electric-pole', p[1], p[2])
end

-- RUNNER
