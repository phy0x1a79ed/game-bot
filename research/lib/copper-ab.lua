-- copper-ab.lua: copper patches A (281,-292) and B (336,-327): layout checks (fx builder 1 planner).
-- Prepend PART='survey'|'field'|'fieldA'|'turrets'|'line'|'load'|'unload'|'district' and optionally MODE='check' (default).
-- check = can_place per entity (a read; reports blocked entities, counts, BOM). Nothing is placed.
-- MODE='ghost' AND GHOST_OK=true places entity ghosts for the entities that pass can_place; LO/HI slice the list (budget).
-- Run with lib/copper-ab.sh PART, which sends header + that part + tail (each payload stays under 2 KB compressed).
-- Inserter direction = side it PICKS from (rail-yard.lua convention). Track YT, load stop XL (eastbound), unload stop XU (westbound).
local s = game.surfaces[1]
local N, E, S, W = 0, 4, 8, 12
local YT, XL, XU = -179, 329, 100
local V1, V2 = 334.5, 342.5
local L, info = {}, ''
local function add(n, x, y, d) L[#L + 1] = {n, x, y, d or N} end
local function row(n, x1, x2, y, d, st) for x = x1, x2, st or 1 do add(n, x, y, d) end end
local function col(n, x, y1, y2, d) for y = y1, y2 do add(n, x, y, d) end end
local yN, yS = YT - 4.5, YT + 4.5
-- @PART survey
if PART == 'survey' then
  local function ore(a) local t, n = 0, 0 for _, r in pairs(s.find_entities_filtered{area = a, name = 'copper-ore'}) do t = t + r.amount n = n + 1 end return n .. ' tiles ' .. math.floor(t / 1000) .. 'k' end
  local o = {'A ' .. ore({{255, -320}, {312, -268}}), 'B ' .. ore({{312, -345}, {355, -310}})}
  local e = {}
  for _, c in ipairs({{'A', 281, -292}, {'B', 336, -327}}) do for _, R in ipairs({150, 250}) do
    local u, sp, w = 0, 0, 0
    for _, q in pairs(s.find_entities_filtered{area = {{c[2] - R, c[3] - R}, {c[2] + R, c[3] + R}}, force = 'enemy'}) do
      if (q.position.x - c[2]) ^ 2 + (q.position.y - c[3]) ^ 2 <= R * R then
        if q.type == 'unit' then u = u + 1 elseif q.type == 'unit-spawner' then sp = sp + 1 else w = w + 1 end end end
    e[#e + 1] = string.format('%s r%d units %d spawners %d worms %d', c[1], R, u, sp, w) end end
  local nest = {}
  for _, q in pairs(s.find_entities_filtered{area = {{255, -350}, {300, -310}}, force = 'enemy'}) do if q.type ~= 'unit' then nest[#nest + 1] = string.format('%s(%.0f,%.0f)', q.name:sub(1, 3), q.position.x, q.position.y) end end
  info = table.concat(o, '; ') .. '\n' .. table.concat(e, '; ') .. '\nG-CU ' .. table.concat(nest, ' ')
  rcon.print(game.tick .. ' ' .. info) return
end
-- @PART field
if PART == 'field' then
  -- B field phase 1: belts V1 x=334.5, V2 x=342.5 flowing south; drills each side, pitch 3 in y; poles in the gaps and outside.
  local function ore(x, y) local t = 0 for _, r in pairs(s.find_entities_filtered{area = {{x - 2.5, y - 2.5}, {x + 2.5, y + 2.5}}, name = 'copper-ore'}) do t = t + r.amount end return t end
  local mn, lo = 1e12, {}
  for k = 0, 7 do local y = -338.5 + 3 * k
    for _, d in ipairs({{V1 - 2, E}, {V1 + 2, W}, {V2 - 2, E}, {V2 + 2, W}}) do
      add('electric-mining-drill', d[1], y, d[2]) local o = ore(d[1], y) if o < mn then mn = o end if o < 40000 then lo[#lo + 1] = string.format('%.1f,%.1f=%dk', d[1], y, o / 1000) end end end
  for _, x in ipairs({329.5, 338.5, 347.5}) do for _, y in ipairs({-336.5, -330.5, -324.5, -318.5}) do add('medium-electric-pole', x, y) end end
  col('transport-belt', V1, -340.5, -314.5, S) col('transport-belt', V2, -340.5, -314.5, S)
  local u = 0 for _, r in pairs(s.find_entities_filtered{area = {{330, -342}, {347, -316}}, name = 'copper-ore'}) do u = u + r.amount end
  info = string.format('32 drills (B): min ore under a 5x5 site %dk, unique ore in footprint %dk; thin sites <40k: %s', mn / 1000, u / 1000, table.concat(lo, ' '))
end
-- @PART fieldA
if PART == 'fieldA' then
  -- A field phase 2: belts AV1 x=278.5, AV2 x=286.5 south to rows y=-204.5/-208.5, then east to splitters merging into V1/V2.
  local function ore(x, y) local t = 0 for _, r in pairs(s.find_entities_filtered{area = {{x - 2.5, y - 2.5}, {x + 2.5, y + 2.5}}, name = 'copper-ore'}) do t = t + r.amount end return t end
  local mn = 1e12
  for k = 0, 3 do local y = -296.5 + 3 * k
    for _, d in ipairs({{276.5, E}, {280.5, W}, {284.5, E}, {288.5, W}}) do add('electric-mining-drill', d[1], y, d[2]) local o = ore(d[1], y) if o < mn then mn = o end end end
  for _, x in ipairs({273.5, 282.5, 291.5}) do for _, y in ipairs({-293.5, -287.5}) do add('medium-electric-pole', x, y) end end
  col('transport-belt', 278.5, -298.5, -205.5, S) col('transport-belt', 286.5, -298.5, -209.5, S)
  add('transport-belt', 278.5, -204.5, E) row('transport-belt', 279.5, 332.5, -204.5, E) add('transport-belt', 333.5, -204.5, S) add('transport-belt', 333.5, -203.5, S) add('splitter', 334, -202.5, S)
  add('transport-belt', 286.5, -208.5, E) row('transport-belt', 287.5, 332.5, -208.5, E) add('underground-belt', 333.5, -208.5, E) add('underground-belt', 335.5, -208.5, E)
  row('transport-belt', 336.5, 340.5, -208.5, E) add('transport-belt', 341.5, -208.5, S) add('transport-belt', 341.5, -207.5, S) add('splitter', 342, -206.5, S)
  info = '16 drills (A) min ore under a 5x5 site ' .. math.floor(mn / 1000) .. 'k; AV1 merges into V1 at splitter (334,-202.5), AV2 under V1 by UG then into V2 at splitter (342,-206.5)'
end
-- @PART turrets
if PART == 'turrets' then
  for _, p in ipairs({{322, -340}, {322, -338}, {322, -332}, {322, -330}, {322, -324}, {322, -322}, {322, -316}, {322, -314},
    {331, -345}, {333, -345}, {338, -345}, {340, -345}, {345, -345}, {347, -345},
    {352, -340}, {352, -338}, {352, -333}, {352, -331}, {352, -321}, {352, -319},
    {331, -311}, {333, -311}, {343, -311}, {345, -311},
    {298, -187}, {300, -187}, {318, -187}, {320, -187}}) do add('gun-turret', p[1], p[2]) end
  info = '28 gun turrets: B west 8, north 6, east 6, south 4 (24, placed FIRST), platform north 4 (298..320,-187)'
end
-- @PART line
if PART == 'line' then
  row('straight-rail', 93, 331, YT, E, 2)
  -- V1 and V2 from the field to the platform feeders; V2 jogs west on row y=-196.5 to x=336.5.
  -- The cliff ridge (306,-262) -> (358,-166) crosses x 334..338 at y -198..-190: both belts go under it by underground (gap 4).
  col('transport-belt', V1, -313.5, -198.5, S) add('underground-belt', V1, -197.5, S) add('underground-belt', V1, -192.5, S)
  col('transport-belt', V1, -191.5, -184.5, S) add('transport-belt', V1, -183.5, W)
  col('transport-belt', V2, -313.5, -197.5, S) add('transport-belt', V2, -196.5, W) row('transport-belt', 338.5, 341.5, -196.5, W)
  add('transport-belt', 337.5, -196.5, W) add('transport-belt', 336.5, -196.5, S) add('underground-belt', 336.5, -195.5, S) add('underground-belt', 336.5, -190.5, S)
  col('transport-belt', 336.5, -189.5, -175.5, S) add('transport-belt', 336.5, -174.5, W)
  -- power: medium (331.5,-152.5) -> big pole (333,-153) -> big pole (333,-172) -> platform -> field pole line x=344.5
  add('big-electric-pole', 333, -153) add('big-electric-pole', 333, -172) -- 2 big poles hop the rail corridor y -166..-154 (wire 30)
  for _, p in ipairs({{330.5, -175.5}, {338.5, -176.5}, {344.5, -181.5}}) do add('medium-electric-pole', p[1], p[2]) end
  for k = 1, 14 do add('medium-electric-pole', 344.5, -181.5 - 9 * k) end
  add('medium-electric-pole', 344.5, -312.5)
  info = 'rails x93..331 y=-179 (120); stops Unload Copper Base (100,-181) W and Load Copper N (329,-177) E not testable without rail; V1/V2 from field; pole chain'
end
-- @PART load
if PART == 'load' then
  for _, c in ipairs({XL - 10, XL - 17, XL - 24, XL - 31}) do for i = 0, 5 do local x = c - 2.5 + i
    add('inserter', x, YT - 3.5, N); add('iron-chest', x, YT - 2.5); add('fast-inserter', x, YT - 1.5, N)
    add('inserter', x, YT + 3.5, S); add('iron-chest', x, YT + 2.5); add('fast-inserter', x, YT + 1.5, S)
  end end
  for _, x in ipairs({XL - 6.5, XL - 13.5, XL - 20.5, XL - 27.5, XL - 34.5}) do add('medium-electric-pole', x, YT - 3.5); add('medium-electric-pole', x, YT + 3.5) end
  row('transport-belt', XL - 34.5, V1 - 1, yN, W); row('transport-belt', XL - 34.5, V2 - 7, yS, W)
  info = '48 belt->chest inserters, 48 chests, 48 fast inserters; feeders y=-183.5 (V1) and y=-174.5 (V2)'
end
-- @PART unload
if PART == 'unload' then
  for _, c in ipairs({XU + 10, XU + 17, XU + 24, XU + 31}) do for i = 0, 5 do local x = c - 2.5 + i
    add('fast-inserter', x, YT - 1.5, S); add('iron-chest', x, YT - 2.5); add('inserter', x, YT - 3.5, S)
    add('fast-inserter', x, YT + 1.5, N); add('iron-chest', x, YT + 2.5); add('inserter', x, YT + 3.5, N)
  end end
  for _, x in ipairs({XU + 6.5, XU + 13.5, XU + 20.5, XU + 27.5, XU + 34.5}) do add('medium-electric-pole', x, YT - 3.5); add('medium-electric-pole', x, YT + 3.5) end
  add('long-handed-inserter', XU + 3.5, YT + 2.5, S); add('long-handed-inserter', XU + 36.5, YT - 2.5, N)
  info = '48 fast + 48 chest + 48 inserter, 10 poles; loco fuel: long-handed (103.5,-176.5) from the S ore belt coal lane to the lead loco, long-handed (136.5,-181.5) from the N ore belt coal lane to the tail loco'
end
-- @PART coal
if PART == 'coal' then
  -- coal tap: splitter (110.5,-144) on the boiler coal belt y=-143.5 (a live tile, not testable) -> x=112.5 north under the trunk and the supply line
  -- -> y=-168.5 east -> x=142.5 north under the track -> splitter -> sideloads: N ore belt from the south (south lane), S ore belt from the north (north lane).
  add('transport-belt', 111.5, -144.5, E); col('transport-belt', 112.5, -144.5, -158.5, N)
  add('underground-belt', 112.5, -159.5, N); add('underground-belt', 112.5, -162.5, N); add('underground-belt', 112.5, -163.5, N); add('underground-belt', 112.5, -166.5, N)
  add('transport-belt', 112.5, -167.5, N); add('transport-belt', 112.5, -168.5, E); row('transport-belt', 113.5, 141.5, -168.5, E)
  add('transport-belt', 142.5, -168.5, N); col('transport-belt', 142.5, -169.5, -175.5, N)
  add('underground-belt', 142.5, -176.5, N); add('underground-belt', 142.5, -180.5, N)
  add('transport-belt', 142.5, -181.5, W); add('transport-belt', 141.5, -181.5, W); add('splitter', 140.5, -182, W)
  add('transport-belt', 139.5, -182.5, N); add('transport-belt', 139.5, -181.5, W); add('transport-belt', 138.5, -181.5, W); add('transport-belt', 137.5, -181.5, S)
  add('underground-belt', 137.5, -180.5, S); add('underground-belt', 137.5, -175.5, S)
  info = 'coal tap to both ore belt heads (~65 coal/min); N dummy head (140.5,-183.5) is part of the N ore row, S dummy head (138.5,-174.5) is the S ore row head'
end
-- @PART district
if PART == 'district' then
  -- ore belts flow WEST from the heads (x=137.5 N, 138.5 S) past 24 steel furnaces per row (x 105..59, pitch 2); plate belts y=-188.5 / -169.5 flow west to the mains x=0.5 / 1.5.
  row('transport-belt', 56.5, 140.5, yN, W); row('transport-belt', 56.5, 138.5, yS, W)
  for i = 0, 23 do local fx = 105 - 2 * i
    add('steel-furnace', fx, yN - 2.5); add('inserter', fx - 0.5, yN - 1, S); add('inserter', fx - 0.5, yN - 4, S)
    add('steel-furnace', fx, yS + 2.5); add('inserter', fx - 0.5, yS + 1, N); add('inserter', fx - 0.5, yS + 4, N)
    if i % 3 == 1 then add('medium-electric-pole', fx + 0.5, yN - 1); add('medium-electric-pole', fx + 0.5, yS + 1) end
  end
  add('big-electric-pole', 54, -156) add('big-electric-pole', 54, -172) -- hop the corridor from the yard pole (49.5,-156.5) to the S district poles
  row('transport-belt', 1.5, 105.5, yN - 5, W); add('transport-belt', 0.5, yN - 5, S); col('transport-belt', 0.5, yN - 4, -52.5, S)
  row('transport-belt', 2.5, 105.5, yS + 5, W); add('transport-belt', 1.5, yS + 5, S); col('transport-belt', 1.5, yS + 6, -52.5, S)
  info = '48 furnaces x 59..105; yellow plate belts to the terminals (0.5,-52.5) and (1.5,-52.5); coal head lanes and the join to the copper main (-0.5,-49.5) are not in this check'
end
-- @TAIL
local bad, ok, bom = {}, 0, {}
local lo, hi = LO or 1, HI or #L
local ghost = (MODE == 'ghost' and GHOST_OK == true)
for i = lo, math.min(hi, #L) do local e = L[i]
  bom[e[1]] = (bom[e[1]] or 0) + 1
  local spec = {name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player', build_check_type = defines.build_check_type.manual_ghost}
  if s.can_place_entity(spec) then ok = ok + 1
    if ghost then s.create_entity{name = 'entity-ghost', inner_name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player'} end
  else
    local nm = {} for _, q in pairs(s.find_entities_filtered{area = {{e[2] - 0.9, e[3] - 0.9}, {e[2] + 0.9, e[3] + 0.9}}}) do if q.type ~= 'resource' then nm[#nm + 1] = q.name end end
    bad[#bad + 1] = string.format('%s@%.1f,%.1f[%s]', e[1], e[2], e[3], table.concat(nm, '/'))
  end
end
local b = {} for k, v in pairs(bom) do b[#b + 1] = k .. '=' .. v end table.sort(b)
rcon.print(string.format('tick %d %s%s: total %d ok %d bad %d | %s\n%s\nBAD %s', game.tick, PART, ghost and ' GHOSTED' or '', #L, ok, #bad, table.concat(b, ','), info, table.concat(bad, ' ', 1, math.min(#bad, 30))))
