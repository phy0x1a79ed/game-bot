-- ops-audit-belt-gaps.lua (read-only): one-tile holes in straight belt runs inside x X0_V..X1_V, y -400..300.
-- A hole = a transport belt carrying items with no output neighbour, whose tile 2 ahead holds a belt facing the same way.
-- That pattern is what a removal that took the wrong neighbour leaves behind. Output: "GAP x,y dir=<d> upstream=<items>".
local s = game.surfaces[1]
local D = {[0] = {0, -1}, [4] = {1, 0}, [8] = {0, 1}, [12] = {-1, 0}}
local out = {}
for _, b in pairs(s.find_entities_filtered{type = 'transport-belt', area = {{X0_V, -400}, {X1_V, 300}}}) do
  if #b.belt_neighbours.outputs == 0 then
    local n = b.get_transport_line(1).get_item_count() + b.get_transport_line(2).get_item_count()
    local d = D[b.direction]
    if n > 0 and d then
      local gx, gy = b.position.x + d[1], b.position.y + d[2]
      if s.count_entities_filtered{position = {gx, gy}, radius = 0.4, limit = 1} == 0 then
        local far = s.find_entities_filtered{position = {gx + d[1], gy + d[2]}, radius = 0.4, type = 'transport-belt'}[1]
        if far and far.direction == b.direction then
          out[#out + 1] = string.format('GAP %.1f,%.1f dir=%d upstream=%d', gx, gy, b.direction, n)
        end
      end
    end
  end
end
rcon.print(#out > 0 and table.concat(out, '\n') or 'none')
