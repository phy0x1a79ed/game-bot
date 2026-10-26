--- tool: core
--- kind: lib
--- effect: read
--- summary: helpers every tool shares: directions and vectors, rounding, surface and force checks, ghost unwrapping, belt sets, lanes and outputs
--- args: none
--- returns: {fail, r2, xy, at, sgn, vec, card, rot, dir_of, add, scale, same_tile, epos, DIR, CARD, sorted, world, name_of, type_of, proto_of, ename, static, BELT_TYPES, IGNORED, entities_at, belt_items, carried, belt_outputs}
local core = {}

core.DIR = {}
for k, v in pairs(defines.direction) do core.DIR[v] = k end
-- the four cardinal directions in 2.x's 16-way encoding, as unit vectors (y grows south)
core.CARD = {[0] = {0, -1}, [4] = {1, 0}, [8] = {0, 1}, [12] = {-1, 0}}

function core.fail(msg, hint) return {error = msg, hint = hint} end
function core.r2(v) return math.floor(v * 100 + 0.5) / 100 end
function core.xy(p) return {core.r2(p.x or p[1]), core.r2(p.y or p[2])} end
function core.at(p) return string.format("(%.1f, %.1f)", p.x or p[1], p.y or p[2]) end
function core.sgn(v) return v > 0.001 and 1 or (v < -0.001 and -1 or 0) end

--- {x, y} from {x =, y =} or {x, y}, or nil.
function core.vec(v)
  if type(v) ~= "table" then return nil end
  local x, y = v.x or v[1], v.y or v[2]
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  return {x, y}
end

--- A one-axis unit vector from {dx, dy}, or nil when the vector is diagonal or zero.
function core.card(v)
  v = core.vec(v)
  if not v then return nil end
  local x, y = core.sgn(v[1]), core.sgn(v[2])
  if (x ~= 0) == (y ~= 0) then return nil end
  return {x, y}
end

--- Rotate a vector given for a north-facing entity to cardinal direction d (clockwise, y down).
function core.rot(v, d)
  local x, y = v[1] or v.x, v[2] or v.y
  for _ = 1, math.floor(d / 4) % 4 do x, y = -y, x end
  return {x, y}
end

--- The direction (0, 4, 8, 12) at which the north-based vector nv points along the unit vector c; nv defaults to north.
function core.dir_of(c, nv)
  nv = nv or {0, -1}
  for d = 0, 12, 4 do
    local v = core.rot(nv, d)
    local m = math.abs(v[1]) > math.abs(v[2]) and {core.sgn(v[1]), 0} or {0, core.sgn(v[2])}
    if m[1] == c[1] and m[2] == c[2] then return d end
  end
end

function core.add(a, b) return {a[1] + b[1], a[2] + b[2]} end
function core.scale(v, k) return {v[1] * k, v[2] * k} end
function core.same_tile(a, b) return math.floor(a[1]) == math.floor(b[1]) and math.floor(a[2]) == math.floor(b[2]) end
function core.epos(e) return {e.position.x, e.position.y} end

function core.sorted(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

--- The surface and force named by a.surface and a.force (defaults nauvis and player), or nil and an error table.
function core.world(a)
  if a.surface ~= nil and type(a.surface) ~= "string" then return nil, core.fail("surface must be a name", "for example \"nauvis\"") end
  if a.force ~= nil and type(a.force) ~= "string" then return nil, core.fail("force must be a name", "for example \"player\"") end
  local s = game.surfaces[a.surface or "nauvis"]
  if not s then
    local names = {}
    for _, sf in pairs(game.surfaces) do names[#names + 1] = sf.name end
    table.sort(names)
    return nil, core.fail("no surface named '" .. tostring(a.surface) .. "'", "surfaces: " .. table.concat(names, ", "))
  end
  local f = game.forces[a.force or "player"]
  if not f then return nil, core.fail("no force named '" .. tostring(a.force) .. "'", "the usual force is player") end
  return s, f
end

-- a ghost stands for the entity it plans
function core.name_of(e) return e.type == "entity-ghost" and e.ghost_name or e.name end
function core.type_of(e) return e.type == "entity-ghost" and e.ghost_type or e.type end
function core.proto_of(e) return e.type == "entity-ghost" and e.ghost_prototype or e.prototype end
function core.ename(e) return e.type == "entity-ghost" and e.ghost_name .. " ghost" or e.name end

--- What a prototype says that never changes, read once per name per tick (each engine read builds a fresh table):
--- cb (collision box, facing north), layers, item (that places it), placeable, boxes (fluidboxes), conns (normal pipe
--- connections, relative per direction), ug (the underground connection of a pipe-to-ground).
local STATIC = {}
function core.static(proto)
  local c = STATIC[proto.name]
  if c then return c end
  local b = proto.collision_box
  c = {cb = {b.left_top.x, b.left_top.y, b.right_bottom.x, b.right_bottom.y},
    layers = proto.collision_mask and proto.collision_mask.layers or {}, boxes = {}, conns = {}}
  local items = proto.items_to_place_this
  c.item = items and items[1] and {name = items[1].name, count = items[1].count} or nil
  c.placeable = c.item ~= nil and proto.flags ~= nil and proto.flags["player-creation"] == true
  for k, fb in pairs(proto.fluidbox_prototypes or {}) do
    c.boxes[#c.boxes + 1] = {key = fb.index or k, filter = fb.filter and fb.filter.name}
    for _, pc in pairs(fb.pipe_connections or {}) do
      local kind = pc.connection_type or "normal"
      if kind == "underground" then
        c.ug = c.ug or {direction = pc.direction, max = pc.max_underground_distance}
      elseif kind == "normal" and pc.direction then
        local rel = {}
        for d = 0, 12, 4 do rel[d] = core.vec(pc.positions and pc.positions[d / 4 + 1] or core.rot(core.vec(pc.position) or {0, 0}, d)) end
        c.conns[#c.conns + 1] = {fb = fb.index or k, direction = pc.direction, rel = rel}
      end
    end
  end
  STATIC[proto.name] = c
  return c
end

core.BELT_TYPES = {["transport-belt"] = true, ["underground-belt"] = true, ["splitter"] = true,
  ["loader"] = true, ["loader-1x1"] = true, ["linked-belt"] = true, ["lane-splitter"] = true}

-- what stands on a tile without taking it: nothing builds on, picks from or drops into these
core.IGNORED = {resource = true, ["item-entity"] = true, corpse = true, ["character-corpse"] = true, character = true,
  ["construction-robot"] = true, ["logistic-robot"] = true, ["combat-robot"] = true, fish = true, unit = true,
  ["item-request-proxy"] = true, ["tile-ghost"] = true, ["highlight-box"] = true, explosion = true, smoke = true}

--- The entities whose collision box holds point p, leaving out the IGNORED types.
function core.entities_at(s, p)
  local out = {}
  for _, e in pairs(s.find_entities_filtered{position = p}) do
    if not core.IGNORED[e.type] then out[#out + 1] = e end
  end
  return out
end

local function merge(into, line)
  for _, it in pairs(line.get_contents()) do into[it.name] = (into[it.name] or 0) + it.count end
end

--- Items on a belt-like entity as left, right lane tables. Odd transport lines are the left lane.
--- An underground entrance also holds the items travelling under the ground, on its lines 3 and 4.
function core.belt_items(e)
  local left, right = {}, {}
  local n = e.get_max_transport_line_index()
  if e.type == "underground-belt" and e.belt_to_ground_type == "output" then n = math.min(n, 2) end
  for i = 1, n do merge(i % 2 == 1 and left or right, e.get_transport_line(i)) end
  return left, right
end

--- The sorted names of the items on a belt-like entity, both lanes.
function core.carried(e)
  local left, right = core.belt_items(e)
  for n, v in pairs(right) do left[n] = (left[n] or 0) + v end
  return core.sorted(left)
end

--- The points just past the tiles a belt-like piece hands items onto: kind is the entity type, d its direction,
--- pos its centre {x, y}, role an underground's input or output. Only a belt, an underground exit and a splitter hand on.
function core.belt_outputs(kind, d, pos, role)
  local c = core.CARD[d]
  if not c then return {} end
  if kind == "transport-belt" or (kind == "underground-belt" and role == "output") then
    return {{pos[1] + c[1], pos[2] + c[2]}}
  end
  if kind == "splitter" then
    local h = core.rot({0.5, 0}, d)
    return {{pos[1] - h[1] + c[1], pos[2] - h[2] + c[2]}, {pos[1] + h[1] + c[1], pos[2] + h[2] + c[2]}}
  end
  return {}
end

return core
