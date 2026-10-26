--- tool: joins
--- kind: lib
--- effect: read
--- summary: the connection passes of intent: belt joins and side-loads, underground pairing, fluid mixing
--- args: none (a lib: intent calls run with its check state)
--- returns: {run}
--- uses: core
-- run(X) adds issues to X.E, the normalised entries of one intent check. X carries s (the surface), E, issue(e, code,
-- msg, ...), list_at(p, pred) (the entry whose box holds p), world_at(p) (the world entities there) and valid(e).

local C = use("core")
local CARD, DIR, at, vec = C.CARD, C.DIR, C.at, C.vec
local add, scale, same_tile, epos, ename, static = C.add, C.scale, C.same_tile, C.epos, C.ename, C.static
local BELTS = {["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true}

-- the fluid in world entity e's storage j, or in the segment it belongs to, or its filter
local function world_fluid(e, j)
  for _, get in pairs{"get_fluid_segment_fluid", "get_fluid", "get_fluid_segment_filter", "get_fluid_filter"} do
    local ok, fl = pcall(function() return e[get](j) end)
    if ok and fl and fl.name then return fl.name end
  end
end

local function run(X)
  local s, E, issue, list_at, world_at, valid = X.s, X.E, X.issue, X.list_at, X.world_at, X.valid

  -- 5. belts: where each belt-like entry hands items on, and what hands items to it
  -- a belt-like record: {src, kind, d, role, pos, w (world entity) or e (entry)}
  local function belt_at(p)
    local o = list_at(p)
    if o then return BELTS[o.type] and {src = "list", kind = o.type, d = o.d, role = o.role, pos = o.pos, e = o} or nil end
    for _, w in pairs(world_at(p)) do
      if BELTS[w.type] then
        return {src = "world", kind = w.type, d = w.direction, role = w.type == "underground-belt" and w.belt_to_ground_type or nil, pos = epos(w), w = w}
      end
    end
  end
  local function outputs(b) return C.belt_outputs(b.kind, b.d, b.pos, b.role) end
  local function feeds(b, p)
    for _, o in pairs(b and outputs(b) or {}) do if same_tile(o, p) then return true end end
    return false
  end
  local function bdesc(b)
    local items = b.w and C.carried(b.w) or {}
    return (b.src == "world" and "existing " or "") .. b.kind .. " at " .. at(b.pos) .. (#items > 0 and " (carrying " .. table.concat(items, ", ") .. ")" or "")
  end
  local JOIN = ": your items join that line. Leave a gap, or accept BELT_JOINS_FOREIGN"

  for _, e in ipairs(E) do
    if valid(e) and BELTS[e.type] and CARD[e.d] then
      local me = {src = "list", kind = e.type, d = e.d, role = e.role, pos = e.pos, e = e}
      for _, o in pairs(outputs(me)) do
        local T = belt_at(o)
        if T then
          local rel = (T.d - e.d) % 16
          if rel == 8 or (T.kind == "underground-belt" and T.role == "output" and rel == 0) or (T.kind == "splitter" and rel ~= 0) then
            issue(e, "BELT_FACES_BELT", "%s at %s runs into %s head-on, which stops it: turn one of them", e.name, at(e.pos), bdesc(T))
          elseif T.src == "world" and rel == 0 then
            issue(e, "BELT_JOINS_FOREIGN", "%s at %s flows straight into %s%s", e.name, at(e.pos), bdesc(T), JOIN)
          elseif T.src == "world" and T.kind == "transport-belt" then
            local back, far = belt_at(add(T.pos, scale(CARD[T.d], -1))), belt_at(add(T.pos, CARD[e.d]))
            if (back and back.d == T.d and feeds(back, T.pos)) or (far and feeds(far, T.pos)) then
              issue(e, "BELT_SIDELOADS", "%s at %s side-loads onto the %s lane of %s: your items mix into that line. End it a tile short, or accept BELT_SIDELOADS",
                e.name, at(e.pos), (e.d - T.d) % 16 == 4 and "left" or "right", bdesc(T))
            else
              issue(e, "BELT_JOINS_FOREIGN", "%s at %s bends %s into a curve, since nothing feeds it from behind%s", e.name, at(e.pos), bdesc(T), JOIN)
            end
          elseif T.src == "world" then
            issue(e, "BELT_SIDELOADS", "%s at %s side-loads onto %s: your items mix into that line. End it a tile short, or accept BELT_SIDELOADS",
              e.name, at(e.pos), bdesc(T))
          end
        end
      end
      -- upstream: existing belts that hand items into this entry
      for d = 0, 12, 4 do
        local n = add(e.pos, CARD[d])
        local W = e.type ~= "splitter" and not list_at(n) and belt_at(n)
        if W and W.src == "world" and feeds(W, e.pos) and not feeds(me, W.pos) then
          local rel = (W.d - e.d) % 16
          if rel == 8 or (e.type == "underground-belt" and e.role == "output" and rel == 0) then
            issue(e, "BELT_FACES_BELT", "%s runs head-on into %s at %s, which stops it: turn one of them", bdesc(W), e.name, at(e.pos))
          else
            issue(e, "BELT_JOINS_FOREIGN", "%s flows into %s at %s: its items enter your line. Leave a gap, or accept BELT_JOINS_FOREIGN", bdesc(W), e.name, at(e.pos))
          end
        end
      end
    end
  end

  -- 6. undergrounds: belts pair entry to exit along the flow, pipes pair along `toward`
  -- the first underground of e's name along step, from the list or the world: it, its distance, whether it pairs
  local function walk_pair(e, step, maxd, pairs_with)
    local K = math.max(2 * maxd, 12)
    local ax, bx = e.pos[1] + step[1] * 0.6, e.pos[1] + step[1] * (K + 0.4)
    local ay, by = e.pos[2] + step[2] * 0.6, e.pos[2] + step[2] * (K + 0.4)
    local x0, x1, y0, y1 = math.min(ax, bx), math.max(ax, bx), math.min(ay, by), math.max(ay, by)
    if step[1] == 0 then x0, x1 = e.pos[1] - 0.4, e.pos[1] + 0.4 else y0, y1 = e.pos[2] - 0.4, e.pos[2] + 0.4 end
    local along = {}
    for _, w in pairs(s.find_entities_filtered{area = {{x0, y0}, {x1, y1}}, name = e.name}) do
      along[math.floor((w.position.x - e.pos[1]) * step[1] + (w.position.y - e.pos[2]) * step[2] + 0.5)] = w
    end
    for k = 1, K do
      local o = list_at(add(e.pos, scale(step, k)), function(x) return x.name == e.name end)
      local w, cand = along[k], nil
      if o then cand = {d = o.d, role = o.role, pos = o.pos, what = "entry " .. o.i}
      elseif w then cand = {d = w.direction, role = w.type == "underground-belt" and w.belt_to_ground_type or nil, pos = epos(w), what = "existing " .. ename(w)} end
      local ok = cand and pairs_with(cand)
      if ok ~= nil then return cand, k, ok end
    end
  end
  for _, e in ipairs(E) do
    if valid(e) and e.type == "underground-belt" and e.role and CARD[e.d] then
      local maxd = e.proto.max_underground_distance
      local step = e.role == "input" and CARD[e.d] or scale(CARD[e.d], -1)
      local want = e.role == "input" and "output" or "input"
      local cand, k, ok = walk_pair(e, step, maxd, function(c)
        if c.d ~= e.d and c.d ~= (e.d + 8) % 16 then return nil end   -- crossing at right angles: ignored
        return c.d == e.d and c.role == want
      end)
      if not cand or not ok then
        issue(e, "UNDERGROUND_UNPAIRED", "%s %s at %s has no %s within %d tiles %s%s: add one, flowing %s",
          e.name, e.role == "input" and "entry" or "exit", at(e.pos), e.role == "input" and "exit" or "entry", maxd, e.role == "input" and "ahead" or "behind",
          cand and string.format(" (%s at %s comes first and does not pair)", cand.what, at(cand.pos)) or "", DIR[e.d])
      elseif k > maxd then
        local better = {}
        for n, pr in pairs(prototypes.get_entity_filtered{{filter = "type", type = "underground-belt"}}) do
          if (pr.max_underground_distance or 0) >= k then better[#better + 1] = n end
        end
        table.sort(better)
        issue(e, "UNDERGROUND_TOO_LONG", "%s at %s pairs with %s at %s, %d tiles apart, but %s spans at most %d%s",
          e.name, at(e.pos), cand.what, at(cand.pos), k, e.name, maxd, #better > 0 and ": use " .. table.concat(better, " or ") .. ", or add a hop" or ": add a hop")
      end
    elseif valid(e) and e.type == "pipe-to-ground" and CARD[e.d] and static(e.proto).ug then
      local uc = static(e.proto).ug
      local myway = (uc.direction + e.d) % 16
      local cand, k, ok = walk_pair(e, CARD[myway], uc.max, function(c)
        local theirs = (uc.direction + c.d) % 16
        if theirs == (myway + 8) % 16 then return true end
        if theirs == myway then return false end
      end)
      if not cand or not ok then
        issue(e, "UNDERGROUND_UNPAIRED", "%s at %s has no partner within %d tiles toward %s%s: add one whose intent.toward points back",
          e.name, at(e.pos), uc.max, DIR[myway], cand and string.format(" (%s at %s comes first and faces the same way)", cand.what, at(cand.pos)) or "")
      elseif k > uc.max then
        issue(e, "UNDERGROUND_TOO_LONG", "%s at %s pairs with %s at %s, %d tiles apart, but it spans at most %d: add a hop", e.name, at(e.pos), cand.what, at(cand.pos), k, uc.max)
      else
        e.ug_partner = cand
      end
    end
  end

  -- 7. fluids: the engine lets a ghost join two fluids, so union the list's fluidboxes through their connections,
  -- then collect the fluids each group touches
  local parent, fluids, conns = {}, {}, {}
  local function key(i, k) return i .. ":" .. k end
  local function find(x) while parent[x] ~= x do parent[x] = parent[parent[x]] x = parent[x] end return x end
  local function union(a, b) a, b = find(a), find(b) if a ~= b then parent[a] = b end end
  local function touch(x, fluid, where) fluids[x] = fluids[x] or {} fluids[x][fluid] = fluids[x][fluid] or where end
  for _, e in ipairs(E) do
    if valid(e) and #static(e.proto).boxes > 0 then
      e.fluid, conns[e.i] = true, {}
      for _, fb in ipairs(static(e.proto).boxes) do
        local x = key(e.i, fb.key)
        parent[x] = x
        if fb.filter then touch(x, fb.filter, e.name .. " (entry " .. e.i .. ")") end
      end
      for _, c in ipairs(static(e.proto).conns) do
        local from = add(e.pos, c.rel[e.d])
        local cd = CARD[(c.direction + e.d) % 16]
        if cd then table.insert(conns[e.i], {fb = c.fb, from = from, target = add(from, cd)}) end
      end
    end
  end
  for _, e in ipairs(E) do
    for _, c in pairs(conns[e.i] or {}) do
      local x = key(e.i, c.fb)
      local o = list_at(c.target, function(y) return y.fluid end)
      if o then
        for _, oc in pairs(conns[o.i]) do
          if same_tile(oc.from, c.target) and same_tile(oc.target, c.from) then union(x, key(o.i, oc.fb)) end
        end
      else
        for _, w in pairs(world_at(c.target)) do
          for j = 1, w.type ~= "entity-ghost" and #static(w.prototype).boxes > 0 and w.fluids_count or 0 do
            local okc, wcs = pcall(function() return w.get_fluid_box_pipe_connections(j) end)
            for _, wc in pairs(okc and wcs or {}) do
              if (wc.connection_type or "normal") == "normal" and same_tile(vec(wc.target_position), c.from) then
                local fl = world_fluid(w, j)
                if fl then touch(x, fl, w.name .. " at " .. at(epos(w))) end
              end
            end
          end
        end
      end
    end
    if e.ug_partner then
      local o = list_at(e.ug_partner.pos, function(y) return y.name == e.name end)
      if o then union(key(e.i, 1), key(o.i, 1))
      else
        for _, w in pairs(world_at(e.ug_partner.pos)) do
          local fl = w.name == e.name and world_fluid(w, 1)
          if fl then touch(key(e.i, 1), fl, w.name .. " at " .. at(epos(w))) end
        end
      end
    end
  end
  local groups = {}
  for x in pairs(parent) do
    local r = find(x)
    groups[r] = groups[r] or {members = {}, fluids = {}}
    table.insert(groups[r].members, x)
    for fl, where in pairs(fluids[x] or {}) do groups[r].fluids[fl] = groups[r].fluids[fl] or where end
  end
  for _, g in pairs(groups) do
    local names = {}
    for fl, where in pairs(g.fluids) do names[#names + 1] = fl .. " (from " .. where .. ")" end
    if #names > 1 then
      table.sort(names)
      for _, x in pairs(g.members) do
        local e = E[tonumber(x:match("^(%d+):"))]
        issue(e, "FLUID_MIX", "%s at %s joins %s into one network: leave a one-tile gap, or route with pipe-to-ground", e.name, at(e.pos), table.concat(names, " and "))
      end
    end
  end
end

return {run = run}
