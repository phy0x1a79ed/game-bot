-- provider-cell.lua: passive-provider-chest cell beside lib/adv-cell.lua. Prepend MODE='check'|'place'.
-- steel-chest AM1 (steel hand-fed) -> inserter -> adv chest (-6.5,46.5) -> inserter -> provider AM2 <- advanced circuits from the adv cell chest (-6.5,46.5), EC from the extended EC belt y=43.5. Inserter direction = side it picks from.
local s = game.surfaces[1]
local L = {}
for x = -9.5, -4.5 do L[#L + 1] = {'transport-belt', x, 43.5, 12} end
local more = {
  {'fast-inserter', -9.5, 44.5, 0},
  {'assembling-machine-2', -9.5, 46.5, 0, 'passive-provider-chest'},
  {'fast-inserter', -7.5, 46.5, 4},
  {'assembling-machine-1', -6.5, 49.5, 0, 'steel-chest'},
  {'fast-inserter', -6.5, 47.5, 8},
  {'medium-electric-pole', -8.5, 48.5, 0},
  {'fast-inserter', -9.5, 48.5, 0},
  {'iron-chest', -9.5, 49.5, 0},
  {'medium-electric-pole', -11.5, 44.5, 0},
  {'medium-electric-pole', -11.5, 49.5, 0},
}
for _, e in pairs(more) do L[#L + 1] = e end
local bad, placed = {}, 0
for _, e in pairs(L) do
  local spec = {name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player', build_check_type = defines.build_check_type.manual_ghost}
  if not s.can_place_entity(spec) then bad[#bad + 1] = e[1] .. '@' .. e[2] .. ',' .. e[3]
  elseif MODE == 'place' then
    local g = {name = 'entity-ghost', inner_name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player'}
    local gh = s.create_entity(g)
    if gh then placed = placed + 1 if e[5] then pcall(function() gh.set_recipe(e[5]) end) end end
  end
end
rcon.print(MODE .. ' ' .. #L .. ' placed ' .. placed .. ' bad ' .. table.concat(bad, ' '))
