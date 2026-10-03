-- rail-signals.lua: fill-and-stop cell for rail-signal, rail-chain-signal and train-stop beside lib/rail-mall.lua. Prepend MODE='check'|'place'.
-- Inputs are hand-inserted (FINDING HAND-FED); rail-signal output feeds the chain-signal machine by inserter. Inserter direction = side it picks from.
local s = game.surfaces[1]
local L = {
  {'assembling-machine-1', 38.5, -97.5, 0, 'rail-signal'},
  {'inserter', 40.5, -97.5, 12},
  {'assembling-machine-1', 42.5, -97.5, 0, 'rail-chain-signal'},
  {'assembling-machine-2', 38.5, -92.5, 0, 'train-stop'},
  {'inserter', 40.5, -92.5, 4},
  {'assembling-machine-1', 42.5, -92.5, 0, 'iron-stick'},
  {'medium-electric-pole', 40.5, -95.5, 0},
  {'medium-electric-pole', 34.5, -92.5, 0},
}
local bad, placed = {}, 0
for _, e in pairs(L) do
  local spec = {name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player', build_check_type = defines.build_check_type.manual_ghost}
  if not s.can_place_entity(spec) then bad[#bad + 1] = e[1] .. '@' .. e[2] .. ',' .. e[3]
  elseif MODE == 'place' then
    local g = {name = 'entity-ghost', inner_name = e[1], position = {e[2], e[3]}, direction = e[4], force = 'player'}
    if e[5] then g.recipe = e[5] end
    if s.create_entity(g) then placed = placed + 1 end
  end
end
rcon.print(MODE .. ' ' .. #L .. ' placed ' .. placed .. ' bad ' .. table.concat(bad, ' '))
