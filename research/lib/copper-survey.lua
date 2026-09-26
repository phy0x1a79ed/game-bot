local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

p('== entities in copper core box (10..26, 51..68) ==')
for _, e in pairs(surf.find_entities_filtered{area={{10,51},{26,68}}, force='player'}) do
  if e.type ~= 'character' then
    p(e.name .. '@' .. string.format('%.1f,%.1f', e.position.x, e.position.y) .. ' dir=' .. tostring(e.direction))
  end
end

p('== candidate cell ore amounts (drill-centre would sit near here) ==')
local candidates = {
  {22,57},{22,60},{22,63},{22,66},
  {14,57},{14,63},{14,66},
  {18,63},{18,66},{12,66},{12,63},
  {24,60},{24,63},{24,66},
}
for _, c in pairs(candidates) do
  local x,y = c[1], c[2]
  local res = surf.find_entities_filtered{area={{x-3,y-3},{x+3,y+3}}, name='copper-ore'}
  local total, n = 0, #res
  for _, r in pairs(res) do total = total + r.amount end
  local free = surf.can_place_entity{name='burner-mining-drill', position={x,y}, direction=defines.direction.east}
  p(string.format('(%d,%d): avg_ore=%s (n=%d) can_place_drill=%s', x, y, n>0 and tostring(math.floor(total/n)) or 'none', n, tostring(free)))
end
rcon.print(table.concat(out, '\n'))
