local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

local function probe(x, y, dir)
  return surf.can_place_entity{name='transport-belt', position={x,y}, direction=dir or defines.direction.west, force='player'}
end
local function probe_named(name, x, y, dir)
  return surf.can_place_entity{name=name, position={x,y}, direction=dir or defines.direction.north, force='player'}
end

local bad = {}
local function check(x,y,label)
  if not probe(x,y) then bad[#bad+1] = label .. ' (' .. x .. ',' .. y .. ')' end
end

-- FULL ROUTE, corrected:
-- (a) west along y=-46.5 for the two feeder-chain taps merge (near patch) -- checked separately, patch-local
-- (b) west along y=-33.5 from x=78.5 down to x=-20.5 (stop 1 tile short of iron-belt col at -19.5)
for x = -20, 78 do check(x+0.5, -33.5, 'seg-b') end
-- (c) north along x=-21.5 from y=-33.5 to y=-21.5
for y = -33, -21 do check(-21.5, y+0.5, 'seg-c') end
-- (d) west along y=-21.5 from x=-21.5 to x=-58.5
for x = -58, -21 do check(x+0.5, -21.5, 'seg-d') end
-- (e) north along x=-58.5 from y=-21.5 to y=-14.5
for y = -21, -14 do check(-58.5, y+0.5, 'seg-e') end
-- (f) east along y=-14.5 from x=-58.5 to x=-49.5
for x = -58, -49 do check(x+0.5, -14.5, 'seg-f') end
-- (g) north along x=-49.5 from y=-14.5 to y=-10.5
for y = -14, -10 do check(-49.5, y+0.5, 'seg-g') end
-- (h) final tiles near the chest: belt (-49.5,-9.5), inserter tile (-48.5,-9.5) [not a belt, checked separately]
check(-49.5, -9.5, 'seg-h-belt')

p('blocked count: ' .. #bad)
for _, b in pairs(bad) do p('  ' .. b) end

-- inserter + chest feasibility at the hand-off
local ins_ok_electric = probe_named('inserter', -48.5, -9.5, defines.direction.east)
local ins_ok_burner = probe_named('burner-inserter', -48.5, -9.5, defines.direction.east)
p('electric inserter placeable at (-48.5,-9.5) dir=east(pickup west/belt, drop east/chest): ' .. tostring(ins_ok_electric))
p('burner inserter placeable at same spot: ' .. tostring(ins_ok_burner))

-- power reach: find nearest pole and its supply area vs (-48.5,-9.5)
local poles = surf.find_entities_filtered{name={'small-electric-pole','medium-electric-pole','big-electric-pole'}, position={-48.5,-9.5}, radius=12}
p('poles within 12 of (-48.5,-9.5): ' .. #poles)
for _, pole in pairs(poles) do
  local d = ((pole.position.x+48.5)^2 + (pole.position.y+9.5)^2)^0.5
  local ok1, sad = pcall(function() return pole.prototype.supply_area_distance end)
  p(string.format('  %s @ %.1f,%.1f dist=%.2f supply_radius=%s', pole.name, pole.position.x, pole.position.y, d, tostring(ok1 and sad or 'n/a')))
end

rcon.print(table.concat(out, '\n'))
