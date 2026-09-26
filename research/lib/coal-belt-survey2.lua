local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

-- coal tile richness, bucketed into 3x3 cells, over the whole ring-1 patch area
local coal = surf.find_entities_filtered{type='resource', name='coal', area={{55,-60},{95,-33}}}
p('coal tiles in (55,-60)-(95,-33): ' .. #coal)
local cells = {}
for _, e in pairs(coal) do
  local cx = math.floor(e.position.x/3)*3
  local cy = math.floor(e.position.y/3)*3
  local k = cx .. ',' .. cy
  cells[k] = cells[k] or {n=0, total=0, cx=cx, cy=cy}
  cells[k].n = cells[k].n + 1
  cells[k].total = cells[k].total + e.amount
end
-- turret cover check (18 tile range) + distance to existing player entities
local turrets = {{66,-50},{74,-50},{76,-43},{83,-48}}
local existing = surf.find_entities_filtered{area={{55,-60},{95,-33}}, force='player'}
local list = {}
for k, c in pairs(cells) do
  local avg = c.total / c.n
  -- covered by any ring-1 turret?
  local covered = false
  for _, t in pairs(turrets) do
    local d = ((c.cx+1.5-t[1])^2 + (c.cy+1.5-t[2])^2)^0.5
    if d <= 16 then covered = true end -- 2 tile margin inside the 18-range
  end
  -- clear of existing entities within 3 tiles of cell centre?
  local blocked = false
  for _, e in pairs(existing) do
    local d = ((c.cx+1.5-e.position.x)^2 + (c.cy+1.5-e.position.y)^2)^0.5
    if d <= 3.5 then blocked = true end
  end
  if avg >= 200 then
    list[#list+1] = {cx=c.cx, cy=c.cy, avg=avg, n=c.n, covered=covered, blocked=blocked}
  end
end
table.sort(list, function(a,b) return a.avg > b.avg end)
p('=== rich cells (avg>=200/tile), sorted, top 20 ===')
for i, c in pairs(list) do
  if i <= 20 then
    p(string.format('cell centre~(%.0f,%.0f) avg=%.0f n=%d covered=%s blocked=%s', c.cx+1.5, c.cy+1.5, c.avg, c.n, tostring(c.covered), tostring(c.blocked)))
  end
end
rcon.print(table.concat(out, '\n'))
