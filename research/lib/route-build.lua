-- route-build.lua: seat-places the missing boiler-route belts (coal-to-boilers.path) inside a window. Prepend SEAT; builds only tiles within 10 of the seat.
local s = game.surfaces[1]
local segs = {{20.5, -152.5, 20.5, -104.5, 'south'}, {20.5, -103.5, 77.5, -103.5, 'east'}, {78.5, -103.5, 78.5, -72.5, 'south'}}
local ok, bad = 0, {}
local pp = game.get_player(SEAT).position
for _, g in ipairs(segs) do
  local dx = (g[3] > g[1]) and 1 or 0
  local dy = (g[4] > g[2]) and 1 or 0
  local x, y = g[1], g[2]
  while true do
    if (x - pp.x) ^ 2 + (y - pp.y) ^ 2 < 100 and not s.find_entities_filtered{position = {x, y}, radius = 0.3, name = 'transport-belt'}[1] then
      local k, r = pcall(remote.call, 'game_bot', 'build', {seat = SEAT, name = 'transport-belt', x = x, y = y, direction = g[5]})
      if k and type(r) == 'table' and r.built then ok = ok + 1 else bad[#bad + 1] = x .. ',' .. y .. ':' .. (k and serpent.line(r) or tostring(r)):sub(1, 40) end
    end
    if x == g[3] and y == g[4] then break end
    x = x + dx; y = y + dy
  end
end
rcon.print('built ' .. ok .. ' bad ' .. #bad .. ' ' .. table.concat(bad, ' '):sub(1, 400))
