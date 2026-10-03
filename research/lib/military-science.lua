-- military-science.lua: ghost layout of the 60 packs/min military science block at site N (x 16..48, y -70..-38), see crew/council/military-science.md.
-- MODE='check'   : can_place, self-overlap, power coverage and pole connectivity (a read; the generic power check is replaced by the one after RUNNER).
-- MODE='place'   : create the ghosts (a Lua order; robots build them). Idempotent.
-- MODE='recipes' : set the recipe on every built machine of the layout that lacks it (a setting).
-- STAGE tags: 1 = piercing copper+steel feed, 2 = yellow + piercing, 3 = grenades, 4 = packs, 5 = walls and outputs. Set STAGES below to place a subset.
local MODE = MODE_ARG
local s = game.surfaces[1]
local N, E, S, W = defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west
local L = {}
local STAGE = 1
local STAGES = {[3]=true,[4]=true,[5]=true}
local function add(name, x, y, dir, extra) L[#L + 1] = {name = name, x = x, y = y, dir = dir or N, extra = extra, stage = STAGE} end
local function belts(x0, x1, y, dir) local st = x0 <= x1 and 1 or -1 for x = x0, x1, st do add('transport-belt', x, y, dir) end end
local function beltsy(x, y0, y1, dir) local st = y0 <= y1 and 1 or -1 for y = y0, y1, st do add('transport-belt', x, y, dir) end end
local function ug(x, y, dir, t) add('underground-belt', x, y, dir, {type = t}) end
local function am(x, y, recipe) add('assembling-machine-2', x, y, N, {recipe = recipe}) end
local function pole(x, y) add('medium-electric-pole', x, y) end

-- STAGE 1: the copper feed (tap (-15.5,-4.5) -> side-load (17.5,-38.5) W into (16.5,-38.5)) is built by redesign-a, not in this file
-- STAGE 1: copper+steel feed. Entry (16.5,-37.5) is iron3's steel column end (steel lane + copper lane). FC runs north on x=16.5, then east on y=-49.5.
STAGE = 1
beltsy(16.5, -39.5, -48.5, N)
add('transport-belt', 16.5, -49.5, E); belts(17.5, 31.5, -49.5, E)
-- iron for the yellow machines: iron3 delivers (15.5,-45.5) north, under FC, then east on y=-48.5
ug(15.5, -46.5, E, 'input'); ug(17.5, -46.5, E, 'output')
add('transport-belt', 18.5, -46.5, N); add('transport-belt', 18.5, -47.5, N); add('transport-belt', 18.5, -48.5, E); belts(19.5, 28.5, -48.5, E)
-- piercing row A y=-52.5 (30/min to the packs): P1 19.5, Y1 23.5, P2 27.5. Row B y=-45.5 (30/min to the old wall belt, capsule cell, turrets): P3 22.5, Y2 26.5, P4 30.5
STAGE = 2
am(19.5, -52.5, 'piercing-rounds-magazine'); am(27.5, -52.5, 'piercing-rounds-magazine'); am(23.5, -52.5, 'firearm-magazine')
am(22.5, -45.5, 'piercing-rounds-magazine'); am(30.5, -45.5, 'piercing-rounds-magazine'); am(26.5, -45.5, 'firearm-magazine')
for _, x in pairs({19.5, 27.5}) do add('inserter', x, -50.5, S); end
for _, x in pairs({22.5, 24.5}) do add('long-handed-inserter', x, -50.5, S) end
for _, x in pairs({21.5, 22.5, 23.5, 29.5, 30.5, 31.5}) do add('long-handed-inserter', x, -47.5, N) end
for _, x in pairs({25.5, 27.5}) do add('inserter', x, -47.5, N) end; add('fast-inserter', 26.5, -47.5, N)
add('inserter', 21.5, -52.5, E); add('inserter', 25.5, -52.5, W); add('inserter', 24.5, -45.5, E); add('inserter', 28.5, -45.5, W)
for _, x in pairs({22.5, 30.5}) do add('inserter', x, -43.5, N) end
belts(22.5, 37.5, -42.5, E)
add('inserter', 19.5, -54.5, S); add('inserter', 27.5, -54.5, S)
belts(27.5, 17.5, -55.5, W); add('transport-belt', 16.5, -55.5, N); beltsy(16.5, -56.5, -63.5, N)
add('transport-belt', 16.5, -64.5, E); add('transport-belt', 17.5, -64.5, E); add('transport-belt', 18.5, -64.5, S)
add('transport-belt', 38.5, -42.5, S)
add('transport-belt', 38.5, -41.5, E); add('transport-belt', 39.5, -41.5, S)
add('transport-belt', 39.5, -40.5, E); add('transport-belt', 40.5, -40.5, E)
-- STAGE 3: grenade row y=-66.5, x 19.5..34.5; IC (iron lane, coal lane) entry (17.5,-69.5)
STAGE = 3
belts(17.5, 35.5, -69.5, E)
for k = 0, 5 do local x = 19.5 + 3 * k
  am(x, -66.5, 'grenade'); add('fast-inserter', x, -68.5, N); add('inserter', x, -64.5, N)
end
belts(17.5, 37.5, -63.5, E)
-- STAGE 4: pack row y=-60.5, x 19.5..37.5; GO feeds from y=-63.5; W walls y=-56.5 (flows west), PO packs y=-57.5 (flows east)
STAGE = 4
for k = 0, 6 do local x = 19.5 + 3 * k
  am(x, -60.5, 'military-science-pack'); add('inserter', x, -62.5, N)
  add('inserter', x - 1, -58.5, N); add('long-handed-inserter', x, -58.5, S)
end
belts(19.5, 40.5, -57.5, E)
-- STAGE 5: walls and outputs
STAGE = 5
add('inserter', 40.5, -45.5, S); beltsy(40.5, -46.5, -55.5, N); add('transport-belt', 40.5, -56.5, W); belts(39.5, 19.5, -56.5, W)
-- pack output PO: y=-57.5 east to x=41.5, then belt-path.lua route (east on y=-53.5, south on x=85.5, west on y=-3.5) into redesign-b's military branch at (59.5,-3.5)
beltsy(41.5, -57.5, -54.5, S)
belts(41.5, 53.5, -53.5, E)
ug(54.5, -53.5, E, 'input')
ug(59.5, -53.5, E, 'output')
belts(60.5, 61.5, -53.5, E)
ug(62.5, -53.5, E, 'input')
ug(67.5, -53.5, E, 'output')
belts(68.5, 84.5, -53.5, E)
beltsy(85.5, -53.5, -51.5, S)
ug(85.5, -50.5, S, 'input')
ug(85.5, -45.5, S, 'output')
beltsy(85.5, -44.5, -26.5, S)
ug(85.5, -25.5, S, 'input')
ug(85.5, -20.5, S, 'output')
beltsy(85.5, -19.5, -4.5, S)
belts(85.5, 60.5, -3.5, W)
-- POLES
STAGE = 1
pole(39.5, -46.5); pole(34.5, -46.5); pole(25.5, -54.5)
for _, x in pairs({21.5, 29.5}) do pole(x, -50.5); pole(x, -54.5) end
for _, q in pairs({{24.5, -47.5}, {28.5, -47.5}, {24.5, -43.5}, {28.5, -43.5}}) do pole(q[1], q[2]) end
for _, x in pairs({20.5, 26.5, 32.5}) do pole(x, -68.5); pole(x, -64.5) end
for _, x in pairs({20.5, 26.5, 32.5, 38.5}) do pole(x, -58.5) end
pole(38.5, -62.5)

-- self-contained runner and power check follow (this file has no shared-runner marker, so redesign-ghosts.sh runs it as is)
if MODE == 'check' then
  local poles, unp, disc = {}, {}, {}
  for _, e in pairs(L) do if e.name == 'medium-electric-pole' then poles[#poles + 1] = {x = e.x, y = e.y, new = true} end end
  for _, p in pairs(s.find_entities_filtered{type = 'electric-pole', area = {{-25, -75}, {62, 12}}}) do
    if p.electric_network_id then poles[#poles + 1] = {x = p.position.x, y = p.position.y, new = false, sup = p.prototype.get_supply_area_distance(), wire = p.prototype.get_max_wire_distance()} end end
  local half = {['assembling-machine-2'] = 1.5, inserter = 0.15, ['fast-inserter'] = 0.15, ['long-handed-inserter'] = 0.15}
  for _, e in pairs(L) do local h = half[e.name] if h then local cov = false
    for _, p in pairs(poles) do local d = p.sup or 3.5 if math.abs(e.x - p.x) < d + h and math.abs(e.y - p.y) < d + h then cov = true break end end
    if not cov then unp[#unp + 1] = string.format('%s(%.1f,%.1f)', e.name, e.x, e.y) end end end
  local reach, fr = {}, {}
  for i, p in pairs(poles) do if not p.new then reach[i] = true fr[#fr + 1] = i end end
  while #fr > 0 do local i = table.remove(fr) for j, q in pairs(poles) do if not reach[j] then
    local w = math.min(poles[i].wire or 9, q.wire or 9) if (poles[i].x - q.x) ^ 2 + (poles[i].y - q.y) ^ 2 <= w * w then reach[j] = true fr[#fr + 1] = j end end end end
  for i, p in pairs(poles) do if not reach[i] then disc[#disc + 1] = string.format('(%.1f,%.1f)', p.x, p.y) end end
  local occ, dup, size = {}, {}, {['assembling-machine-2'] = 3}
  for _, e in pairs(L) do local w = size[e.name] or 1 local x0, y0 = math.floor(e.x - w / 2 + 0.01), math.floor(e.y - w / 2 + 0.01)
    for i = 0, w - 1 do for j = 0, w - 1 do local k = (x0 + i) .. ',' .. (y0 + j) if occ[k] then dup[#dup + 1] = e.name .. '@' .. k .. '/' .. occ[k] else occ[k] = e.name end end end end
  rcon.print('MY self-overlaps=' .. #dup .. ' ' .. table.concat(dup, ' '))
  rcon.print('MY unpowered=' .. #unp .. ' ' .. table.concat(unp, ' '))
  rcon.print('MY disconnected poles=' .. #disc .. ' ' .. table.concat(disc, ' '))
end
local out = {}
local function exists(e)
  return s.find_entities_filtered{position = {e.x, e.y}, radius = 0.3, name = e.name}[1]
      or s.find_entities_filtered{position = {e.x, e.y}, radius = 0.3, ghost_name = e.name}[1]
end
if MODE == 'recipes' then
  local set = 0
  for _, e in pairs(L) do if e.extra and e.extra.recipe then
    local m = s.find_entities_filtered{position = {e.x, e.y}, radius = 0.3, name = e.name}[1]
    if m and (not m.get_recipe() or m.get_recipe().name ~= e.extra.recipe) then m.set_recipe(e.extra.recipe) set = set + 1 end
  end end
  rcon.print('recipes set=' .. set) return
end
local cnt, bad, ok, skip, placed, fail = {}, {}, 0, 0, 0, {}
for _, e in pairs(L) do
  cnt[e.name] = (cnt[e.name] or 0) + 1
  if exists(e) then skip = skip + 1
  else
    local p = {name = e.name, position = {e.x, e.y}, direction = e.dir, force = 'player', build_check_type = defines.build_check_type.manual_ghost}
    if e.extra and e.extra.type then p.type = e.extra.type end
    if s.can_place_entity(p) then
      ok = ok + 1
      if MODE == 'place' and (not STAGES or STAGES[e.stage]) then
        local c = {name = 'entity-ghost', inner_name = e.name, position = {e.x, e.y}, direction = e.dir, force = 'player'}
        if e.extra and e.extra.type then c.type = e.extra.type end
        if e.extra and e.extra.recipe then c.recipe = e.extra.recipe end
        local g = s.create_entity(c)
        if g then placed = placed + 1 else fail[#fail + 1] = string.format('%s(%.1f,%.1f)', e.name, e.x, e.y) end
      end
    else bad[#bad + 1] = string.format('%s(%.1f,%.1f)', e.name, e.x, e.y) end
  end
end
local c = {} for k, v in pairs(cnt) do c[#c + 1] = k .. '=' .. v end
table.sort(c)
rcon.print(string.format('mode=%s total=%d ok=%d skip=%d placed=%d bad=%d %s | fail=%s | %s', MODE, #L, ok, skip, placed, #bad, table.concat(bad, ' '), table.concat(fail, ' '), table.concat(c, ',')))
