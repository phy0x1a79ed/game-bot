--- tool: belt_trace
--- kind: call
--- effect: read
--- summary: follow a belt line downstream (and upstream with up = true) through undergrounds and splitters as straight segments, with items per lane and why each branch stops
--- args: x, y (a tile on the belt); up (bool: also trace upstream); taps (bool: list inserters that pick from or drop onto the line); limit (belt entities to visit, default 500, max 5000); surface
--- returns: {start = {name, x, y}, tiles, segments = {{id, parent, kind, dir, from = {x, y}, to = {x, y}, n, left = {item = n}, right = {item = n}}, ...}, lanes = {left, right}, ends = {{seg, x, y, why = "end" | "loop" | "join" | "cap", faces}}, taps = {{name, x, y, seg, role = "pickup" | "drop", other = {name, x, y, recipe}}}, up = {same fields}}; segments run in flow order and parent is the segment they branch from; {error, hint} on bad args
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {point = true, extra = {"up", "taps", "limit"}})
if not c then return err end
local limit = a.limit == nil and 500 or a.limit
if type(limit) ~= "number" or limit ~= math.floor(limit) or limit < 1 or limit > 5000 then
  return rd.fail("limit must be a whole number from 1 to 5000", "got " .. tostring(a.limit))
end
local s = c.s

local DV = {[0] = {0, -1}, [4] = {1, 0}, [8] = {0, 1}, [12] = {-1, 0}}
local BELTS = {"transport-belt", "underground-belt", "splitter"}

local start = s.find_entities_filtered{area = {{c.x - 0.3, c.y - 0.3}, {c.x + 0.3, c.y + 0.3}}, type = BELTS}[1]
if not start then
  local near = s.find_entities_filtered{position = {c.x, c.y}, radius = 6, type = BELTS, limit = 1}[1]
  return rd.fail(string.format("no belt at (%.1f, %.1f)", c.x, c.y),
    near and string.format("nearest belt is %s at (%.1f, %.1f)", near.name, near.position.x, near.position.y)
      or "no belt within 6 tiles")
end

local function nexts(e, fwd)
  local n = fwd and e.belt_neighbours.outputs or e.belt_neighbours.inputs
  return n
end

-- the entities one step covers, in travel order: an underground pair counts as one step
local function unit(e, fwd)
  if e.type == "underground-belt" then
    local io = e.belt_to_ground_type
    local nb = e.underground_belt_neighbour
    if nb and ((fwd and io == "input") or (not fwd and io == "output")) then return {e, nb}, nb end
  end
  return {e}, e
end

local function kind_of(e)
  if e.type == "transport-belt" then return "belt" end
  if e.type == "underground-belt" then return "underground" end
  return e.type
end

local function faces(e)
  local d = DV[e.direction]
  if not d then return nil end
  local p = e.position
  local probes = {{p.x + d[1], p.y + d[2]}}
  if e.type == "splitter" then
    probes[2] = {p.x + d[1] + 0.5 * math.abs(d[2]), p.y + d[2] + 0.5 * math.abs(d[1])}
    probes[1] = {p.x + d[1] - 0.5 * math.abs(d[2]), p.y + d[2] - 0.5 * math.abs(d[1])}
  end
  for _, q in ipairs(probes) do
    for _, o in pairs(s.find_entities_filtered{position = q}) do
      if o.type ~= "resource" and o.type ~= "item-entity" and o.type ~= "corpse" and o.type ~= "character" then
        return o.type == "entity-ghost" and o.ghost_name .. " (ghost)" or o.name
      end
    end
  end
  return nil
end

local function xy(p) return {rd.r2(p.x), rd.r2(p.y)} end

local function trace(starts, fwd)
  local segs, ends, visited = {}, {}, {}
  local count = 0
  local stack = {}
  for i = #starts, 1, -1 do stack[#stack + 1] = {starts[i], nil} end
  while #stack > 0 do
    local item = table.remove(stack)
    local e0, parent = item[1], item[2]
    local seen = visited[e0.unit_number]
    if seen then
      local why, p = "join", parent
      while p do
        if p == seen then why = "loop" break end
        p = segs[p].parent
      end
      ends[#ends + 1] = {seg = parent, x = rd.r2(e0.position.x), y = rd.r2(e0.position.y), why = why}
    else
      local seg = {id = #segs + 1, parent = parent, kind = kind_of(e0), dir = e0.direction, n = 0, pts = {},
        ents = {}, left = {}, right = {}}
      segs[#segs + 1] = seg
      local cur = e0
      while true do
        if count >= limit then
          ends[#ends + 1] = {seg = seg.id, x = rd.r2(cur.position.x), y = rd.r2(cur.position.y), why = "cap"}
          break
        end
        local ents, tail = unit(cur, fwd)
        for _, u in ipairs(ents) do
          visited[u.unit_number] = seg.id
          seg.ents[#seg.ents + 1] = u
          seg.pts[#seg.pts + 1] = u.position
          local left, right = rd.belt_items(u)
          rd.add(seg.left, left)
          rd.add(seg.right, right)
        end
        count = count + #ents
        seg.n = seg.n + #ents
        local nx = nexts(tail, fwd)
        if #nx == 0 then
          ends[#ends + 1] = {seg = seg.id, x = rd.r2(tail.position.x), y = rd.r2(tail.position.y), why = "end",
            faces = fwd and faces(tail) or nil}
          break
        end
        local n1 = nx[1]
        if #nx == 1 and seg.kind == "belt" and n1.type == "transport-belt" and n1.direction == seg.dir
            and not visited[n1.unit_number] then
          cur = n1
        else
          for i = #nx, 1, -1 do stack[#stack + 1] = {nx[i], seg.id} end
          break
        end
      end
    end
  end
  return segs, ends, count
end

-- the tiles an entity covers, as keys, for matching inserter pickup and drop positions
local function tiles(e, add)
  local p = e.position
  local fx, fy = math.floor(p.x), math.floor(p.y)
  if e.type == "splitter" then
    if e.direction == 0 or e.direction == 8 then
      add(math.floor(p.x - 0.5), fy)
      add(math.floor(p.x + 0.5), fy)
    else
      add(fx, math.floor(p.y - 0.5))
      add(fx, math.floor(p.y + 0.5))
    end
  else
    add(fx, fy)
  end
end

local function find_taps(segs)
  local owner = {}
  for _, seg in ipairs(segs) do
    for _, e in ipairs(seg.ents) do
      tiles(e, function(x, y) owner[x .. "," .. y] = seg.id end)
    end
  end
  local taps, seen = {}, {}
  local function other(t)
    if not t then return nil end
    local r = {name = t.name, x = rd.r2(t.position.x), y = rd.r2(t.position.y)}
    if t.type == "assembling-machine" or t.type == "furnace" then
      local recipe = t.get_recipe()
      if recipe then r.recipe = recipe.name end
    end
    return r
  end
  for _, seg in ipairs(segs) do
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(seg.pts) do
      x0, y0, x1, y1 = math.min(x0, p.x), math.min(y0, p.y), math.max(x1, p.x), math.max(y1, p.y)
    end
    for _, ins in pairs(s.find_entities_filtered{type = "inserter", area = {{x0 - 3, y0 - 3}, {x1 + 3, y1 + 3}}}) do
      local pk, dp = ins.pickup_position, ins.drop_position
      local from = owner[math.floor(pk.x) .. "," .. math.floor(pk.y)]
      local to = owner[math.floor(dp.x) .. "," .. math.floor(dp.y)]
      for _, role in ipairs{{"pickup", from, ins.drop_target}, {"drop", to, ins.pickup_target}} do
        local key = ins.unit_number .. role[1]
        if role[2] and not seen[key] then
          seen[key] = true
          taps[#taps + 1] = {name = ins.name, x = rd.r2(ins.position.x), y = rd.r2(ins.position.y), seg = role[2],
            role = role[1], other = other(role[3])}
        end
      end
    end
  end
  table.sort(taps, function(p, q)
    if p.seg ~= q.seg then return p.seg < q.seg end
    if p.y ~= q.y then return p.y < q.y end
    return p.x < q.x
  end)
  return taps
end

local function render(segs, ends, count, fwd)
  local out = {tiles = count, segments = {}, ends = ends, lanes = {left = {}, right = {}}}
  for i, seg in ipairs(segs) do
    local pts = seg.pts
    local first, last = pts[1], pts[#pts]
    if not fwd then first, last = last, first end
    local r = {id = seg.id, parent = seg.parent, kind = seg.kind, dir = rd.dir(seg.dir), from = xy(first),
      to = xy(last), n = seg.n}
    if next(seg.left) then r.left = seg.left end
    if next(seg.right) then r.right = seg.right end
    rd.add(out.lanes.left, seg.left)
    rd.add(out.lanes.right, seg.right)
    out.segments[i] = r
  end
  return out
end

local function finish(starts, fwd)
  local segs, ends, count = trace(starts, fwd)
  local out = render(segs, ends, count, fwd)
  if a.taps then
    local taps = find_taps(segs)
    if #taps > 100 then
      for i = #taps, 101, -1 do taps[i] = nil end
      out.taps_more = true
    end
    out.taps = taps
  end
  return out
end

local out = finish({start}, true)
out.start = {name = start.name, x = rd.r2(start.position.x), y = rd.r2(start.position.y)}
if a.up then
  local before = nexts(start, false)
  if start.type == "underground-belt" and start.belt_to_ground_type == "output" and start.underground_belt_neighbour then
    before = {start.underground_belt_neighbour}
  end
  out.up = finish(before, false)
end
return out
