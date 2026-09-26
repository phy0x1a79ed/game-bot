local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local function probe(x,y) return surf.can_place_entity{name='transport-belt', position={x,y}, direction=defines.direction.west, force='player'} end
local bad = {}
local function check(x,y,label) if not probe(x,y) then bad[#bad+1] = label..' ('..x..','..y..')' end end

-- LEG 1: patch collector, already built live: chain1 tap (79.5,-46.5), chain2 tap (79.5,-38.5)
-- LEG 2: north from chain1 tap to y=-33.5 (13 tiles), well east of ring-1's loop (x=66-74)
for y = -46, -34 do check(79.5, y+0.5, 'leg2') end
-- LEG 3: west along y=-33.5 to x=-20.5 (validated clear corridor, confirmed live this cycle)
for x = -20, 78 do check(x+0.5, -33.5, 'leg3') end
-- LEG 4: north along x=-21.5 from y=-33.5 to y=-6.5 (the untested stretch -- avoids the
-- iron-column's own modules entirely, since the iron column sits at x=-15..-34)
for y = -33, -7 do check(-21.5, y+0.5, 'leg4') end
-- LEG 5: the iron-belt-corner crossing at y=-6.5 (needs pole #2 relocated: -37.5,-6.5 -> elsewhere)
for x = -37, -21 do check(x+0.5, -6.5, 'leg5') end
-- LEG 6: south from the crossing into the power-block pocket via pole #1's gap (-48.5,-13.5 relocated)
for y = -13, -7 do check(-48.5, y+0.5, 'leg6') end
for x = -49, -46 do check(x+0.5, -13.5, 'leg6b') end

p('blocked count: ' .. #bad)
for _, b in pairs(bad) do p('  ' .. b) end
p('(NOTE: leg5 at x=-38 (tile -37.5) is EXPECTED blocked -- that IS pole #2, to be relocated)')
p('(NOTE: leg6b at x=-49 (tile -48.5) is EXPECTED blocked -- that IS pole #1, to be relocated)')
rcon.print(table.concat(out, '\n'))
