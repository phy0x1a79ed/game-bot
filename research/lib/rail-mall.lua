-- rail-mall.lua: fill-and-stop rail workshop (stage 1 BOM). Prepend MODE='check'|'place'. Site x 14..35, y -102..-82 north of the base inside R0 cover.
-- Inserter direction = side it picks from. Inputs hand-inserted into the machines (FINDING HAND-FED), intermediates move by inserter chain.
local s = game.surfaces[1]
local N, E, S, W = 0, 4, 8, 12
local L = {}
local function add(n, x, y, d, rec) L[#L + 1] = {n, x, y, d or N, rec} end
local function am(x, y, rec) add('assembling-machine-1', x, y, N, rec) end
local function ins(x, y, pick) add('inserter', x, y, pick) end
-- row A: rails and big poles
add('iron-chest', 14.5, -97.5); ins(15.5, -97.5, W); am(17.5, -97.5, 'iron-stick')
ins(19.5, -97.5, W); am(21.5, -97.5, 'rail')
add('iron-chest', 21.5, -100.5); ins(21.5, -99.5, N)
ins(21.5, -95.5, N); add('iron-chest', 21.5, -94.5)
am(25.5, -97.5, 'iron-stick'); ins(27.5, -97.5, W); am(29.5, -97.5, 'big-electric-pole')
am(29.5, -101.5, 'copper-cable'); ins(29.5, -99.5, N)
-- row B: engines, locomotives, wagons
am(17.5, -88.5, 'iron-gear-wheel'); ins(19.5, -88.5, W); am(21.5, -88.5, 'engine-unit')
am(25.5, -88.5, 'pipe'); ins(23.5, -88.5, E)
ins(21.5, -86.5, N); am(21.5, -84.5, 'locomotive')
am(31.5, -88.5, 'iron-gear-wheel'); ins(31.5, -86.5, N); am(31.5, -84.5, 'cargo-wagon')
local bad, ok, placed = {}, 0, 0
local function spec(e) return {name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player', build_check_type = defines.build_check_type.manual_ghost} end
for _, e in pairs(L) do
  local have = s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.3, name = e[1]}[1] or s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.3, ghost_name = e[1]}[1]
  if have then ok = ok + 1
  elseif not s.can_place_entity(spec(e)) then bad[#bad + 1] = string.format('%s@%.1f,%.1f', e[1], e[2], e[3])
  else ok = ok + 1
    if MODE == 'place' then
      local g = {name = 'entity-ghost', inner_name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player'}
      if e[5] then g.recipe = e[5] end
      if s.create_entity(g) then placed = placed + 1 end
    end
  end
end
-- poles: greedy cover, seeded from a wire chain off (20.5,-68.5)
local occ = {}
for _, e in pairs(L) do
  local hw = (e[1] == 'assembling-machine-1') and 1.5 or 0.5
  for x = math.floor(e[2] - hw + 0.01), math.floor(e[2] + hw - 0.01) do for y = math.floor(e[3] - hw + 0.01), math.floor(e[3] + hw - 0.01) do occ[x .. ',' .. y] = true end end
end
local need = {}
for _, e in pairs(L) do need[#need + 1] = {e[2], e[3], (e[1] == 'assembling-machine-1') and 1.5 or 0.5} end
local poles = {{20.5, -77.5}, {19.5, -82.5}}
local function covered(n) for _, p in ipairs(poles) do if math.abs(p[1] - n[1]) <= 3.5 + n[3] - 0.01 and math.abs(p[2] - n[2]) <= 3.5 + n[3] - 0.01 then return true end end return false end
for iter = 1, 12 do
  local un = {} for _, n in ipairs(need) do if not covered(n) then un[#un + 1] = n end end
  if #un == 0 then break end
  local best, bc
  for x = 12.5, 38.5 do for y = -103.5, -81.5 do
    if not occ[math.floor(x) .. ',' .. math.floor(y)] then
      local near = false for _, p in ipairs(poles) do if (p[1] - x) ^ 2 + (p[2] - y) ^ 2 <= 81 then near = true end end
      if near then local c = 0 for _, n in ipairs(un) do if math.abs(x - n[1]) <= 3.5 + n[3] - 0.01 and math.abs(y - n[2]) <= 3.5 + n[3] - 0.01 then c = c + 1 end end
        if not bc or c > bc then bc = c best = {x, y} end end
    end
  end end
  if not best or bc == 0 then break end
  poles[#poles + 1] = best
end
local pb = {}
for i, p in ipairs(poles) do
  local sp = {name = 'medium-electric-pole', position = p, force = 'player', build_check_type = defines.build_check_type.manual_ghost}
  if not s.can_place_entity(sp) then pb[#pb + 1] = string.format('%.1f,%.1f', p[1], p[2])
  elseif MODE == 'place' then s.create_entity{name = 'entity-ghost', inner_name = 'medium-electric-pole', position = p, force = 'player'} end
end
local un = 0 for _, n in ipairs(need) do if not covered(n) then un = un + 1 end end
local ps = {} for _, p in ipairs(poles) do ps[#ps + 1] = string.format('%.1f,%.1f', p[1], p[2]) end
rcon.print(string.format('rail-mall %s: total %d ok %d placed %d bad %d unpowered %d\nBAD %s\npoles %s badpoles %s', MODE, #L, ok, placed, #bad, un, table.concat(bad, ' '), table.concat(ps, ' '), table.concat(pb, ' ')))
