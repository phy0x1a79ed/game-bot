--- tool: route
--- kind: call
--- effect: read
--- summary: route a belt between two tiles around obstacles, using undergrounds where cheaper, and return it as a checked build list
--- args: from {x, y}; to {x, y} (the first and last belt tiles); box {x0, y0, x1, y1} (tile search area, at most 48 x 48, holding both ends); surface (default nauvis); force (default player); belt (default transport-belt, its underground follows); underground (override); start_flow {dx, dy} and end_flow {dx, dy} (optional direction of the first and last belt); accept (codes allowed on every entry)
--- returns: {ok, list, length, belts, undergrounds, issues, summary} or {error, hint}
--- uses: intent
-- Weighted A* over (tile, direction): a straight step costs 1, a turn 3, an underground hop 5 plus its span.
-- The list is in flow order, in the format check takes, and has already been through check. Tiles that an existing
-- belt feeds, or that an inserter picks from or drops onto, are avoided, except at the two ends.
local I = use("intent")
local a = ... or {}
local MAX_BOX, BUDGET = 48, 3000
if type(a) ~= "table" then return {error = "no arguments", hint = "pass from, to and box"} end

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

if a.surface ~= nil and type(a.surface) ~= "string" then return fail("surface must be a name", "for example \"nauvis\"") end
if a.force ~= nil and type(a.force) ~= "string" then return fail("force must be a name", "for example \"player\"") end
if a.belt ~= nil and type(a.belt) ~= "string" then return fail("belt must be an entity name", "for example transport-belt") end
if a.underground ~= nil and type(a.underground) ~= "string" then return fail("underground must be an entity name", "for example underground-belt") end
if a.accept ~= nil and type(a.accept) ~= "table" then return fail("accept must be a list of codes", "for example {\"BELT_JOINS_FOREIGN\"}") end
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
if W > MAX_BOX or H > MAX_BOX then
  return fail(string.format("the box is %d x %d tiles; the most is %d x %d", W, H, MAX_BOX, MAX_BOX), "route in stages, or narrow the box around the two ends")
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

-- open tiles: no entity and no ground shares the belt's collision layers there (decided once per tile, when the search first needs it)
local area = {{X0 - 1, Y0 - 1}, {X1 + 2, Y1 + 2}}
local taken = I.occupied(s, bp, area)
local ground = I.tile_free(s, bp)
local open = {}
local function is_open(x, y)
  local i = id(x, y)
  local v = open[i]
  if v == nil then
    v = not taken(x, y) and ground(x, y)
    open[i] = v
  end
  return v
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
  if not is_open(t[2], t[3]) then
    local best, bd
    for y = math.max(Y0, t[3] - 6), math.min(Y1, t[3] + 6) do for x = math.max(X0, t[2] - 6), math.min(X1, t[2] + 6) do
      if is_open(x, y) then
        local d = (x - t[2]) ^ 2 + (y - t[3]) ^ 2
        if not bd or d < bd then best, bd = {x, y}, d end
      end
    end end
    return fail(string.format("the %s tile (%d, %d) cannot take a belt", t[1], t[2], t[3]),
      best and string.format("the nearest free tile is (%d, %d)", best[1], best[2]) or "no free tile within 6 tiles")
  end
  bad[t[4]] = nil
end
-- tile ids are row-major inside the box; a state is (tile id, direction, exit flag) packed as id * 8 + direction * 2 + exit flag,
-- where the exit flag marks an underground exit, which must run straight on
local DX, DY = {[0] = 0, 1, 0, -1}, {[0] = -1, 0, 1, 0}
local gi, gxr, gyr = gid, gx - X0, gy - Y0
local usable = {}
local function ok(i)
  local v = usable[i]
  if v == nil then
    local x = i % W
    v = not bad[i] and is_open(X0 + x, Y0 + (i - x) / W)
    usable[i] = v
  end
  return v
end
local hcache = {}
local function h(i)
  local v = hcache[i]
  if not v then
    local x = i % W
    v = math.abs(x - gxr) + math.abs((i - x) / W - gyr)
    hcache[i] = v
  end
  return v
end

-- buckets by priority (cost so far plus distance left, an integer that never falls): no heap, no per-push allocation
local buckets, top = {}, 0
local dist, prev, hop = {}, {}, {}
local function relax(k, nk, nc, span)
  local old = dist[nk]
  if not old or nc < old then
    dist[nk] = nc
    prev[nk] = k
    hop[nk] = span
    local p = nc + h((nk - nk % 8) / 8)
    local b = buckets[p]
    if not b then b = {} buckets[p] = b end
    b[#b + 1] = nk
    if p > top then top = p end
  end
end
for d = 0, 3 do
  if not sdir or (CARDS[d][1] == sdir[1] and CARDS[d][2] == sdir[2]) then
    relax(nil, sid * 8 + d * 2, 0)
  end
end

local goal, pops, near_i, near_h = nil, 0, nil, nil
local p = 0
while p <= top and not goal do
  local b = buckets[p]
  local n = 1
  while b and n <= #b and not goal do
    local k = b[n]
    n = n + 1
    local ex = k % 2
    local d = (k % 8 - ex) / 2
    local i = (k - k % 8) / 8
    local c = dist[k]
    if c + h(i) == p then
      pops = pops + 1
      if pops > BUDGET then return fail("the search gave up after " .. BUDGET .. " steps", "narrow the box around the two ends, or route in stages") end
      local hv = h(i)
      if not near_h or hv < near_h then near_h, near_i = hv, i end
      if i == gi and (not edir or (CARDS[d][1] == edir[1] and CARDS[d][2] == edir[2])) then goal = k break end
      local x = i % W
      local y = (i - x) / W
      local nx, ny = x + DX[d], y + DY[d]
      if nx >= 0 and nx < W and ny >= 0 and ny < H then
        local ni = i + DX[d] + DY[d] * W
        if ok(ni) then
          if ex == 0 then
            relax(k, ni * 8 + d * 2, c + 1)
            relax(k, ni * 8 + ((d + 1) % 4) * 2, c + 4)
            relax(k, ni * 8 + ((d + 3) % 4) * 2, c + 4)
          else
            relax(k, ni * 8 + d * 2, c + 1)
          end
          -- an underground is worth it only to cross something: a tile between the ends that the belt cannot use
          local crossing = false
          for L = 2, maxd do
            local mx, my = nx + DX[d] * L, ny + DY[d] * L
            if mx < 0 or mx >= W or my < 0 or my >= H then break end
            local mid = ni + (L - 1) * (DX[d] + DY[d] * W)
            if not ok(mid) then crossing = true end
            local ax = ugaxis[mid]
            if ax and ax == (d * 4) % 8 then break end
            local ei = ni + L * (DX[d] + DY[d] * W)
            if crossing and ok(ei) then relax(k, ei * 8 + d * 2 + 1, c + 5 + L, L) end
          end
        end
      end
    end
  end
  buckets[p] = nil
  p = p + 1
end
if not goal then
  local hint = "no belt can start at the first tile"
  if near_i then
    hint = string.format("the search reached (%d, %d), %d tiles short, after %d states; widen the box%s, or clear what blocks the way",
      near_i % W + X0, (near_i - near_i % W) / W + Y0, near_h, pops, up and "" or " (no underground belt is available)")
  end
  return fail(string.format("no belt route from (%d, %d) to (%d, %d) inside the box", sx, sy, gx, gy), hint)
end

local seq, k = {}, goal
while k do
  table.insert(seq, 1, k)
  k = prev[k]
end
local list, belts, hops, length = {}, 0, 0, 1
local function entry(name, x, y, d, role)
  local intent = {flow = {CARDS[d][1], CARDS[d][2]}}
  if role then intent.role = role end
  list[#list + 1] = {name = name, position = {x + 0.5, y + 0.5}, intent = intent}
end
for n, k2 in ipairs(seq) do
  local ex = k2 % 2
  local d = (k2 % 8 - ex) / 2
  local i = (k2 - k2 % 8) / 8
  local x = i % W + X0
  local y = (i - i % W) / W + Y0
  if ex == 1 then
    local L = hop[k2]
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

if #list > I.MAX_ENTRIES then
  return fail(string.format("the route needs %d entries; the most is %d", #list, I.MAX_ENTRIES), "route in stages, or shorten the distance")
end
local res = I.check(s, f, list, {accept = a.accept})
return {ok = res.ok, list = list, length = length, belts = belts, undergrounds = hops, issues = I.failures(list, res), summary = res.summary,
  searched = pops}
