-- ops-audit-perimeter.lua (read-only): base-ring cells (10x10, edge of the production footprint in x -150..200, y -130..110) whose nearest gun turret is over 25 tiles away, with enemy corpses within 30 as the raid-direction evidence. Output: "GAP cx,cy side=<N|S|E|W> nearest=<d> corpses=<n>".
local s = game.surfaces[1]
local X0, X1, Y0, Y1, C = -150, 200, -130, 110, 10
local PROD = {'assembling-machine', 'furnace', 'mining-drill', 'lab', 'boiler', 'generator', 'roboport', 'container', 'logistic-container', 'chemical-plant', 'oil-refinery', 'inserter'}
local occ = {}
for _, e in pairs(s.find_entities_filtered{force = 'player', type = PROD, area = {{X0, Y0}, {X1, Y1}}}) do
  occ[math.floor(e.position.x / C) .. ',' .. math.floor(e.position.y / C)] = true
end
local tur = {}
for _, t in pairs(s.find_entities_filtered{force = 'player', name = 'gun-turret', area = {{X0 - 30, Y0 - 30}, {X1 + 30, Y1 + 30}}}) do
  tur[#tur + 1] = t.position
end
local cor = {}
for _, c in pairs(s.find_entities_filtered{type = 'corpse', area = {{X0 - 30, Y0 - 30}, {X1 + 30, Y1 + 30}}}) do
  if c.name:find('biter', 1, true) or c.name:find('spitter', 1, true) then cor[#cor + 1] = c.position end
end
local cx0, cy0 = 20, -10
local out = {'tick ' .. game.tick .. ' turrets=' .. #tur .. ' corpses=' .. #cor}
for k in pairs(occ) do
  local i, j = k:match('(-?%d+),(-?%d+)'); i, j = tonumber(i), tonumber(j)
  local edge = not (occ[(i + 1) .. ',' .. j] and occ[(i - 1) .. ',' .. j] and occ[i .. ',' .. (j + 1)] and occ[i .. ',' .. (j - 1)])
  if edge then
    local px, py = i * C + C / 2, j * C + C / 2
    local best = 1e9
    for _, p in pairs(tur) do local d = (p.x - px) ^ 2 + (p.y - py) ^ 2; if d < best then best = d end end
    best = math.sqrt(best)
    if best > 25 then
      local n = 0
      for _, p in pairs(cor) do if (p.x - px) ^ 2 + (p.y - py) ^ 2 < 900 then n = n + 1 end end
      local dx, dy = px - cx0, py - cy0
      local side = math.abs(dx) > math.abs(dy) and (dx > 0 and 'E' or 'W') or (dy > 0 and 'S' or 'N')
      out[#out + 1] = string.format('GAP %d,%d side=%s nearest=%.0f corpses=%d', px, py, side, best, n)
    end
  end
end
rcon.print(table.concat(out, '\n'))
