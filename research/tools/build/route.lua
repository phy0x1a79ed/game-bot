--- tool: route
--- kind: call
--- effect: read
--- summary: route a belt between two tiles around obstacles, using undergrounds where cheaper, and return it as a checked build list
--- args: from {x, y}; to {x, y} (the first and last belt tiles); box {x0, y0, x1, y1} (tile search area, at most 128 x 128, holding both ends); surface (default nauvis); force (default player); belt (default transport-belt, its underground follows); underground (override); start_flow {dx, dy} and end_flow {dx, dy} (optional direction of the first and last belt); accept (codes allowed on every entry)
--- returns: {ok, list, length, belts, undergrounds, issues, summary} or {error, hint}
--- uses: intent
-- Weighted A* over (tile, direction): a straight step costs 1, a turn 3, an underground hop 5 plus its span.
-- The list is in flow order, in the format check takes, and has already been through check. Tiles that an existing
-- belt feeds, or that an inserter picks from or drops onto, are avoided, except at the two ends.
local I = use("intent")
local a = ... or {}

local function fail(msg, hint) return {error = msg, hint = hint} end
local function num(v) return type(v) == "number" end
local function pt(v)
  if type(v) ~= "table" then return nil end
  local x, y = v.x or v[1], v.y or v[2]
  if num(x) and num(y) then return {x, y} end
end
local function card(v)
  v = pt(v)
  if not v then return nil end
  local x, y = v[1] > 0.001 and 1 or (v[1] < -0.001 and -1 or 0), v[2] > 0.001 and 1 or (v[2] < -0.001 and -1 or 0)
  if (x ~= 0) ~= (y ~= 0) then return {x, y} end
end

local s = a.surface == nil and game.surfaces.nauvis or game.surfaces[a.surface]
if not s then return fail("no surface named " .. tostring(a.surface), "the usual surface is nauvis") end
local f = a.force == nil and game.forces.player or game.forces[a.force]
if not f then return fail("no force named " .. tostring(a.force), "the usual force is player") end

local from, to = pt(a.from), pt(a.to)
if not from or not to then return fail("from and to must both be {x, y}", "for example from = {x = 10.5, y = 4.5}: the tile that holds the point is used") end
local bx = a.box
local X0, Y0, X1, Y1
if type(bx) == "table" then
  X0, Y0, X1, Y1 = bx.x0 or bx[1], bx.y0 or bx[2], bx.x1 or bx[3], bx.y1 or bx[4]
end
if not (num(X0) and num(Y0) and num(X1) and num(Y1)) then
  return fail("box must be {x0, y0, x1, y1} in tiles", "the search area, for example {x0 = 0, y0 = 0, x1 = 40, y1 = 40}")
end
X0, Y0, X1, Y1 = math.floor(math.min(X0, X1)), math.floor(math.min(Y0, Y1)), math.floor(math.max(X0, X1)), math.floor(math.max(Y0, Y1))
local W, H = X1 - X0 + 1, Y1 - Y0 + 1
if W > 128 or H > 128 then
  return fail(string.format("the box is %d x %d tiles; the most is 128 x 128", W, H), "route in stages, or narrow the box around the two ends")
end
local sx, sy, gx, gy = math.floor(from[1]), math.floor(from[2]), math.floor(to[1]), math.floor(to[2])
for _, t in ipairs{{"from", sx, sy}, {"to", gx, gy}} do
  if t[2] < X0 or t[2] > X1 or t[3] < Y0 or t[3] > Y1 then
    return fail(string.format("%s tile (%d, %d) is outside the box", t[1], t[2], t[3]), "widen the box to hold both ends")
  end
end

local belt = a.belt or "transport-belt"
local bp = prototypes.entity[belt]
if not bp or bp.type ~= "transport-belt" then return fail("no belt named " .. tostring(belt), "for example transport-belt or fast-transport-belt") end
local ug = a.underground or belt:gsub("transport%-belt$", "underground-belt")
local up = prototypes.entity[ug]
if up and up.type ~= "underground-belt" then up = nil end
if a.underground and not up then return fail("no underground belt named " .. tostring(a.underground), "for example underground-belt") end
local maxd = up and up.max_underground_distance or 0

local sdir, edir = card(a.start_flow), card(a.end_flow)
if (a.start_flow and not sdir) or (a.end_flow and not edir) then
  return fail("start_flow and end_flow must be one-axis directions", "for example {1, 0} for east")
end

local CARDS = {[0] = {0, -1}, [1] = {1, 0}, [2] = {0, 1}, [3] = {-1, 0}}
local function didx(c) for d = 0, 3 do if CARDS[d][1] == c[1] and CARDS[d][2] == c[2] then return d end end end
local DN = {[0] = "north", [1] = "east", [2] = "south", [3] = "west"}
local function id(x, y) return (y - Y0) * W + (x - X0) end
local function inb(x, y) return x >= X0 and x <= X1 and y >= Y0 and y <= Y1 end

-- open tiles: nothing shares the belt's collision layers there, and the engine accepts a belt ghost
local area = {{X0 - 1, Y0 - 1}, {X1 + 2, Y1 + 2}}
local taken = I.occupied(s, bp, area)
local open = {}
for y = Y0, Y1 do
  for x = X0, X1 do
    open[id(x, y)] = not taken(x, y) and s.can_place_entity{name = belt, position = {x + 0.5, y + 0.5}, direction = defines.direction.north,
      force = f, build_check_type = defines.build_check_type.manual_ghost}
  end
end

local bad, ugaxis = {}, {}
local function mark(px, py) if inb(math.floor(px), math.floor(py)) then bad[id(math.floor(px), math.floor(py))] = true end end
for _, e in pairs(s.find_entities_filtered{area = area, type = {"transport-belt", "underground-belt", "splitter"}}) do
  local c = ({[0] = {0, -1}, [4] = {1, 0}, [8] = {0, 1}, [12] = {-1, 0}})[e.direction]
  if c then
    local p = e.position
    if e.type == "transport-belt" or (e.type == "underground-belt" and e.belt_to_ground_type == "output") then mark(p.x + c[1], p.y + c[2]) end
    if e.type == "splitter" then
      local px, py = -c[2] * 0.5, c[1] * 0.5
      mark(p.x + px + c[1], p.y + py + c[2])
      mark(p.x - px + c[1], p.y - py + c[2])
    end
    if e.type == "underground-belt" and inb(math.floor(p.x), math.floor(p.y)) then ugaxis[id(math.floor(p.x), math.floor(p.y))] = e.direction % 8 end
  end
end
for _, e in pairs(s.find_entities_filtered{area = area, type = "inserter"}) do
  mark(e.pickup_position.x, e.pickup_position.y)
  mark(e.drop_position.x, e.drop_position.y)
end

local sid, gid = id(sx, sy), id(gx, gy)
for _, t in ipairs{{"from", sx, sy, sid}, {"to", gx, gy, gid}} do
  if not open[t[4]] then
    local best, bd
    for y = Y0, Y1 do for x = X0, X1 do
      if open[id(x, y)] then
        local d = (x - t[2]) ^ 2 + (y - t[3]) ^ 2
        if not bd or d < bd then best, bd = {x, y}, d end
      end
    end end
    return fail(string.format("the %s tile (%d, %d) cannot take a belt", t[1], t[2], t[3]),
      best and string.format("the nearest free tile is (%d, %d)", best[1], best[2]) or "no tile in the box is free")
  end
  bad[t[4]] = nil
end
local function ok(x, y) return inb(x, y) and open[id(x, y)] and not bad[id(x, y)] end

local heap = {}
local function push(c, k)
  heap[#heap + 1] = {c, k}
  local i = #heap
  while i > 1 do
    local p = math.floor(i / 2)
    if heap[p][1] <= heap[i][1] then break end
    heap[p], heap[i] = heap[i], heap[p]
    i = p
  end
end
local function pop()
  local top = heap[1]
  heap[1] = heap[#heap]
  heap[#heap] = nil
  local i, n = 1, #heap
  while true do
    local l, r, m = 2 * i, 2 * i + 1, i
    if l <= n and heap[l][1] < heap[m][1] then m = l end
    if r <= n and heap[r][1] < heap[m][1] then m = r end
    if m == i then break end
    heap[m], heap[i] = heap[i], heap[m]
    i = m
  end
  return top
end

-- state key: (tile id * 4 + direction) * 2 + exit flag; an exit flag marks an underground exit, which must run straight on
local function key(x, y, d, ex) return (id(x, y) * 4 + d) * 2 + ex end
local function unkey(k)
  local ex = k % 2
  local r = (k - ex) / 2
  local d = r % 4
  local i = (r - d) / 4
  return i % W + X0, math.floor(i / W) + Y0, d, ex
end
local function h(x, y) return math.abs(x - gx) + math.abs(y - gy) end

local dist, prev = {}, {}
local function relax(k, nk, nc, hop)
  if not dist[nk] or nc < dist[nk] then
    dist[nk] = nc
    prev[nk] = {k, hop}
    local x, y = unkey(nk)
    push(nc + h(x, y), nk)
  end
end
for d = 0, 3 do
  if not sdir or (CARDS[d][1] == sdir[1] and CARDS[d][2] == sdir[2]) then
    local k = key(sx, sy, d, 0)
    dist[k] = 0
    push(h(sx, sy), k)
  end
end

local goal, pops, nearest, near_h = nil, 0, nil, nil
local BUDGET = 400000
while #heap > 0 do
  local it = pop()
  local k = it[2]
  local x, y, d, ex = unkey(k)
  local c = dist[k]
  if it[1] == c + h(x, y) then
    pops = pops + 1
    if pops > BUDGET then return fail("the search gave up after " .. BUDGET .. " steps", "narrow the box around the two ends") end
    if not near_h or h(x, y) < near_h then near_h, nearest = h(x, y), {x, y} end
    if x == gx and y == gy and (not edir or (CARDS[d][1] == edir[1] and CARDS[d][2] == edir[2])) then goal = k break end
    local v = CARDS[d]
    local nx, ny = x + v[1], y + v[2]
    if ok(nx, ny) then
      if ex == 0 then
        for _, dd in ipairs{d, (d + 1) % 4, (d + 3) % 4} do
          relax(k, key(nx, ny, dd, 0), c + 1 + (dd ~= d and 3 or 0))
        end
      else
        relax(k, key(nx, ny, d, 0), c + 1)
      end
      for L = 2, maxd do
        local ex2, ey2 = nx + v[1] * L, ny + v[2] * L
        if not inb(ex2, ey2) then break end
        local clash = false
        for j = 1, L - 1 do
          local ax = ugaxis[id(nx + v[1] * j, ny + v[2] * j)]
          if ax and ax == (d * 4) % 8 then clash = true end
        end
        if not clash and ok(ex2, ey2) then relax(k, key(ex2, ey2, d, 1), c + 5 + L, L) end
      end
    end
  end
end
if not goal then
  return fail(string.format("no belt route from (%d, %d) to (%d, %d) inside the box", sx, sy, gx, gy),
    nearest and string.format("the search reached (%d, %d), %d tiles short; widen the box%s, or clear what blocks the way", nearest[1], nearest[2], near_h,
      up and "" or " (no underground belt is available)") or "no belt can start at the first tile")
end

local seq, k = {}, goal
while k do
  table.insert(seq, 1, k)
  k = prev[k] and prev[k][1]
end
local list, belts, hops, length = {}, 0, 0, 1
local function entry(name, x, y, d, role)
  local intent = {flow = {CARDS[d][1], CARDS[d][2]}}
  if role then intent.role = role end
  list[#list + 1] = {name = name, position = {x + 0.5, y + 0.5}, intent = intent}
end
for n, k2 in ipairs(seq) do
  local x, y, d, ex = unkey(k2)
  if ex == 1 then
    local L = prev[k2][2]
    entry(ug, x - CARDS[d][1] * L, y - CARDS[d][2] * L, d, "entry")
    entry(ug, x, y, d, "exit")
    hops = hops + 1
    length = length + L + 1
  else
    entry(belt, x, y, d)
    belts = belts + 1
    if n > 1 then length = length + 1 end
  end
end

local res = I.check(s, f, list, {accept = a.accept})
return {ok = res.ok, list = list, length = length, belts = belts, undergrounds = hops, issues = I.failures(list, res), summary = res.summary,
  searched = pops}
