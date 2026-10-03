-- mall-b.lua: M0 bootstrap row south of annex belts G/H (builder1 mall-b, run 4). Prepend MODE='check'|'place', optional PHASE2=true.
-- Row: inserters y=22.5 | AM1 y=23-26 (center 24.5) | out inserters y=26.5 | chests y=27.5. Iron tap: fast inserter (26.5,19.5, filter iron) -> belt S -> sideload onto H north lane.
-- Inserter direction = side it picks from.
local s = game.surfaces[1]
local N, E, S, W = 0, 4, 8, 12
local L = {}
local function add(n, x, y, d, r) L[#L + 1] = {n, x, y, d or N, r} end
-- tap
add('fast-inserter', 26.5, 19.5, N, 'FILTER-iron-plate')
add('transport-belt', 26.5, 20.5, S); add('transport-belt', 26.5, 21.5, W); add('transport-belt', 27.5, 21.5, W)
-- cells
add('assembling-machine-1', -4.5, 24.5, N, 'splitter')
add('assembling-machine-1', 0.5, 24.5, N, 'transport-belt')
add('assembling-machine-1', 4.5, 24.5, N, 'iron-gear-wheel')
add('assembling-machine-1', 8.5, 24.5, N, 'long-handed-inserter')
add('assembling-machine-1', 14.5, 24.5, N, 'chemical-plant')
add('assembling-machine-1', 18.5, 24.5, N, 'pipe')
add('assembling-machine-1', 22.5, 24.5, N, 'pipe-to-ground')
add('assembling-machine-1', 17.5, 28.5, N, 'pump')
-- raw from H (iron; steel for chem)
for _, x in pairs({-4.5, 0.5, 4.5, 8.5, 14.5, 18.5, 22.5}) do add('inserter', x, 22.5, N) end
-- cell to cell
add('inserter', 2.5, 24.5, E); add('inserter', 6.5, 24.5, W); add('inserter', 16.5, 24.5, E); add('inserter', 20.5, 24.5, W)
add('inserter', 17.5, 26.5, N)  -- pipe -> pump
-- chests: LH inputs, LH out, pipe out, splitter out
add('inserter', 7.5, 26.5, S); add('iron-chest', 7.5, 27.5)
add('inserter', 9.5, 26.5, N); add('iron-chest', 9.5, 27.5)
add('inserter', 19.5, 26.5, N); add('iron-chest', 19.5, 27.5)
add('inserter', -4.5, 26.5, N); add('iron-chest', -4.5, 27.5)
-- poles
for _, p in pairs({{-2.5,22.5},{2.5,22.5},{6.5,22.5},{11.5,22.5},{16.5,22.5},{20.5,22.5},{24.5,22.5},{-2.5,26.5},{2.5,26.5},{10.5,26.5},{16.5,26.5}}) do add('medium-electric-pole', p[1], p[2]) end
if PHASE2 then
  add('long-handed-inserter', -3.5, 22.5, N)   -- G -> splitter (EC)
  add('long-handed-inserter', 14.5 - 1, 22.5, N)  -- G -> chem (gear, EC)
  add('long-handed-inserter', -2.5, 23.5, E)   -- belts: belt AM -> splitter AM over the turret
end
local bad, ok, placed = {}, 0, 0
for _, e in pairs(L) do
  local spec = {name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player', build_check_type = defines.build_check_type.manual_ghost}
  local have = s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.3, name = e[1]}[1] or s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.3, ghost_name = e[1]}[1]
  if have then ok = ok + 1
  elseif not s.can_place_entity(spec) then
    local nm = {} for _, x in pairs(s.find_entities_filtered{position = {e[2], e[3]}, radius = 0.45}) do nm[#nm + 1] = x.name end
    bad[#bad + 1] = string.format('%s@%.1f,%.1f[%s]', e[1], e[2], e[3], table.concat(nm, '/'))
  else
    ok = ok + 1
    if MODE == 'place' then
      local gh = s.create_entity{name = 'entity-ghost', inner_name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player'}
      if gh then placed = placed + 1
        if e[5] then
          if e[5]:sub(1, 7) == 'FILTER-' then local okf, err = pcall(function() gh.set_filter(1, e[5]:sub(8)) end) if not okf then bad[#bad + 1] = 'filterfail ' .. tostring(err) end
          else pcall(function() gh.set_recipe(e[5]) end) end
        end
      end
    end
  end
end
rcon.print(string.format('%s: total %d ok %d placed %d bad %d\nBAD %s', MODE, #L, ok, placed, #bad, table.concat(bad, ' ')))
