--- tool: intent
--- kind: lib
--- effect: read
--- summary: check a build list against stated intent: direction, reach, pairing, fluids, power, collisions
--- args: none (a lib: use("intent").check(surface, force, list, {accept = codes}))
--- returns: {check, prepare, occupied, failures}
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
-- opts.accept does the same for every entry. Directions, reach, boxes and pairing distances come from prototypes;
-- positions snap to the entity's tile grid.

local D = defines.direction
local CARD = {[0] = {0, -1}, [4] = {1, 0}, [8] = {0, 1}, [12] = {-1, 0}}
local DIR_NAME = {} for k, v in pairs(D) do DIR_NAME[v] = k end
local EPS = 0.01

-- entity types an inserter (or drill) can hand items to or take them from
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
local FLOW_TYPES = {["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true, loader = true,
  ["loader-1x1"] = true, ["linked-belt"] = true}

local function sgn(v) return v > 0.001 and 1 or (v < -0.001 and -1 or 0) end
local function V(v)
  if type(v) ~= "table" then return nil end
  local x, y = v.x or v[1], v.y or v[2]
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  return {x, y}
end
local function add(a, b) return {a[1] + b[1], a[2] + b[2]} end
local function scale(v, k) return {v[1] * k, v[2] * k} end
local function at(p) return string.format("(%.1f, %.1f)", p[1], p[2]) end
local function tile(p) return math.floor(p[1]), math.floor(p[2]) end
local function same_tile(a, b) local ax, ay = tile(a) local bx, by = tile(b) return ax == bx and ay == by end
local function centre(p) local x, y = tile(p) return {x + 0.5, y + 0.5} end
local function epos(e) return {e.position.x, e.position.y} end

-- rotate a vector defined for a north-facing entity to cardinal direction d (clockwise, y down)
local function rot(v, d)
  local x, y = v[1] or v.x, v[2] or v.y
  for _ = 1, math.floor(d / 4) % 4 do x, y = -y, x end
  return {x, y}
end
local function cardinal_of(v)
  if math.abs(v[1]) > math.abs(v[2]) then return {sgn(v[1]), 0} end
  return {0, sgn(v[2])}
end
local function intent_card(v)
  if not v or not v[1] or not v[2] then return nil end
  local x, y = sgn(v[1]), sgn(v[2])
  if (x ~= 0) == (y ~= 0) then return nil end
  return {x, y}
end
-- the cardinal direction d at which north-based vector nv points along card
local function dir_for(nv, card)
  for d = 0, 12, 4 do
    local c = cardinal_of(rot(nv, d))
    if c[1] == card[1] and c[2] == card[2] then return d end
  end
end
local function dir_of_card(card) return dir_for({0, -1}, card) end

local function box(proto, d, p)
  local b = proto.collision_box
  local a, c = rot({b.left_top.x, b.left_top.y}, d), rot({b.right_bottom.x, b.right_bottom.y}, d)
  return {math.min(a[1], c[1]) + p[1], math.min(a[2], c[2]) + p[2], math.max(a[1], c[1]) + p[1], math.max(a[2], c[2]) + p[2]}
end
local function contains(bx, p) return p[1] > bx[1] + EPS and p[1] < bx[3] - EPS and p[2] > bx[2] + EPS and p[2] < bx[4] - EPS end
local function overlap(a, b) return a[1] < b[3] - EPS and b[1] < a[3] - EPS and a[2] < b[4] - EPS and b[2] < a[4] - EPS end

-- the centre nearest (x, y) on proto's tile grid at direction d: odd sizes sit on half tiles, even sizes on tile corners
local function on_grid(proto, d, x, y)
  local w, h = proto.tile_width, proto.tile_height
  if d == 4 or d == 12 then w, h = h, w end
  local ox, oy = w % 2 == 1 and 0.5 or 0, h % 2 == 1 and 0.5 or 0
  return {math.floor(x - ox + 0.5) + ox, math.floor(y - oy + 0.5) + oy}
end

local function layers(proto) return proto.collision_mask and proto.collision_mask.layers or {} end
local function shares(a, b) for l in pairs(a) do if b[l] then return true end end return false end

local function ename(e) return e.name == "entity-ghost" and e.ghost_name .. " ghost" or e.name end
local function etype(e) return e.name == "entity-ghost" and e.ghost_type or e.type end
local function eproto(e) return e.name == "entity-ghost" and e.ghost_prototype or e.prototype end

-- the underground connection of a pipe-to-ground prototype, as {direction, max} for a north-facing entity
local function underground_conn(proto)
  for _, fb in pairs(proto.fluidbox_prototypes or {}) do
    for _, c in pairs(fb.pipe_connections or {}) do
      if c.connection_type == "underground" then return {direction = c.direction, max = c.max_underground_distance} end
    end
  end
end

-- normal pipe connections of proto facing d at p: {fb, from = tile centre inside, target = tile centre outside}
local function pipe_conns(proto, d, p)
  local out = {}
  for k, fb in pairs(proto.fluidbox_prototypes or {}) do
    for _, c in pairs(fb.pipe_connections or {}) do
      if (c.connection_type or "normal") == "normal" and c.direction then
        local rel = c.positions and c.positions[math.floor(d / 4) + 1] or rot(V(c.position) or {0, 0}, d)
        rel = V(rel)
        local from = add(p, rel)
        local cd = (c.direction + d) % 16
        if CARD[cd] then out[#out + 1] = {fb = fb.index or k, from = from, target = add(from, CARD[cd])} end
      end
    end
  end
  return out
end

-- the fluid in world entity e's storage j, or in the segment it belongs to, or its filter (2.1 fluid API)
local function world_fluid(e, j)
  for _, get in pairs{"get_fluid_segment_fluid", "get_fluid", "get_fluid_segment_filter", "get_fluid_filter"} do
    local ok, fl = pcall(e[get], j)
    if ok and fl and fl.name then return fl.name end
  end
end

local function check(surface, force, list, opts)
  local s = (type(surface) == "string" or surface == nil) and game.surfaces[surface or "nauvis"] or surface
  local f = (type(force) == "string" or force == nil) and game.forces[force or "player"] or force
  local E, bom = {}, {}
  local every = {}
  for _, c in pairs(opts and opts.accept or {}) do every[c] = true end

  local function issue(e, code, msg)
    for _, x in pairs(e.issues) do if x.code == code and x.msg == msg then return end end
    e.issues[#e.issues + 1] = {code = code, msg = msg}
  end

  -- normalise: prototype, direction from intent, snapped position, box
  for i, raw in ipairs(list) do
    local e = {i = i, name = raw.name, intent = type(raw.intent) == "table" and raw.intent or {}, issues = {}, accept = {}}
    for _, c in pairs(raw.accept or {}) do e.accept[c] = true end
    for c in pairs(every) do e.accept[c] = true end
    E[i] = e
    local proto = prototypes.entity[raw.name or ""]
    local p = V(raw.position)
    if not proto then
      issue(e, "BAD_INTENT", "no entity named " .. tostring(raw.name))
    elseif not p then
      issue(e, "BAD_INTENT", "position must be {x, y}")
    else
      e.proto, e.type = proto, proto.type
      local it = e.intent
      local function need(key, what)
        local c = intent_card(V(it[key]))
        if not c then issue(e, "BAD_INTENT", string.format("%s needs intent.%s = {dx, dy}, one axis only: %s", raw.name, key, what)) end
        return c
      end
      local d
      if e.type == "inserter" then
        local c = need("drop", "the side it drops items on")
        if c then d = dir_for(V(proto.inserter_drop_position), c) end
        local dv = V(it.drop)
        local mag = dv and math.max(math.abs(dv[1]), math.abs(dv[2]))
        local reach = math.floor(math.abs(V(proto.inserter_drop_position)[2]) + 0.5)
        if mag and mag > 1 and mag ~= reach then
          issue(e, "BAD_INTENT", string.format("%s reaches %d tile(s), not %d: give drop as a unit side, or pick another inserter", raw.name, reach, mag))
        end
      elseif e.type == "mining-drill" then
        local c = need("output", "the side it drops ore on")
        if c then d = dir_for(V(proto.vector_to_place_result), c) end
      elseif FLOW_TYPES[e.type] then
        local c = need("flow", "the way items move")
        if c then d = dir_of_card(c) end
        if e.type == "underground-belt" then
          e.role = it.role == "entry" and "input" or it.role == "exit" and "output" or nil
          if not e.role then issue(e, "BAD_INTENT", "underground-belt needs intent.role = \"entry\" or \"exit\"") end
        end
      elseif e.type == "pipe-to-ground" then
        local c = need("toward", "the side its underground pipe leaves toward the partner")
        local uc = underground_conn(proto)
        if c and uc then d = dir_for(CARD[uc.direction], c) end
      end
      if raw.direction ~= nil then
        local rd = type(raw.direction) == "string" and D[raw.direction] or raw.direction
        if type(rd) ~= "number" or rd % 4 ~= 0 then
          issue(e, "BAD_INTENT", string.format("direction %s is a diagonal in 2.x's 16-way encoding (2 = northeast, 6 = southeast): "
            .. "state intent instead, or use defines.direction (east = 4, south = 8, west = 12)", tostring(raw.direction)))
        elseif d and rd ~= d then
          issue(e, "BAD_INTENT", string.format("direction %d (%s) contradicts the intent, which needs %d (%s): drop the raw direction",
            rd, DIR_NAME[rd], d, DIR_NAME[d]))
        elseif not d then d = rd end
      end
      e.d = d or 0
      e.pos = on_grid(proto, e.d, p[1], p[2])
      e.box = box(proto, e.d, e.pos)
      e.layers = layers(proto)
      local item = proto.items_to_place_this and proto.items_to_place_this[1]
      if item then bom[item.name] = (bom[item.name] or 0) + (item.count or 1) end
    end
  end

  local function valid(e) return e.proto ~= nil end
  local function list_at(p, pred)
    for _, o in ipairs(E) do
      if valid(o) and contains(o.box, p) and (not pred or pred(o)) then return o end
    end
  end
  local function world_at(p)
    local out = {}
    for _, w in pairs(s.find_entities_filtered{position = p}) do
      if w.type ~= "resource" and w.type ~= "item-entity" and w.type ~= "corpse" and w.type ~= "character"
        and not w.type:find("robot") then out[#out + 1] = w end
    end
    return out
  end

  -- 1. collisions inside the list
  for a = 1, #E do
    local A = E[a]
    if valid(A) then
      for b = a + 1, #E do
        local B = E[b]
        if valid(B) and overlap(A.box, B.box) and shares(A.layers, B.layers) then
          issue(A, "COLLIDES_LIST", string.format("%s at %s overlaps entry %d (%s at %s): move one of them", A.name, at(A.pos), b, B.name, at(B.pos)))
          issue(B, "COLLIDES_LIST", string.format("%s at %s overlaps entry %d (%s at %s): move one of them", B.name, at(B.pos), a, A.name, at(A.pos)))
        end
      end
    end
  end

  -- 2. collisions with the world
  for _, e in ipairs(E) do
    if valid(e) then
      local bx = e.box
      local area = {{bx[1] + EPS, bx[2] + EPS}, {bx[3] - EPS, bx[4] - EPS}}
      local hit = false
      for _, w in pairs(s.find_entities_filtered{area = area}) do
        local wp = eproto(w)
        if wp and w.type ~= "character" and not w.type:find("robot") and shares(e.layers, layers(wp)) then
          hit = true
          issue(e, "COLLIDES_WORLD", string.format("%s at %s is blocked by %s at %s: pick a free spot or remove it first",
            e.name, at(e.pos), ename(w), at(epos(w))))
        end
      end
      local ls = {} for l in pairs(e.layers) do ls[#ls + 1] = l end
      local water = #ls > 0 and s.count_tiles_filtered{area = area, collision_mask = ls} or 0
      if water > 0 then
        hit = true
        issue(e, "COLLIDES_WORLD", string.format("%s at %s sits on %d tile(s) it cannot be built on (water or similar)", e.name, at(e.pos), water))
      end
      if not hit and e.type ~= "mining-drill" and not s.can_place_entity{name = e.name, position = e.pos, direction = e.d,
          force = f, build_check_type = defines.build_check_type.manual_ghost} then
        issue(e, "COLLIDES_WORLD", string.format("the engine refuses %s at %s (terrain, map edge or a build rule)", e.name, at(e.pos)))
      end
    end
  end

  -- what an inserter or drill reaches at point p: a list entry or a world entity of a type that handles items
  -- what a pickup or drop target makes, uses or holds, for intent.item: {makes, uses, holds, belt, what, uses_what}
  local item_view
  local function names_of(t) local n = {} for k in pairs(t) do n[#n + 1] = k end table.sort(n) return table.concat(n, ", ") end
  item_view = function(obj)
    local v, rec = {}, nil
    if obj.e then
      local r = obj.e.intent.recipe
      rec = r and prototypes.recipe[r]
    else
      local w = obj.w
      if w.name ~= "entity-ghost" and (w.type == "assembling-machine" or w.type == "furnace") then
        local ok, r = pcall(w.get_recipe)
        rec = ok and r or nil
        if rec and rec.prototype then rec = rec.prototype end
      end
      if w.name ~= "entity-ghost" and BELTS[w.type] then
        v.belt, v.holds = true, {}
        for k = 1, w.get_max_transport_line_index() do
          for _, c in pairs(w.get_transport_line(k).get_contents()) do v.holds[c.name] = true end
        end
        v.what = names_of(v.holds)
      elseif w.name ~= "entity-ghost" and (w.type == "container" or w.type == "logistic-container") then
        v.holds = {}
        local inv = w.get_inventory(defines.inventory.chest)
        for _, c in pairs(inv and inv.get_contents() or {}) do v.holds[c.name] = true end
        v.what = names_of(v.holds)
      end
    end
    if rec then
      v.makes, v.uses = {}, {}
      for _, p in pairs(rec.products or {}) do v.makes[p.name] = true end
      for _, p in pairs(rec.ingredients or {}) do v.uses[p.name] = true end
      v.what, v.uses_what = names_of(v.makes), names_of(v.uses)
    end
    return v
  end
  local function target_at(p, types)
    local o = list_at(p)
    if o then return types[o.type] and o.name .. " (entry " .. o.i .. ")", o.name, types[o.type] and {e = o} end
    local other
    for _, w in pairs(world_at(p)) do
      if types[etype(w)] then return ename(w) .. " at " .. at(epos(w)), nil, {w = w} end
      other = other or ename(w)
    end
    return nil, other
  end
  local function reach_hint(e, side, vec)
    -- a target one tile nearer or farther along the same side means the arm length is wrong
    local n = math.floor(math.max(math.abs(vec[1]), math.abs(vec[2])) + 0.5)
    local unit = cardinal_of(vec)
    for _, k in pairs{1, 2, 3} do
      if k ~= n then
        local t = target_at(add(e.pos, scale(unit, k)), side == "pick" and GIVES or TAKES)
        if t then return string.format("; %s sits %d tile(s) out on that side, but %s reaches %d", t, k, e.name, n) end
      end
    end
    return ""
  end

  -- 3. inserters: something to pick from, something to drop into
  for _, e in ipairs(E) do
    if valid(e) and e.type == "inserter" then
      local pv = rot(V(e.proto.inserter_pickup_position), e.d)
      local dv = rot(V(e.proto.inserter_drop_position), e.d)
      local pp, dp = add(e.pos, pv), add(e.pos, dv)
      e.pick, e.drop = pp, dp
      local src, other, sobj = target_at(pp, GIVES)
      if not src then
        issue(e, "INSERTER_PICKS_NOTHING", string.format("%s at %s picks from %s (the %s side)%s%s: put the source there, or flip intent.drop",
          e.name, at(e.pos), at(pp), DIR_NAME[dir_of_card(cardinal_of(pv))], other and (", which holds " .. other .. " and gives no items") or ", which is empty",
          reach_hint(e, "pick", pv)))
      end
      local dst, other2, dobj = target_at(dp, TAKES)
      if not dst then
        issue(e, "INSERTER_DROPS_ON_GROUND", string.format("%s at %s drops at %s (the %s side)%s%s: put the target there, or flip intent.drop",
          e.name, at(e.pos), at(dp), DIR_NAME[dir_of_card(cardinal_of(dv))], other2 and (", onto " .. other2 .. ", which takes no items") or ", which is empty",
          reach_hint(e, "drop", dv)))
      end
      local item = e.intent.item
      if item and not prototypes.item[item] then
        issue(e, "BAD_INTENT", "no item named " .. tostring(item))
      elseif item then
        local why = {}
        local ps = sobj and item_view(sobj)
        if ps and ps.makes and not ps.makes[item] then
          why[#why + 1] = string.format("it picks from %s, which makes %s, not %s", src, ps.what, item)
        elseif ps and ps.holds and next(ps.holds) and not ps.holds[item] then
          why[#why + 1] = string.format("it picks from %s, which holds %s, not %s", src, ps.what, item)
        end
        local ds = dobj and item_view(dobj)
        if ds and ds.uses and not ds.uses[item] then
          why[#why + 1] = string.format("it drops into %s, which uses %s, not %s", dst, ds.uses_what, item)
        elseif ds and ds.holds and ds.belt and next(ds.holds) and not ds.holds[item] then
          why[#why + 1] = string.format("it drops onto %s, which carries %s, not %s", dst, ds.what, item)
        end
        if #why > 0 then
          issue(e, "INSERTER_WRONG_ITEM", string.format("%s at %s is meant to move %s, but %s: if the arm is backwards, flip intent.drop",
            e.name, at(e.pos), item, table.concat(why, "; ")))
        end
      end
    end
  end

  -- 4. drills: ore under the mining area, and somewhere to drop
  for _, e in ipairs(E) do
    if valid(e) and e.type == "mining-drill" then
      local r = e.proto.mining_drill_radius or 0
      local area = {{e.pos[1] - r, e.pos[2] - r}, {e.pos[1] + r, e.pos[2] + r}}
      local cats, n = e.proto.resource_categories or {}, 0
      for _, res in pairs(s.find_entities_filtered{area = area, type = "resource"}) do
        if cats[res.prototype.resource_category] then n = n + 1 end
      end
      if n == 0 then
        local near = s.find_entities_filtered{position = e.pos, radius = 24, type = "resource"}
        local best = near[1] and s.get_closest(e.pos, near)
        issue(e, "DRILL_NO_ORE", string.format("%s at %s has no minable resource in its %.1f-tile mining area%s", e.name, at(e.pos), 2 * r,
          best and string.format("; nearest is %s at %s", best.name, at(epos(best))) or "; none within 24 tiles"))
      end
      if e.proto.vector_to_place_result then
        local dp = add(e.pos, rot(V(e.proto.vector_to_place_result), e.d))
        e.drop = dp
        local dst, other = target_at(dp, TAKES)
        if not dst then
          issue(e, "DRILL_DROPS_ON_GROUND", string.format("%s at %s drops at %s%s: put a belt or chest there, or change intent.output",
            e.name, at(e.pos), at(dp), other and (", onto " .. other .. ", which takes no items") or ", which is empty"))
        end
      end
    end
  end

  -- 5. belts: where each belt-like entry hands items on, and what hands items to it
  -- a belt-like record: {src, kind, d, role, pos, w (world entity) or e (entry)}
  local function belt_at(p)
    local o = list_at(p)
    if o then return BELTS[o.type] and {src = "list", kind = o.type, d = o.d, role = o.role, pos = o.pos, e = o} or nil end
    for _, w in pairs(world_at(p)) do
      if BELTS[w.type] then
        return {src = "world", kind = w.type, d = w.direction, role = w.type == "underground-belt" and w.belt_to_ground_type or nil,
          pos = epos(w), w = w}
      end
    end
  end
  local function outputs(b)
    if b.kind == "transport-belt" or (b.kind == "underground-belt" and b.role == "output") then return {add(b.pos, CARD[b.d])} end
    if b.kind == "splitter" then
      return {add(add(b.pos, rot({-0.5, 0}, b.d)), CARD[b.d]), add(add(b.pos, rot({0.5, 0}, b.d)), CARD[b.d])}
    end
    return {}
  end
  local function feeds(b, p)
    if not b then return false end
    for _, o in pairs(outputs(b)) do if same_tile(o, p) then return true end end
    return false
  end
  local function carrying(b)
    if not b.w then return "" end
    local items = {}
    for k = 1, b.w.get_max_transport_line_index() do
      for _, c in pairs(b.w.get_transport_line(k).get_contents()) do items[c.name] = true end
    end
    local names = {} for n in pairs(items) do names[#names + 1] = n end
    table.sort(names)
    return #names > 0 and " (carrying " .. table.concat(names, ", ") .. ")" or ""
  end
  local function bdesc(b) return (b.src == "world" and "existing " or "") .. b.kind .. " at " .. at(b.pos) .. carrying(b) end

  for _, e in ipairs(E) do
    if valid(e) and BELTS[e.type] and CARD[e.d] then
      local me = {src = "list", kind = e.type, d = e.d, role = e.role, pos = e.pos, e = e}
      -- downstream
      for _, o in pairs(outputs(me)) do
        local T = belt_at(o)
        if T then
          local rel = (T.d - e.d) % 16
          local faces = rel == 8 or (T.kind == "underground-belt" and T.role == "output" and rel == 0) or (T.kind == "splitter" and rel ~= 0)
          if faces then
            issue(e, "BELT_FACES_BELT", string.format("%s at %s runs into %s head-on, which stops it: turn one of them", e.name, at(e.pos), bdesc(T)))
          elseif T.src == "world" then
            if rel == 0 then
              issue(e, "BELT_JOINS_FOREIGN", string.format("%s at %s flows straight into %s: your items join that line. Leave a gap, or accept BELT_JOINS_FOREIGN",
                e.name, at(e.pos), bdesc(T)))
            elseif T.kind == "transport-belt" then
              local back = belt_at(add(T.pos, scale(CARD[T.d], -1)))
              local far = belt_at(add(T.pos, CARD[e.d]))
              if (back and back.d == T.d and feeds(back, T.pos)) or (far and feeds(far, T.pos)) then
                local lane = ((e.d - T.d) % 16 == 4) and "left" or "right"
                issue(e, "BELT_SIDELOADS", string.format("%s at %s side-loads onto the %s lane of %s: your items mix into that line. End it a tile short, or accept BELT_SIDELOADS",
                  e.name, at(e.pos), lane, bdesc(T)))
              else
                issue(e, "BELT_JOINS_FOREIGN", string.format("%s at %s bends %s into a curve, since nothing feeds it from behind: that line then carries your items. Leave a gap, or accept BELT_JOINS_FOREIGN",
                  e.name, at(e.pos), bdesc(T)))
              end
            else
              issue(e, "BELT_SIDELOADS", string.format("%s at %s side-loads onto %s: your items mix into that line. End it a tile short, or accept BELT_SIDELOADS",
                e.name, at(e.pos), bdesc(T)))
            end
          end
        end
      end
      -- upstream: existing belts that hand items into this entry
      for d = 0, 12, 4 do
        local n = add(e.pos, CARD[d])
        if e.type ~= "splitter" and not list_at(n) then
          local W = belt_at(n)
          local mine = false
          for _, o in pairs(outputs(me)) do if W and same_tile(o, W.pos) then mine = true end end
          if W and W.src == "world" and feeds(W, e.pos) and not mine then
            local rel = (W.d - e.d) % 16
            local hood = e.type == "underground-belt" and e.role == "output" and rel == 0
            if rel == 8 or hood then
              issue(e, "BELT_FACES_BELT", string.format("%s runs head-on into %s at %s, which stops it: turn one of them", bdesc(W), e.name, at(e.pos)))
            else
              issue(e, "BELT_JOINS_FOREIGN", string.format("%s flows into %s at %s: its items enter your line. Leave a gap, or accept BELT_JOINS_FOREIGN",
                bdesc(W), e.name, at(e.pos)))
            end
          end
        end
      end
    end
  end

  -- 6. undergrounds: belts pair entry to exit along the flow, pipes pair along `toward`
  local function walk_pair(e, step, maxd, same_way)
    -- first underground of this name along step, from the list or the world; returns it, its distance, whether it pairs
    for k = 1, math.max(2 * maxd, 12) do
      local p = add(e.pos, scale(step, k))
      local o = list_at(p, function(x) return x.name == e.name end)
      local cand
      if o then cand = {d = o.d, role = o.role, pos = o.pos, what = "entry " .. o.i}
      else
        for _, w in pairs(world_at(p)) do
          if ename(w) == e.name or w.name == e.name then
            cand = {d = w.direction, role = w.type == "underground-belt" and w.belt_to_ground_type or nil, pos = epos(w),
              what = "existing " .. ename(w)}
          end
        end
      end
      if cand then
        local pairs_ok = same_way(cand)
        if pairs_ok ~= nil then return cand, k, pairs_ok end
      end
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
      local other = e.role == "input" and "exit" or "entry"
      if not cand or not ok then
        issue(e, "UNDERGROUND_UNPAIRED", string.format("%s %s at %s has no %s within %d tiles %s%s: add one, flowing %s",
          e.name, e.role == "input" and "entry" or "exit", at(e.pos), other, maxd, e.role == "input" and "ahead" or "behind",
          cand and string.format(" (%s at %s comes first and does not pair)", cand.what, at(cand.pos)) or "", DIR_NAME[e.d]))
      elseif k > maxd then
        local better = {}
        for n, pr in pairs(prototypes.get_entity_filtered{{filter = "type", type = "underground-belt"}}) do
          if (pr.max_underground_distance or 0) >= k then better[#better + 1] = n end
        end
        table.sort(better)
        issue(e, "UNDERGROUND_TOO_LONG", string.format("%s at %s pairs with %s at %s, %d tiles apart, but %s spans at most %d%s",
          e.name, at(e.pos), cand.what, at(cand.pos), k, e.name, maxd,
          #better > 0 and ": use " .. table.concat(better, " or ") .. ", or add a hop" or ": add a hop"))
      end
    elseif valid(e) and e.type == "pipe-to-ground" and CARD[e.d] then
      local uc = underground_conn(e.proto)
      if uc then
        local myway = (uc.direction + e.d) % 16
        local cand, k, ok = walk_pair(e, CARD[myway], uc.max, function(c)
          local theirs = (uc.direction + c.d) % 16
          if theirs == (myway + 8) % 16 then return true end
          if theirs == myway then return false end
        end)
        if not cand or not ok then
          issue(e, "UNDERGROUND_UNPAIRED", string.format("%s at %s has no partner within %d tiles toward %s%s: add one whose intent.toward points back",
            e.name, at(e.pos), uc.max, DIR_NAME[myway], cand and string.format(" (%s at %s comes first and faces the same way)", cand.what, at(cand.pos)) or ""))
        elseif k > uc.max then
          issue(e, "UNDERGROUND_TOO_LONG", string.format("%s at %s pairs with %s at %s, %d tiles apart, but it spans at most %d: add a hop",
            e.name, at(e.pos), cand.what, at(cand.pos), k, uc.max))
        else
          e.ug_partner = cand
        end
      end
    end
  end

  -- 7. fluids: union the list's fluidboxes through their connections, then collect the fluids each group touches
  local parent, fluids = {}, {}
  local function key(i, k) return i .. ":" .. k end
  local function find(x) while parent[x] ~= x do parent[x] = parent[parent[x]] x = parent[x] end return x end
  local function union(a, b) a, b = find(a), find(b) if a ~= b then parent[a] = b end end
  local function touch(x, fluid, where) fluids[x] = fluids[x] or {} fluids[x][fluid] = fluids[x][fluid] or where end
  local conns = {}
  for _, e in ipairs(E) do
    if valid(e) and e.proto.fluidbox_prototypes and #e.proto.fluidbox_prototypes > 0 then
      e.fluid = true
      for k, fb in pairs(e.proto.fluidbox_prototypes) do
        local x = key(e.i, fb.index or k)
        parent[x] = x
        if fb.filter then touch(x, fb.filter.name, e.name .. " (entry " .. e.i .. ")") end
      end
      conns[e.i] = pipe_conns(e.proto, e.d, e.pos)
    end
  end
  for _, e in ipairs(E) do
    for _, c in pairs(conns[e.i] or {}) do
      local x = key(e.i, c.fb)
      local o = list_at(c.target, function(y) return y.fluid end)
      if o then
        for _, oc in pairs(conns[o.i] or {}) do
          if same_tile(oc.from, c.target) and same_tile(oc.target, c.from) then union(x, key(o.i, oc.fb)) end
        end
      else
        for _, w in pairs(world_at(c.target)) do
          if w.name ~= "entity-ghost" and #(w.prototype.fluidbox_prototypes or {}) > 0 then
            for j = 1, w.fluids_count do
              local okc, wcs = pcall(w.get_fluid_box_pipe_connections, j)
              for _, wc in pairs(okc and wcs or {}) do
                if (wc.connection_type or "normal") == "normal" and same_tile(V(wc.target_position), c.from) then
                  local fl = world_fluid(w, j)
                  if fl then touch(x, fl, w.name .. " at " .. at(epos(w))) end
                end
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
          if w.name == e.name then local fl = world_fluid(w, 1) if fl then touch(key(e.i, 1), fl, w.name .. " at " .. at(epos(w))) end end
        end
      end
    end
  end
  local groups = {}
  for x in pairs(parent) do
    local r = find(x)
    groups[r] = groups[r] or {members = {}, fluids = {}}
    groups[r].members[#groups[r].members + 1] = x
    for fl, where in pairs(fluids[x] or {}) do groups[r].fluids[fl] = groups[r].fluids[fl] or where end
  end
  for _, g in pairs(groups) do
    local names = {}
    for fl, where in pairs(g.fluids) do names[#names + 1] = fl .. " (from " .. where .. ")" end
    if #names > 1 then
      table.sort(names)
      for _, x in pairs(g.members) do
        local i = tonumber(x:match("^(%d+):"))
        issue(E[i], "FLUID_MIX", string.format("%s at %s joins %s into one network: leave a one-tile gap, or route with pipe-to-ground",
          E[i].name, at(E[i].pos), table.concat(names, " and ")))
      end
    end
  end

  -- 8. poles: each must reach a pole already on a network, directly or through other list poles
  local poles, linked = {}, {}
  for _, e in ipairs(E) do if valid(e) and e.type == "electric-pole" then poles[#poles + 1] = e end end
  local function reach(p, q) return p.get_max_wire_distance and p.get_max_wire_distance() or p.max_wire_distance end
  for _, e in ipairs(poles) do
    local r = reach(e.proto)
    e.nearest = nil
    for _, w in pairs(s.find_entities_filtered{position = e.pos, radius = r + 0.01, type = "electric-pole", force = f}) do
      local dist = math.sqrt((w.position.x - e.pos[1]) ^ 2 + (w.position.y - e.pos[2]) ^ 2)
      if dist <= math.min(r, reach(w.prototype)) + 1e-6 then linked[e.i] = true end
    end
  end
  local grew = true
  while grew do
    grew = false
    for _, a in ipairs(poles) do
      if not linked[a.i] then
        for _, b in ipairs(poles) do
          if linked[b.i] then
            local dist = math.sqrt((a.pos[1] - b.pos[1]) ^ 2 + (a.pos[2] - b.pos[2]) ^ 2)
            if dist <= math.min(reach(a.proto), reach(b.proto)) + 1e-6 then linked[a.i], grew = true, true break end
          end
        end
      end
    end
  end
  for _, e in ipairs(poles) do
    if not linked[e.i] then
      local near = s.find_entities_filtered{position = e.pos, radius = 64, type = "electric-pole", force = f}
      local best = near[1] and s.get_closest(e.pos, near)
      local hint = "; no pole within 64 tiles"
      if best then
        local dist = math.sqrt((best.position.x - e.pos[1]) ^ 2 + (best.position.y - e.pos[2]) ^ 2)
        hint = string.format("; nearest is %s at %s, %.1f tiles away, and the wire reaches %.1f: add a pole between",
          best.name, at(epos(best)), dist, math.min(reach(e.proto), reach(best.prototype)))
      end
      issue(e, "POLE_ISLAND", string.format("%s at %s reaches no pole on a network, directly or through the list%s", e.name, at(e.pos), hint))
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
        if not can then
          issue(e, "BAD_RECIPE", string.format("%s cannot craft %s (category %s)", e.name, r, table.concat(cats, ", ")))
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
    local r = {i = e.i, ok = #issues == 0, direction = e.d, dir = e.d and DIR_NAME[e.d], issues = issues}
    local function r2(v) return {math.floor(v[1] * 100 + 0.5) / 100, math.floor(v[2] * 100 + 0.5) / 100} end
    if e.pick then r.pick = r2(e.pick) end
    if e.drop then r.drop = r2(e.drop) end
    if #acc > 0 then r.accepted = acc end
    if e.pos then r.position = {e.pos[1], e.pos[2]} end
    if e.role then r.type = e.role end
    if r.ok then nok = nok + 1 end
    out[#out + 1] = r
  end
  local parts = {}
  for c, n in pairs(counts) do parts[#parts + 1] = c .. " x" .. n end
  table.sort(parts)
  local items = {}
  for n, c in pairs(bom) do items[#items + 1] = c .. " " .. n end
  table.sort(items)
  local summary = string.format("%d of %d entries ok%s%s; needs %s", nok, #E,
    #parts > 0 and ": " .. table.concat(parts, ", ") or "", accepted > 0 and string.format(" (%d accepted)", accepted) or "",
    #items > 0 and table.concat(items, ", ") or "nothing")
  return {ok = nok == #E, entries = out, bom = bom, counts = counts, summary = summary}
end

local MAX_ENTRIES = 2000

-- the surface, force, list and accept of a tool call, or nil and an {error, hint} table
local function prepare(a)
  local function bad(msg, hint) return nil, {error = msg, hint = hint} end
  if type(a) ~= "table" then return bad("no arguments", "pass a table with a list of entries") end
  local s = a.surface == nil and game.surfaces.nauvis or game.surfaces[a.surface]
  if not s then
    local names = {}
    for _, sf in pairs(game.surfaces) do names[#names + 1] = sf.name end
    table.sort(names)
    return bad("no surface named " .. tostring(a.surface), "surfaces: " .. table.concat(names, ", "))
  end
  local f = a.force == nil and game.forces.player or game.forces[a.force]
  if not f then return bad("no force named " .. tostring(a.force), "the usual force is player") end
  local list = a.list
  if type(list) ~= "table" or #list == 0 or next(list, #list) ~= nil then
    return bad("list must be a non-empty array of entries", "each entry is {name, position = {x, y}, intent = {...}}")
  end
  if #list > MAX_ENTRIES then return bad(#list .. " entries is too many", "send at most " .. MAX_ENTRIES .. " per call") end
  for i, raw in ipairs(list) do
    if type(raw) ~= "table" then return bad("entry " .. i .. " is not a table", "each entry is {name, position = {x, y}, intent = {...}}") end
    if raw.intent ~= nil and type(raw.intent) ~= "table" then return bad("entry " .. i .. " has a non-table intent", "intent is a table such as {flow = {1, 0}}") end
    if raw.accept ~= nil and type(raw.accept) ~= "table" then return bad("entry " .. i .. " has a non-list accept", "accept is a list of codes") end
  end
  if a.accept ~= nil and type(a.accept) ~= "table" then return bad("accept must be a list of codes", "for example {\"BELT_JOINS_FOREIGN\"}") end
  return {surface = s, force = f, list = list, accept = a.accept}
end

-- the tiles a 1x1 entity like proto cannot take in area because a world entity shares its collision layers; returns taken(x, y)
local function occupied(s, proto, area)
  local mine = layers(proto)
  local set = {}
  for _, w in pairs(s.find_entities_filtered{area = area}) do
    local wp = eproto(w)
    if wp and w.type ~= "character" and not w.type:find("robot") and shares(mine, layers(wp)) then
      local b = box(wp, w.direction, epos(w))
      for x = math.floor(b[1] + EPS), math.ceil(b[3] - EPS) - 1 do
        for y = math.floor(b[2] + EPS), math.ceil(b[4] - EPS) - 1 do set[x * 65536 + y] = true end
      end
    end
  end
  return function(x, y) return set[x * 65536 + y] == true end
end

-- the failing entries of a check result as a flat list of {i, name, position, code, msg}
local function failures(list, res)
  local out = {}
  for i, r in ipairs(res.entries) do
    for _, x in ipairs(r.issues) do
      out[#out + 1] = {i = i, name = list[i].name, position = r.position, code = x.code, msg = x.msg}
    end
  end
  return out
end

return {check = check, prepare = prepare, occupied = occupied, failures = failures}
