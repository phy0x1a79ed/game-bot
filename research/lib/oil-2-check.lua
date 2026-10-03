-- oil-2-check.lua: copy of prod-30-check.lua with the oil-refinery footprint (5x5) and a live fluid-join read: every planned pipe or pipe-to-ground that touches an existing pipe reports the fluid that pipe holds.
do
  -- power coverage and pole connectivity (medium pole: supply 3.5, wire 9)
  local poles = {}
  local okA, AR = pcall(function() return AREA end)
  for _, e in pairs(L) do if e.name == 'medium-electric-pole' then poles[#poles + 1] = {x = e.x, y = e.y, new = true} end end
  for _, p in pairs(s.find_entities_filtered{type = 'electric-pole', area = (okA and AR) or {{58, -20}, {170, 34}}}) do
    if p.electric_network_id then poles[#poles + 1] = {x = p.position.x, y = p.position.y, new = false, sup = p.prototype.get_supply_area_distance(), wire = p.prototype.get_max_wire_distance()} end
  end
  local half = {['electric-furnace'] = {1.35, 1.35}, roboport = {2.0, 2.0}, ['assembling-machine-2'] = {1.35, 1.35}, ['assembling-machine-1'] = {1.35, 1.35}, ['chemical-plant'] = {1.35, 1.35}, ['oil-refinery'] = {2.35, 2.35},
    inserter = {0.15, 0.15}, ['fast-inserter'] = {0.15, 0.15}, ['long-handed-inserter'] = {0.15, 0.15}, pump = {0.85, 0.35}}
  local unp = {}
  for _, e in pairs(L) do local h = half[e.name] if h then
    local hx, hy = h[1], h[2]
    if e.name == 'pump' and (e.dir == N or e.dir == S) then hx, hy = hy, hx end
    local cov = false
    for _, p in pairs(poles) do local d = p.sup or 3.5
      if math.abs(e.x - p.x) < d + hx and math.abs(e.y - p.y) < d + hy then cov = true break end end
    if not cov then unp[#unp + 1] = string.format('%s(%.1f,%.1f)', e.name, e.x, e.y) end
  end end
  local reach, frontier = {}, {}
  for i, p in pairs(poles) do if not p.new then reach[i] = true frontier[#frontier + 1] = i end end
  while #frontier > 0 do local i = table.remove(frontier)
    for j, q in pairs(poles) do if not reach[j] then
      local w = math.min(poles[i].wire or 9, q.wire or 9)
      if (poles[i].x - q.x) ^ 2 + (poles[i].y - q.y) ^ 2 <= w * w then reach[j] = true frontier[#frontier + 1] = j end
    end end
  end
  local disc = {} for i, p in pairs(poles) do if not reach[i] then disc[#disc + 1] = string.format('(%.1f,%.1f)', p.x, p.y) end end
  local occ, dup = {}, {}
  local size = {['electric-furnace'] = {3, 3}, roboport = {4, 4}, ['gun-turret'] = {2, 2}, ['assembling-machine-2'] = {3, 3}, ['assembling-machine-1'] = {3, 3}, ['chemical-plant'] = {3, 3}, ['steel-furnace'] = {2, 2}, ['oil-refinery'] = {5, 5}}
  for _, e in pairs(L) do
    local w, h = 1, 1
    if size[e.name] then w, h = size[e.name][1], size[e.name][2]
    elseif e.name == 'pump' then if e.dir == E or e.dir == W then w = 2 else h = 2 end
    elseif e.name == 'splitter' then if e.dir == E or e.dir == W then h = 2 else w = 2 end end
    local x0, y0 = math.floor(e.x - w / 2 + 0.01), math.floor(e.y - h / 2 + 0.01)
    for i = 0, w - 1 do for j = 0, h - 1 do local k = (x0 + i) .. ',' .. (y0 + j)
      if occ[k] then dup[#dup + 1] = e.name .. '@' .. k .. '/' .. occ[k] else occ[k] = e.name end end end
  end
  -- live fluid read at every join with an existing pipe (planned pipes carry extra.fluid)
  local FL = {['crude-oil'] = 'crude', water = 'water', ['petroleum-gas'] = 'pg', ['light-oil'] = 'light', ['heavy-oil'] = 'heavy', lubricant = 'lub', ['sulfuric-acid'] = 'acid'}
  local plan = {}
  for _, e in pairs(L) do if e.name == 'pipe' or e.name == 'pipe-to-ground' then plan[math.floor(e.x) .. ',' .. math.floor(e.y)] = e end end
  local V = {[N] = {0, -1}, [E] = {1, 0}, [S] = {0, 1}, [W] = {-1, 0}}
  local joins, mism, touched = {}, {}, 0
  for _, e in pairs(L) do if e.name == 'pipe' or e.name == 'pipe-to-ground' then
    for d, v in pairs(V) do if e.name == 'pipe' or e.dir == d then
      local nx, ny = e.x + v[1], e.y + v[2]
      if not plan[math.floor(nx) .. ',' .. math.floor(ny)] then
        for _, q in pairs(s.find_entities_filtered{position = {nx, ny}, radius = 0.3, type = {'pipe', 'pipe-to-ground'}}) do
          if q.type == 'pipe' or q.direction == (d + 8) % 16 then
            touched = touched + 1
            local f = 'empty' for k in pairs(q.get_fluid_contents()) do f = FL[k] or k end
            local want = e.extra and e.extra.fluid
            joins[#joins + 1] = string.format('%s(%.1f,%.1f)[%s]~%s(%.1f,%.1f)=%s', e.name == 'pipe' and 'P' or 'G', e.x, e.y, want, q.name == 'pipe' and 'P' or 'G', q.position.x, q.position.y, f)
            if f ~= 'empty' and f ~= want then mism[#mism + 1] = joins[#joins] end
          end
        end
      end
    end end
  end end
  out[#out + 1] = 'joins to live pipes=' .. touched .. ' mismatched=' .. #mism .. ' ' .. table.concat(joins, ' ')
  out[#out + 1] = 'self-overlaps=' .. #dup .. ' ' .. table.concat(dup, ' ')
  out[#out + 1] = 'unpowered=' .. #unp .. ' ' .. table.concat(unp, ' ')
  out[#out + 1] = 'disconnected poles=' .. #disc .. ' ' .. table.concat(disc, ' ')
end
