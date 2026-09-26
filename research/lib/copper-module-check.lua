local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

-- module shape (matches modules 3/4/5): drill(x,y) east, furnace(x+2,y),
-- inserter(x+2.5,y+1.5) dir=north (pickup furnace, drop south), chest(x+2.5,y+2.5)
local candidates = {
  {22,63},{24,63},{18,66},{22,66},{14,66},{24,66},{12,63},{18,63},{24,60},
}

for _, c in pairs(candidates) do
  local x,y = c[1], c[2]
  local dpos = {x,y}
  local fpos = {x+2,y}
  local ipos = {x+2.5,y+1.5}
  local cpos = {x+2.5,y+2.5}
  local ok_d = surf.can_place_entity{name='burner-mining-drill', position=dpos, direction=defines.direction.east}
  local ok_f = surf.can_place_entity{name='stone-furnace', position=fpos}
  local ok_i = surf.can_place_entity{name='burner-inserter', position=ipos, direction=defines.direction.north}
  local ok_c = surf.can_place_entity{name='iron-chest', position=cpos}
  local res = surf.find_entities_filtered{area={{x-2,y-2},{x+4,y+2}}, name='copper-ore'}
  local total = 0
  for _, r in pairs(res) do total = total + r.amount end
  local avg = #res > 0 and math.floor(total/#res) or -1
  p(string.format('drill(%d,%d)/furnace(%d,%d): drill=%s furnace=%s inserter=%s chest=%s avg_ore=%d (n=%d)',
    x, y, x+2, y, tostring(ok_d), tostring(ok_f), tostring(ok_i), tostring(ok_c), avg, #res))
end
rcon.print(table.concat(out, '\n'))
