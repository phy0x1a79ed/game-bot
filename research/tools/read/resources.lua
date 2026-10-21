--- tool: resources
--- kind: call
--- effect: read
--- summary: ore patches in an area, largest first, with amount, tile count, bounding box and the drills mining each
--- args: x0, y0, x1, y1 (numbers); name (an ore name or a list); limit (default 200, max 1000), offset; surface, force (the force whose drills are counted, default player)
--- returns: {patches = {{name, tiles, amount, x0, y0, x1, y1, drills, infinite}, ...}, total, more, next}; the box edges are tile edges; {error, hint} on bad args
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {area = true, paged = true, extra = {"name"}})
if not c then return err end

local query = {area = c.area, type = "resource"}
if a.name ~= nil then
  local set, list = rd.nameset(a.name, "entity", "name")
  if not set then return list end
  for _, n in ipairs(list) do
    if prototypes.entity[n].type ~= "resource" then
      return rd.fail(n .. " is not a resource", "ore names are such as iron-ore, copper-ore, coal, stone, crude-oil")
    end
  end
  query.name = list
end

-- group by 32-tile chunk and ore, then join touching chunks of the same ore into one patch
local chunks = {}
for _, r in pairs(c.s.find_entities_filtered(query)) do
  local p = r.position
  local cx, cy = math.floor(p.x / 32), math.floor(p.y / 32)
  local key = r.name .. "|" .. cx .. "|" .. cy
  local ch = chunks[key]
  if not ch then
    ch = {name = r.name, cx = cx, cy = cy, tiles = 0, amount = 0, x0 = p.x, y0 = p.y, x1 = p.x, y1 = p.y}
    chunks[key] = ch
  end
  ch.tiles, ch.amount = ch.tiles + 1, ch.amount + r.amount
  ch.x0, ch.y0, ch.x1, ch.y1 = math.min(ch.x0, p.x), math.min(ch.y0, p.y), math.max(ch.x1, p.x), math.max(ch.y1, p.y)
end

local patches, seen = {}, {}
local keys = {}
for key in pairs(chunks) do keys[#keys + 1] = key end
table.sort(keys)
for _, key in ipairs(keys) do
  if not seen[key] then
    local ch = chunks[key]
    local p = {name = ch.name, tiles = 0, amount = 0, x0 = ch.x0, y0 = ch.y0, x1 = ch.x1, y1 = ch.y1}
    local todo = {key}
    seen[key] = true
    while #todo > 0 do
      local d = chunks[table.remove(todo)]
      p.tiles, p.amount = p.tiles + d.tiles, p.amount + d.amount
      p.x0, p.y0, p.x1, p.y1 = math.min(p.x0, d.x0), math.min(p.y0, d.y0), math.max(p.x1, d.x1), math.max(p.y1, d.y1)
      for dx = -1, 1 do
        for dy = -1, 1 do
          local k = d.name .. "|" .. (d.cx + dx) .. "|" .. (d.cy + dy)
          if chunks[k] and not seen[k] then seen[k] = true todo[#todo + 1] = k end
        end
      end
    end
    p.x0, p.y0, p.x1, p.y1 = math.floor(p.x0), math.floor(p.y0), math.floor(p.x1) + 1, math.floor(p.y1) + 1
    p.infinite = prototypes.entity[p.name].infinite_resource or nil
    patches[#patches + 1] = p
  end
end

-- a drill counts for a patch when its mining area holds that ore
local drills = c.s.find_entities_filtered{area = {{c.x0 - 4, c.y0 - 4}, {c.x1 + 4, c.y1 + 4}}, type = "mining-drill",
  force = c.force}
local mined = {}
for i, d in ipairs(drills) do
  local radius = d.prototype.mining_drill_radius
  local p = d.position
  local names = {}
  for _, r in pairs(c.s.find_entities_filtered{area = {{p.x - radius, p.y - radius}, {p.x + radius, p.y + radius}}, type = "resource"}) do
    names[r.name] = true
  end
  mined[i] = {x = p.x, y = p.y, names = names}
end
for _, p in ipairs(patches) do
  local n = 0
  for _, d in ipairs(mined) do
    if d.names[p.name] and d.x >= p.x0 - 3 and d.x <= p.x1 + 3 and d.y >= p.y0 - 3 and d.y <= p.y1 + 3 then n = n + 1 end
  end
  p.drills = n
end

table.sort(patches, function(p, q)
  if p.amount ~= q.amount then return p.amount > q.amount end
  if p.name ~= q.name then return p.name < q.name end
  return p.x0 < q.x0
end)
return rd.page({}, "patches", patches, c)
