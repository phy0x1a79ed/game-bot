--- tool: intent
--- kind: lib
--- effect: read
--- summary: check a build list against stated intent: direction, reach, pairing, fluids, power, collisions
--- args: none (a lib: use("intent").check(surface, force, list, {accept = codes}))
--- returns: {MAX_ENTRIES, check, prepare, failures}
--- uses: core, joins
-- The checker behind check, route and place. A pure read.
-- check(surface, force, list, opts) returns {ok, entries = {{i, ok, direction, dir, type, position, issues}}, bom, summary}.
-- Each list entry is {name =, position = {x, y}, intent = {...}, accept = {CODE, ...}, direction = <optional raw>}:
--   inserter          drop = {dx, dy}          the side it drops on; item = name (optional) checks both ends handle it
--   mining-drill      output = {dx, dy}        the side it drops on
--   belt, splitter    flow = {dx, dy}
--   underground-belt  flow = {dx, dy}, role = "entry" | "exit"
--   pipe-to-ground    toward = {dx, dy}        the side its underground pipe leaves toward the partner
--   assembler         recipe = name (optional)
-- `accept` lists codes the caller intends, such as BELT_JOINS_FOREIGN when extending a line; they are reported, not failed.
-- opts.accept does the same for every entry. The engine answers placement; what only holds once the list is built
-- (arm targets, belt joins, pairing, fluid mixing, pole reach) is worked out here from the prototypes.

local C, J = use("core"), use("joins")
local CARD, DIR, at, vec, rot = C.CARD, C.DIR, C.at, C.vec, C.rot
local add, scale, epos, ename, static = C.add, C.scale, C.epos, C.ename, C.static
local EPS = 0.01
local MAX_ENTRIES = 200

-- entity types an inserter (or drill) can hand items to, and the ones it can also take them from
local TAKES = {}
for _, t in pairs{"container", "logistic-container", "infinity-container", "linked-container", "assembling-machine",
  "furnace", "rocket-silo", "lab", "boiler", "reactor", "burner-generator", "mining-drill", "transport-belt",
  "underground-belt", "splitter", "loader", "loader-1x1", "linked-belt", "cargo-wagon", "locomotive",
  "artillery-wagon", "car", "spider-vehicle", "ammo-turret", "artillery-turret", "roboport", "agricultural-tower",
  "asteroid-collector", "cargo-landing-pad", "space-platform-hub", "fusion-reactor", "heating-tower", "inserter-chest"} do
  TAKES[t] = true
end
local GIVES = {}
for t in pairs(TAKES) do GIVES[t] = true end
for _, t in pairs{"ammo-turret", "artillery-turret", "boiler", "reactor", "burner-generator", "heating-tower"} do GIVES[t] = nil end
local BELTS = {["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true}

local function dist(p, q) return math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2) end
local function shares(a, b) for l in pairs(a) do if b[l] then return true end end return false end
local function contains(b, p) return p[1] > b[1] + EPS and p[1] < b[3] - EPS and p[2] > b[2] + EPS and p[2] < b[4] - EPS end
local function overlap(a, b) return a[1] < b[3] - EPS and b[1] < a[3] - EPS and a[2] < b[4] - EPS and b[2] < a[4] - EPS end
local function cardinal(v) return math.abs(v[1]) > math.abs(v[2]) and {C.sgn(v[1]), 0} or {0, C.sgn(v[2])} end

-- the centre nearest (x, y) on proto's tile grid at direction d: odd sizes sit on half tiles, even sizes on tile corners
local function on_grid(proto, d, x, y)
  local w, h = proto.tile_width, proto.tile_height
  if d == 4 or d == 12 then w, h = h, w end
  local ox, oy = w % 2 == 1 and 0.5 or 0, h % 2 == 1 and 0.5 or 0
  return {math.floor(x - ox + 0.5) + ox, math.floor(y - oy + 0.5) + oy}
end

local function box(cb, d, p)
  local a, c = rot({cb[1], cb[2]}, d), rot({cb[3], cb[4]}, d)
  return {math.min(a[1], c[1]) + p[1], math.min(a[2], c[2]) + p[2], math.max(a[1], c[1]) + p[1], math.max(a[2], c[2]) + p[2]}
end

local function names_of(t) return table.concat(C.sorted(t), ", ") end

local function check(surface, force, list, opts)
  local s = (type(surface) == "string" or surface == nil) and game.surfaces[surface or "nauvis"] or surface
  local f = (type(force) == "string" or force == nil) and game.forces[force or "player"] or force
  local E, bom, every = {}, {}, {}
  for _, c in pairs(opts and opts.accept or {}) do every[c] = true end

  local function issue(e, code, msg, ...)
    msg = select("#", ...) > 0 and string.format(msg, ...) or msg
    for _, x in pairs(e.issues) do if x.code == code and x.msg == msg then return end end
    e.issues[#e.issues + 1] = {code = code, msg = msg}
  end

  -- normalise: prototype, direction from intent, snapped position, box
  for i, raw in ipairs(list) do
    local e = {i = i, name = raw.name, intent = type(raw.intent) == "table" and raw.intent or {}, issues = {}, accept = {}}
    for _, c in pairs(raw.accept or {}) do e.accept[c] = true end
    for c in pairs(every) do e.accept[c] = true end
    E[i] = e
    local proto = type(raw.name) == "string" and prototypes.entity[raw.name] or nil
    local p = vec(raw.position)
    if not proto then
      issue(e, "BAD_INTENT", "no entity named " .. tostring(raw.name))
    elseif not static(proto).placeable then
      issue(e, "BAD_INTENT", tostring(raw.name) .. " is not something a player can build")
    elseif not p then
      issue(e, "BAD_INTENT", "position must be {x, y}")
    else
      e.proto, e.type = proto, proto.type
      local it = e.intent
      local function need(key, what)
        local c = C.card(it[key])
        if not c then issue(e, "BAD_INTENT", "%s needs intent.%s = {dx, dy}, one axis only: %s", raw.name, key, what) end
        return c
      end
      local d
      if e.type == "inserter" then
        local c = need("drop", "the side it drops items on")
        local nv = vec(proto.inserter_drop_position)
        if c then d = C.dir_of(c, nv) end
        local dv = vec(it.drop)
        local mag = dv and math.max(math.abs(dv[1]), math.abs(dv[2]))
        local reach = math.floor(math.abs(nv[2]) + 0.5)
        if mag and mag > 1 and mag ~= reach then
          issue(e, "BAD_INTENT", "%s reaches %d tile(s), not %d: give drop as a unit side, or pick another inserter", raw.name, reach, mag)
        end
      elseif e.type == "mining-drill" then
        local c = need("output", "the side it drops ore on")
        if c then d = C.dir_of(c, vec(proto.vector_to_place_result)) end
      elseif C.BELT_TYPES[e.type] then
        local c = need("flow", "the way items move")
        if c then d = C.dir_of(c) end
        if e.type == "underground-belt" then
          e.role = it.role == "entry" and "input" or it.role == "exit" and "output" or nil
          if not e.role then issue(e, "BAD_INTENT", "underground-belt needs intent.role = \"entry\" or \"exit\"") end
        end
      elseif e.type == "pipe-to-ground" then
        local c = need("toward", "the side its underground pipe leaves toward the partner")
        local ug = static(proto).ug
        if c and ug then d = C.dir_of(c, CARD[ug.direction]) end
      end
      if raw.direction ~= nil then
        local rd = type(raw.direction) == "string" and defines.direction[raw.direction] or raw.direction
        if type(rd) ~= "number" or rd % 4 ~= 0 then
          issue(e, "BAD_INTENT", "direction %s is a diagonal in 2.x's 16-way encoding (2 = northeast, 6 = southeast): "
            .. "state intent instead, or use defines.direction (east = 4, south = 8, west = 12)", tostring(raw.direction))
        elseif d and rd ~= d then
          issue(e, "BAD_INTENT", "direction %d (%s) contradicts the intent, which needs %d (%s): drop the raw direction", rd, DIR[rd], d, DIR[d])
        elseif not d then d = rd end
      end
      e.d = d or 0
      e.pos = on_grid(proto, e.d, p[1], p[2])
      local st = static(proto)
      e.box, e.layers = box(st.cb, e.d, e.pos), st.layers
      if st.item then bom[st.item.name] = (bom[st.item.name] or 0) + (st.item.count or 1) end
    end
  end

  local function valid(e) return e.proto ~= nil end
  -- the entries by the tiles their boxes cover, in list order
  local by_tile = {}
  local function tile_key(x, y) return x * 65536 + y end
  local function tiles(b, fn)
    for x = math.floor(b[1] + EPS), math.ceil(b[3] - EPS) - 1 do
      for y = math.floor(b[2] + EPS), math.ceil(b[4] - EPS) - 1 do fn(x, y) end
    end
  end
  for _, o in ipairs(E) do
    if valid(o) then
      tiles(o.box, function(x, y)
        local k = tile_key(x, y)
        by_tile[k] = by_tile[k] or {}
        table.insert(by_tile[k], o)
      end)
    end
  end
  local function list_at(p, pred)
    for _, o in ipairs(by_tile[tile_key(math.floor(p[1]), math.floor(p[2]))] or {}) do
      if contains(o.box, p) and (not pred or pred(o)) then return o end
    end
  end
  local world_cache = {}
  local function world_at(p)
    local k = string.format("%.3f,%.3f", p[1], p[2])
    world_cache[k] = world_cache[k] or C.entities_at(s, p)
    return world_cache[k]
  end

  -- 1. collisions inside the list
  local tested = {}
  for _, bucket in pairs(by_tile) do
    for x = 1, #bucket - 1 do
      for y = x + 1, #bucket do
        local A, B = bucket[x], bucket[y]
        if A.i > B.i then A, B = B, A end
        local pair = A.i * 4096 + B.i
        if not tested[pair] then
          tested[pair] = true
          if overlap(A.box, B.box) and shares(A.layers, B.layers) then
            issue(A, "COLLIDES_LIST", "%s at %s overlaps entry %d (%s at %s): move one of them", A.name, at(A.pos), B.i, B.name, at(B.pos))
            issue(B, "COLLIDES_LIST", "%s at %s overlaps entry %d (%s at %s): move one of them", B.name, at(B.pos), A.i, A.name, at(A.pos))
          end
        end
      end
    end
  end

  -- 2. collisions with the world: the engine decides; the footprint must also be empty, because the engine passes a
  -- ghost that would rotate or fast-replace what stands there. Drills skip the engine, which refuses them off ore.
  for _, e in ipairs(E) do
    if valid(e) then
      local b = e.box
      local hit = false
      for _, w in pairs(s.find_entities_filtered{area = {{b[1] + EPS, b[2] + EPS}, {b[3] - EPS, b[4] - EPS}}}) do
        if not C.IGNORED[w.type] and shares(e.layers, static(C.proto_of(w)).layers) then
          hit = true
          issue(e, "COLLIDES_WORLD", "%s at %s is blocked by %s at %s: pick a free spot or remove it first", e.name, at(e.pos), ename(w), at(epos(w)))
        end
      end
      local engine = e.type == "mining-drill" or s.can_place_entity{name = e.name, position = e.pos, direction = e.d,
        force = f, build_check_type = defines.build_check_type.manual_ghost}
      if not hit and (not engine or e.type == "mining-drill") then
        local blocked = 0
        tiles(b, function(x, y)
          local tp = s.get_tile(x, y).prototype
          if shares(e.layers, tp.collision_mask and tp.collision_mask.layers or {}) then blocked = blocked + 1 end
        end)
        if blocked > 0 then
          issue(e, "COLLIDES_WORLD", "%s at %s sits on %d tile(s) it cannot be built on (water or similar)", e.name, at(e.pos), blocked)
        elseif not engine then
          issue(e, "COLLIDES_WORLD", "the engine refuses %s at %s (terrain, map edge or a build rule)", e.name, at(e.pos))
        end
      end
    end
  end

  -- what a pickup or drop target makes, uses or holds, for intent.item: {makes, uses, holds, belt, what, uses_what}
  local function item_view(obj)
    local v, rec = {}, nil
    if obj.e then
      rec = obj.e.intent.recipe and prototypes.recipe[obj.e.intent.recipe]
    elseif obj.w.type ~= "entity-ghost" then
      local w = obj.w
      if w.type == "assembling-machine" or w.type == "furnace" then
        local ok, r = pcall(w.get_recipe)
        rec = ok and r and (r.prototype or r) or nil
      elseif BELTS[w.type] then
        v.belt, v.holds = true, {}
        for _, n in ipairs(C.carried(w)) do v.holds[n] = true end
      elseif w.type == "container" or w.type == "logistic-container" then
        v.holds = {}
        local inv = w.get_inventory(defines.inventory.chest)
        for _, c in pairs(inv and inv.get_contents() or {}) do v.holds[c.name] = true end
      end
      if v.holds then v.what = names_of(v.holds) end
    end
    if rec then
      v.makes, v.uses = {}, {}
      for _, p in pairs(rec.products or {}) do v.makes[p.name] = true end
      for _, p in pairs(rec.ingredients or {}) do v.uses[p.name] = true end
      v.what, v.uses_what = names_of(v.makes), names_of(v.uses)
    end
    return v
  end
  -- what an inserter or drill reaches at p: a description, the name of whatever else stands there, and the target
  local function target_at(p, types)
    local o = list_at(p)
    if o then return types[o.type] and o.name .. " (entry " .. o.i .. ")", o.name, types[o.type] and {e = o} end
    local other
    for _, w in pairs(world_at(p)) do
      if types[C.type_of(w)] then return ename(w) .. " at " .. at(epos(w)), nil, {w = w} end
      other = other or ename(w)
    end
    return nil, other
  end
  -- a target one tile nearer or farther along the same side means the arm length is wrong
  local function reach_hint(e, types, v)
    local n = math.floor(math.max(math.abs(v[1]), math.abs(v[2])) + 0.5)
    for k = 1, 3 do
      local t = k ~= n and target_at(add(e.pos, scale(cardinal(v), k)), types)
      if t then return string.format("; %s sits %d tile(s) out on that side, but %s reaches %d", t, k, e.name, n) end
    end
    return ""
  end

  -- 3. inserters: something to pick from, something to drop into
  for _, e in ipairs(E) do
    if valid(e) and e.type == "inserter" then
      local pv, dv = rot(vec(e.proto.inserter_pickup_position), e.d), rot(vec(e.proto.inserter_drop_position), e.d)
      e.pick, e.drop = add(e.pos, pv), add(e.pos, dv)
      local src, other, sobj = target_at(e.pick, GIVES)
      if not src then
        issue(e, "INSERTER_PICKS_NOTHING", "%s at %s picks from %s (the %s side)%s%s: put the source there, or flip intent.drop",
          e.name, at(e.pos), at(e.pick), DIR[C.dir_of(cardinal(pv))], other and (", which holds " .. other .. " and gives no items") or ", which is empty",
          reach_hint(e, GIVES, pv))
      end
      local dst, other2, dobj = target_at(e.drop, TAKES)
      if not dst then
        issue(e, "INSERTER_DROPS_ON_GROUND", "%s at %s drops at %s (the %s side)%s%s: put the target there, or flip intent.drop",
          e.name, at(e.pos), at(e.drop), DIR[C.dir_of(cardinal(dv))], other2 and (", onto " .. other2 .. ", which takes no items") or ", which is empty",
          reach_hint(e, TAKES, dv))
      end
      local item = e.intent.item
      if item and not prototypes.item[item] then
        issue(e, "BAD_INTENT", "no item named " .. tostring(item))
      elseif item then
        local why = {}
        local ps, ds = sobj and item_view(sobj), dobj and item_view(dobj)
        if ps and ps.makes and not ps.makes[item] then
          why[#why + 1] = string.format("it picks from %s, which makes %s, not %s", src, ps.what, item)
        elseif ps and ps.holds and next(ps.holds) and not ps.holds[item] then
          why[#why + 1] = string.format("it picks from %s, which holds %s, not %s", src, ps.what, item)
        end
        if ds and ds.uses and not ds.uses[item] then
          why[#why + 1] = string.format("it drops into %s, which uses %s, not %s", dst, ds.uses_what, item)
        elseif ds and ds.belt and next(ds.holds) and not ds.holds[item] then
          why[#why + 1] = string.format("it drops onto %s, which carries %s, not %s", dst, ds.what, item)
        end
        if #why > 0 then
          issue(e, "INSERTER_WRONG_ITEM", "%s at %s is meant to move %s, but %s: if the arm is backwards, flip intent.drop",
            e.name, at(e.pos), item, table.concat(why, "; "))
        end
      end
    end
  end

  -- 4. drills: ore under the mining area, and somewhere to drop
  for _, e in ipairs(E) do
    if valid(e) and e.type == "mining-drill" then
      local r = e.proto.mining_drill_radius or 0
      local cats, n = e.proto.resource_categories or {}, 0
      for _, res in pairs(s.find_entities_filtered{area = {{e.pos[1] - r, e.pos[2] - r}, {e.pos[1] + r, e.pos[2] + r}}, type = "resource"}) do
        if cats[res.prototype.resource_category] then n = n + 1 end
      end
      if n == 0 then
        local near = s.find_entities_filtered{position = e.pos, radius = 24, type = "resource"}
        local best = near[1] and s.get_closest(e.pos, near)
        issue(e, "DRILL_NO_ORE", "%s at %s has no minable resource in its %.1f-tile mining area%s", e.name, at(e.pos), 2 * r,
          best and string.format("; nearest is %s at %s", best.name, at(epos(best))) or "; none within 24 tiles")
      end
      if e.proto.vector_to_place_result then
        e.drop = add(e.pos, rot(vec(e.proto.vector_to_place_result), e.d))
        local dst, other = target_at(e.drop, TAKES)
        if not dst then
          issue(e, "DRILL_DROPS_ON_GROUND", "%s at %s drops at %s%s: put a belt or chest there, or change intent.output",
            e.name, at(e.pos), at(e.drop), other and (", onto " .. other .. ", which takes no items") or ", which is empty")
        end
      end
    end
  end

  -- 5-7. belts, undergrounds and fluids
  J.run({s = s, E = E, issue = issue, list_at = list_at, world_at = world_at, valid = valid})

  -- 8. poles: each must reach a pole already on a network, directly or through other list poles
  local poles, linked = {}, {}
  local function reach(p) return p.get_max_wire_distance() end
  for _, e in ipairs(E) do
    if valid(e) and e.type == "electric-pole" then
      poles[#poles + 1] = e
      for _, w in pairs(s.find_entities_filtered{position = e.pos, radius = reach(e.proto) + 0.01, type = "electric-pole", force = f}) do
        if dist(epos(w), e.pos) <= math.min(reach(e.proto), reach(w.prototype)) + 1e-6 then linked[e.i] = true end
      end
    end
  end
  local queue, head = {}, 1
  for _, e in ipairs(poles) do if linked[e.i] then queue[#queue + 1] = e end end
  while head <= #queue do
    local a = queue[head]
    head = head + 1
    for _, b in ipairs(poles) do
      if not linked[b.i] and dist(a.pos, b.pos) <= math.min(reach(a.proto), reach(b.proto)) + 1e-6 then
        linked[b.i] = true
        queue[#queue + 1] = b
      end
    end
  end
  local hints = 0
  for _, e in ipairs(poles) do
    if not linked[e.i] then
      hints = hints + 1
      local near = hints <= 5 and s.find_entities_filtered{position = e.pos, radius = 64, type = "electric-pole", force = f} or {}
      local best = near[1] and s.get_closest(e.pos, near)
      local hint = hints <= 5 and "; no pole within 64 tiles" or ""
      if best then
        hint = string.format("; nearest is %s at %s, %.1f tiles away, and the wire reaches %.1f: add a pole between",
          best.name, at(epos(best)), dist(epos(best), e.pos), math.min(reach(e.proto), reach(best.prototype)))
      end
      issue(e, "POLE_ISLAND", "%s at %s reaches no pole on a network, directly or through the list%s", e.name, at(e.pos), hint)
    end
  end

  -- 9. assembler recipes
  for _, e in ipairs(E) do
    local r = e.intent.recipe
    if valid(e) and r then
      local rec = f.recipes[r]
      if not rec then issue(e, "BAD_RECIPE", "no recipe named " .. tostring(r))
      else
        local cats, can = rec.prototype.categories or {}, false
        for _, c in pairs(cats) do if (e.proto.crafting_categories or {})[c] then can = true end end
        if not can then issue(e, "BAD_RECIPE", "%s cannot craft %s (category %s)", e.name, r, table.concat(cats, ", "))
        elseif not rec.enabled then issue(e, "BAD_RECIPE", r .. " is not researched yet") end
      end
    end
  end

  -- result
  local out, counts, nok, accepted = {}, {}, 0, 0
  for _, e in ipairs(E) do
    local issues, acc = {}, {}
    for _, x in ipairs(e.issues) do
      if e.accept[x.code] then acc[#acc + 1] = x else issues[#issues + 1] = x counts[x.code] = (counts[x.code] or 0) + 1 end
    end
    accepted = accepted + #acc
    local r = {i = e.i, ok = #issues == 0, direction = e.d, dir = e.d and DIR[e.d], issues = issues,
      pick = e.pick and C.xy(e.pick), drop = e.drop and C.xy(e.drop), position = e.pos and {e.pos[1], e.pos[2]}, type = e.role}
    if #acc > 0 then r.accepted = acc end
    if r.ok then nok = nok + 1 end
    out[#out + 1] = r
  end
  local parts, items = {}, {}
  for c, n in pairs(counts) do parts[#parts + 1] = c .. " x" .. n end
  for n, c in pairs(bom) do items[#items + 1] = c .. " " .. n end
  table.sort(parts)
  table.sort(items)
  local summary = string.format("%d of %d entries ok%s%s; needs %s", nok, #E,
    #parts > 0 and ": " .. table.concat(parts, ", ") or "", accepted > 0 and string.format(" (%d accepted)", accepted) or "",
    #items > 0 and table.concat(items, ", ") or "nothing")
  return {ok = nok == #E, entries = out, bom = bom, counts = counts, summary = summary}
end

-- the surface, force, list and accept of a tool call, or nil and an {error, hint} table
local function prepare(a)
  local function bad(msg, hint) return nil, C.fail(msg, hint) end
  if type(a) ~= "table" then return bad("no arguments", "pass a table with a list of entries") end
  local s, f = C.world(a)
  if not s then return nil, f end
  local list = a.list
  local SHAPE = "each entry is {name, position = {x, y}, intent = {...}}"
  if type(list) ~= "table" or #list == 0 or next(list, #list) ~= nil then return bad("list must be a non-empty array of entries", SHAPE) end
  if #list > MAX_ENTRIES then return bad(#list .. " entries is too many", "send at most " .. MAX_ENTRIES .. " per call, in several calls") end
  for i, raw in ipairs(list) do
    if type(raw) ~= "table" then return bad("entry " .. i .. " is not a table", SHAPE) end
    if raw.name ~= nil and type(raw.name) ~= "string" then return bad("entry " .. i .. " has a non-text name", "name is an entity name such as transport-belt") end
    if raw.intent ~= nil and type(raw.intent) ~= "table" then return bad("entry " .. i .. " has a non-table intent", "intent is a table such as {flow = {1, 0}}") end
    for _, k in ipairs{"item", "recipe", "role"} do
      local v = raw.intent and raw.intent[k]
      if v ~= nil and type(v) ~= "string" then return bad("entry " .. i .. " has a non-text intent." .. k, "intent." .. k .. " is a name") end
    end
    if raw.accept ~= nil and type(raw.accept) ~= "table" then return bad("entry " .. i .. " has a non-list accept", "accept is a list of codes") end
  end
  if a.accept ~= nil and type(a.accept) ~= "table" then return bad("accept must be a list of codes", "for example {\"BELT_JOINS_FOREIGN\"}") end
  return {surface = s, force = f, list = list, accept = a.accept}
end

-- the failing entries of a check result as a flat list of {i, name, position, code, msg}
local function failures(list, res)
  local out = {}
  for i, r in ipairs(res.entries) do
    for _, x in ipairs(r.issues) do out[#out + 1] = {i = i, name = list[i].name, position = r.position, code = x.code, msg = x.msg} end
  end
  return out
end

return {MAX_ENTRIES = MAX_ENTRIES, check = check, prepare = prepare, failures = failures}
