local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

-- where exactly is the water near the power block? and what's west of the poles?
local box = {{-70,-20},{-45,0}}
local water_tiles = surf.find_tiles_filtered{area=box, name={'water','deepwater','water-green','water-shallow','water-mud'}}
local minx, maxx, miny, maxy = 1e9,-1e9,1e9,-1e9
for _, t in pairs(water_tiles) do
  minx = math.min(minx, t.position.x); maxx = math.max(maxx, t.position.x)
  miny = math.min(miny, t.position.y); maxy = math.max(maxy, t.position.y)
end
p('water tiles in (-70,-20)-(-45,0): ' .. #water_tiles .. ' bbox=(' .. minx .. ',' .. miny .. ')-(' .. maxx .. ',' .. maxy .. ')')

-- any player entities west of the power block, and along a y=-20 west corridor
local ents = surf.find_entities_filtered{area=box, force='player'}
p('player entities in that box: ' .. #ents)
for _, e in pairs(ents) do
  p(string.format('  %-22s @ %6.1f,%6.1f dir=%s', e.name, e.position.x, e.position.y, tostring(e.direction)))
end

-- can_place_entity probe along a candidate belt path, all in one call
-- Path: (a) west along y=-33.5 from x=78.5 to x=-21.5
--       (b) north along x=-21.5 from y=-33.5 to y=-20.5
--       (c) west along y=-20.5 from x=-21.5 to x=-58.5
--       (d) north along x=-58.5 from y=-20.5 to y=-8.5
--       (e) east along y=-8.5-ish into the feed chest area (checked separately once (d) is confirmed clear)
local function probe(x, y)
  local ok = surf.can_place_entity{name='transport-belt', position={x,y}, direction=defines.direction.west, force='player'}
  return ok
end
local bad = {}
-- (a)
for x = -21, 78, 1 do
  local xx = x + 0.5
  if not probe(xx, -33.5) then bad[#bad+1] = string.format('(%.1f,-33.5)', xx) end
end
-- (b)
for y = -33, -21, 1 do
  local yy = y + 0.5
  if not probe(-21.5, yy) then bad[#bad+1] = string.format('(-21.5,%.1f)', yy) end
end
-- (c)
for x = -58, -21, 1 do
  local xx = x + 0.5
  if not probe(xx, -20.5) then bad[#bad+1] = string.format('(%.1f,-20.5)', xx) end
end
-- (d)
for y = -20, -9, 1 do
  local yy = y + 0.5
  if not probe(-58.5, yy) then bad[#bad+1] = string.format('(-58.5,%.1f)', yy) end
end
p('blocked tiles along candidate route a-b-c-d: ' .. #bad)
for _, b in pairs(bad) do p('  BLOCKED ' .. b) end

rcon.print(table.concat(out, '\n'))
