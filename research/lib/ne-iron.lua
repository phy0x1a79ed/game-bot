-- ne-iron.lua: NE iron layout checks (fx builder 1 planner). Prepend MODE='check' and PART='line'|'unload'|'district'|'coal'|'load'|'field'|'turrets'|'power'.
-- check = can_place per entity (a read; reports blocked entities, counts, BOM). Nothing is placed. Inserter direction = side it PICKS from (rail-yard.lua convention).
-- Track y=YT for the whole line; every stack is offset from YT: fast inserter YT+-1.5, chest +-2.5, belt inserter +-3.5, belt +-4.5.
local s = game.surfaces[1]
local N, E, S, W = 0, 4, 8, 12
local YT = -131
local L = {}
local function add(n, x, y, d) L[#L + 1] = {n, x, y, d or N} end
local function row(n, x1, x2, y, d, step) for x = x1, x2, step or 1 do add(n, x, y, d) end end
local function col(n, x, y1, y2, d) for y = y1, y2 do add(n, x, y, d) end end
local info = ''
local WAG_B = {50, 57, 64, 71}
local WAG_P = {501, 494, 487, 480}
local yN, yS = YT - 4.5, YT + 4.5
if PART == 'line' then
  row('straight-rail', 33, 513, YT, E, 2)
  info = 'track y=-131 x 33..513 (241 rails); stops Unload Iron Base (40,-133) W and Load Iron E (511,-129) E are not testable without rail'
elseif PART == 'unload' then
  for _, c in ipairs(WAG_B) do for i = 0, 5 do local x = c - 2.5 + i
    add('fast-inserter', x, YT - 1.5, S); add('iron-chest', x, YT - 2.5); add('inserter', x, YT - 3.5, S)
    add('fast-inserter', x, YT + 1.5, N); add('iron-chest', x, YT + 2.5); add('inserter', x, YT + 3.5, N)
  end end
  for _, x in ipairs({46.5, 53.5, 60.5, 67.5, 74.5}) do add('medium-electric-pole', x, YT - 3.5); add('medium-electric-pole', x, YT + 3.5) end
  add('inserter', 43.5, YT + 1.5, S); add('long-handed-inserter', 78.5, YT - 2.5, N)
  info = '48 fast + 48 chest + 48 inserter, 10 poles, loco fuel: inserter (43.5,YT+1.5) from coal row y=YT+2.5, long-handed (78.5,YT-2.5) from ore belt N coal lane'
elseif PART == 'district' then
  row('fast-transport-belt', 44.5, 115.5, yN, E); row('fast-transport-belt', 44.5, 115.5, yS, E)
  for i = 0, 19 do local fx = 76 + 2 * i
    add('steel-furnace', fx, yN - 2.5); add('inserter', fx - 0.5, yN - 1, S); add('inserter', fx - 0.5, yN - 4, S)
    add('steel-furnace', fx, yS + 2.5); add('inserter', fx - 0.5, yS + 1, N); add('inserter', fx - 0.5, yS + 4, N)
    if i % 3 == 1 then add('medium-electric-pole', fx + 0.5, yN - 1); add('medium-electric-pole', fx + 0.5, yS + 1) end
  end
  local pN, pS = yN - 5, yS + 5
  row('fast-transport-belt', 22.5, 114.5, pN, W); add('fast-underground-belt', 21.5, pN, W); add('fast-underground-belt', 19.5, pN, W); row('fast-transport-belt', 10.5, 18.5, pN, W)
  row('fast-transport-belt', 28.5, 114.5, pS, W); add('fast-underground-belt', 27.5, pS, W); add('fast-underground-belt', 23.5, pS, W); add('fast-transport-belt', 22.5, pS, W)
  add('fast-underground-belt', 21.5, pS, W); add('fast-underground-belt', 19.5, pS, W); row('fast-transport-belt', 10.5, 18.5, pS, W)
  add('fast-transport-belt', 9.5, pN, S); col('fast-transport-belt', 9.5, pN + 1, -75.5, S)
  info = '2 x 20 furnaces x 76..114; ore belts y=yN/yS from x=44.5; plate belts y=pN/pS flow W to Plate Main E x=9.5 (UG under x=20.5 and the coal columns)'
elseif PART == 'coal' then
  add('splitter', 24.5, -104, E)
  add('transport-belt', 25.5, -104.5, N); col('transport-belt', 25.5, -109.5, -105.5, N)
  add('splitter', 26, -110.5, N)
  for y = -111.5, yN + 2, -1 do add('transport-belt', 25.5, y, N) end
  row('transport-belt', 25.5, 44.5, yN + 1, E); add('transport-belt', 45.5, yN + 1, N)
  for y = -111.5, yS - 1, -1 do add('transport-belt', 26.5, y, N) end
  row('transport-belt', 26.5, 44.5, yS - 2, E); add('transport-belt', 45.5, yS - 2, S); add('transport-belt', 45.5, yS - 1, S)
  info = 'coal tap splitter (24.5,-104) on the boiler route; column splitter (26,-110.5); N coal row y=yN+1 (-134.5), S coal row y=yS-2 (-128.5); both sideload the ore belt heads at x=45.5'
elseif PART == 'load' then
  for _, c in ipairs(WAG_P) do for i = 0, 5 do local x = c - 2.5 + i
    add('inserter', x, YT - 3.5, N); add('iron-chest', x, YT - 2.5); add('fast-inserter', x, YT - 1.5, N)
    add('inserter', x, YT + 3.5, S); add('iron-chest', x, YT + 2.5); add('fast-inserter', x, YT + 1.5, S)
  end end
  for _, x in ipairs({504.5, 497.5, 490.5, 483.5, 476.5}) do add('medium-electric-pole', x, YT - 3.5); add('medium-electric-pole', x, YT + 3.5) end
  row('transport-belt', 476.5, 516.5, yN, W); row('transport-belt', 476.5, 518.5, yS, W)
  info = '48 belt->chest inserters, 48 chests, 48 fast; feeders y=yN (row A) and y=yS (row B)'
elseif PART == 'field' then
  local function ore(x, y) local t = 0 for _, r in pairs(s.find_entities_filtered{area = {{x - 2.5, y - 2.5}, {x + 2.5, y + 2.5}}, name = 'iron-ore'}) do t = t + r.amount end return t end
  local mn, tot, lo = 1e12, 0, {}
  for k = 0, 9 do local x = 520.5 + 3 * k
    for _, d in ipairs({{-140.5, S}, {-136.5, N}, {-132.5, S}, {-128.5, N}}) do
      add('electric-mining-drill', x, d[1], d[2]) local o = ore(x, d[1]) tot = tot + o if o < mn then mn = o end if o < 40000 then lo[#lo + 1] = string.format('%.1f,%.1f=%dk', x, d[1], o / 1000) end end
  end
  for j = 0, 4 do local x = 521.5 + 7 * j for _, y in ipairs({-142.5, -134.5, -126.5}) do add('medium-electric-pole', x, y) end end
  row('transport-belt', 517.5, 548.5, -138.5, W); add('transport-belt', 516.5, -138.5, S); for y = -137.5, yN - 1, 1 do add('transport-belt', 516.5, y, S) end
  add('transport-belt', 516.5, yN, W)
  row('transport-belt', 519.5, 548.5, -130.5, W); add('transport-belt', 518.5, -130.5, S); for y = -129.5, yS - 1, 1 do add('transport-belt', 518.5, y, S) end
  add('transport-belt', 518.5, yS, W)
  info = string.format('40 drills: min ore under a 5x5 site %dk, sum %dk (sites overlap, so a double count); thin sites <40k: %s', mn / 1000, tot / 1000, table.concat(lo, ' '))
elseif PART == 'turrets' then
  for _, p in ipairs({{521,-118},{523,-118},{533,-118},{535,-118},{545,-118},{547,-118},{554,-118},{556,-118},
    {556,-143},{556,-141},{556,-134},{556,-132},{556,-125},{556,-123},{527,-148},{529,-148},{543,-148},{545,-148},
    {480,-120},{482,-120},{496,-120},{498,-120},{470,-135},{470,-137}}) do add('gun-turret', p[1], p[2]) end
  info = '24 gun turrets: S face 6, SE corner 2, E face 6, N face 4, platform S 4, platform W 2'
elseif PART == 'power' then
  for _, p in ipairs({{484.5,-143.5},{484.5,-136.5},{513.5,-137.5},{506.5,-141.5}}) do add('medium-electric-pole', p[1], p[2]) end
  for _, p in ipairs({{49.5,-148.5},{49.5,-143.5},{46.5,-139.5}}) do add('medium-electric-pole', p[1], p[2]) end
  info = 'feeder poles: yard grid -> base platform; FO (484.5,-150.5) -> patch platform -> field'
end
local bad, ok, bom = {}, 0, {}
for _, e in ipairs(L) do
  bom[e[1]] = (bom[e[1]] or 0) + 1
  local spec = {name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player', build_check_type = defines.build_check_type.manual_ghost}
  if s.can_place_entity(spec) then ok = ok + 1
  else
    local b = s.find_entities_filtered{area = {{e[2] - 0.9, e[3] - 0.9}, {e[2] + 0.9, e[3] + 0.9}}}
    local nm = {} for _, q in pairs(b) do if q.type ~= 'resource' then nm[#nm + 1] = q.name end end
    bad[#bad + 1] = string.format('%s@%.1f,%.1f[%s]', e[1], e[2], e[3], table.concat(nm, '/'))
  end
end
local b = {} for k, v in pairs(bom) do b[#b + 1] = k .. '=' .. v end table.sort(b)
rcon.print(string.format('tick %d %s: total %d ok %d bad %d | %s\n%s\nBAD %s', game.tick, PART, #L, ok, #bad, table.concat(b, ','), info, table.concat(bad, ' ', 1, math.min(#bad, 30))))
