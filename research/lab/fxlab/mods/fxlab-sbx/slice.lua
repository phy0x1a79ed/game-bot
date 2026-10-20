-- Slicing and reset (scope fxlab-slice); CONTRACT.md § Slicing lists the verbs.
-- A slice clones a rectangle of a source surface to the play surface `sbx-<name>` at the same coordinates, keeps a
-- frozen copy on `sbx-<name>-snap`, and closes every connection that crosses the cut with an infinity chest, loader
-- or pipe so the play surface runs alone. `slice_reset` wipes the play rectangle and clones the snapshot back.
-- storage.slice[name] = {area, big, source, snap, ports, unhandled, rails, rec (belts and fluids the freeze cannot
-- hold), fp (snapshot fingerprint), closer_ids, closer_ents, feeds, drains, evo, pollution, reset_at, inplace}.
local sbx = require("sbx")
local M = {remote = {}}

local D = defines.direction
local V = {[D.north] = {0, -1}, [D.east] = {1, 0}, [D.south] = {0, 1}, [D.west] = {-1, 0}}
local LEFT = {[D.north] = D.west, [D.east] = D.north, [D.south] = D.east, [D.west] = D.south}
local OPP = {[D.north] = D.south, [D.east] = D.west, [D.south] = D.north, [D.west] = D.east}
local BELT_OF = {["underground-belt"] = "transport-belt", ["fast-underground-belt"] = "fast-transport-belt",
  ["express-underground-belt"] = "express-transport-belt", ["turbo-underground-belt"] = "turbo-transport-belt",
  splitter = "transport-belt", ["fast-splitter"] = "fast-transport-belt", ["express-splitter"] = "express-transport-belt",
  ["turbo-splitter"] = "turbo-transport-belt"}
local BELTY = {"transport-belt", "underground-belt", "splitter", "loader-1x1", "loader"}
local BELT_T = {"transport-belt", "underground-belt", "splitter", "loader-1x1", "loader", "linked-belt", "lane-splitter"}
local IS_BELT = {}
for _, t in ipairs(BELT_T) do IS_BELT[t] = true end
local PIPEISH = {pipe = true, ["pipe-to-ground"] = true, ["storage-tank"] = true, pump = true, ["infinity-pipe"] = true}
local RAIL_T = {"straight-rail", "curved-rail-a", "curved-rail-b", "half-diagonal-rail", "elevated-straight-rail",
  "elevated-curved-rail-a", "elevated-curved-rail-b", "elevated-half-diagonal-rail", "rail-ramp"}
-- not state of the world: transient effects, and bodies that god mode parks on the play surface
local SKIP = {character = true, corpse = true, explosion = true, ["smoke-with-trigger"] = true, fish = true,
  ["flying-text"] = true, ["highlight-box"] = true, ["particle-source"] = true, stream = true, sticker = true,
  projectile = true, ["rail-remnants"] = true, ["deconstructible-tile-proxy"] = true}
local FP_SKIP = {fire = true}
for k in pairs(SKIP) do FP_SKIP[k] = true end
local BIG_PAD = 8
local SURFACE_SIZE = 2040

local function state()
  storage.slice = storage.slice or {}
  return storage.slice
end

M.on_init = function() storage.slice = {} end
M.on_configuration_changed = function() storage.slice = storage.slice or {} end

local function at(p, k, d) local v = V[d] return {x = p.x + k * v[1], y = p.y + k * v[2]} end

-- Profilers cannot be read as numbers in Lua: the last run's laps stay in a local until `slice_timing` prints them.
local laps = {}
local lap_name, lap_prof
local function lap(name)
  if lap_prof then lap_prof.stop() laps[#laps + 1] = {lap_name, lap_prof} end
  lap_name = name
  lap_prof = name and helpers.create_profiler() or nil
end
local function laps_begin() laps = {} lap_name, lap_prof = nil, nil end

M.remote.slice_timing = function()
  for _, l in ipairs(laps) do rcon.print({"", l[1], "\t", l[2]}) end
  return {laps = #laps}
end

local function rect(a)
  local lt, rb = a and (a[1] or a.left_top), a and (a[2] or a.right_bottom)
  if type(lt) ~= "table" or type(rb) ~= "table" then sbx.fail("bad_args", "area = {{x0, y0}, {x1, y1}}") end
  local x0, y0 = tonumber(lt[1] or lt.x), tonumber(lt[2] or lt.y)
  local x1, y1 = tonumber(rb[1] or rb.x), tonumber(rb[2] or rb.y)
  if not (x0 and y0 and x1 and y1) or x1 <= x0 or y1 <= y0 then sbx.fail("bad_args", "area needs x1 > x0 and y1 > y0") end
  x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.ceil(x1), math.ceil(y1)
  if math.max(math.abs(x0), math.abs(y0), math.abs(x1), math.abs(y1)) > SURFACE_SIZE - 64 then
    sbx.fail("bad_args", "area must lie within " .. (SURFACE_SIZE - 64) .. " tiles of the origin")
  end
  return {{x0, y0}, {x1, y1}}
end
local function pad(a, p) return {{a[1][1] - p, a[1][2] - p}, {a[2][1] + p, a[2][2] + p}} end
local function inrect(a, p) return p.x >= a[1][1] and p.x <= a[2][1] and p.y >= a[1][2] and p.y <= a[2][2] end

local function chunks_ready(s, a)
  local n = 0
  for cx = math.floor(a[1][1] / 32), math.floor(a[2][1] / 32) do
    for cy = math.floor(a[1][2] / 32), math.floor(a[2][2] / 32) do
      if not s.is_chunk_generated({cx, cy}) then
        s.request_to_generate_chunks({cx * 32 + 16, cy * 32 + 16}, 0)
        n = n + 1
      end
    end
  end
  if n > 0 then s.force_generate_chunk_requests() end
end

local function new_surface(name)
  local s = game.surfaces[name]
  if not s then
    s = game.create_surface(name, {width = 2 * SURFACE_SIZE, height = 2 * SURFACE_SIZE})
    s.generate_with_lab_tiles = true
    s.always_day = true
  end
  return s
end

-- Belt items and fluids that a freeze cannot hold ---------------------------------------------------------------

local function record(s, area)
  local rec = {belts = {}, fluids = {}, segs = {}, energy = {}, items = 0}
  for _, e in pairs(s.find_entities_filtered{area = area, type = BELT_T}) do
    local lines, any = {}, false
    for i = 1, e.get_max_transport_line_index() do
      local l = {}
      for _, d in pairs(e.get_transport_line(i).get_detailed_contents()) do
        l[#l + 1] = {d.position, d.stack.name, d.stack.quality.name, d.stack.count}
        rec.items = rec.items + d.stack.count
        any = true
      end
      lines[i] = l
    end
    if any then rec.belts[#rec.belts + 1] = {n = e.name, x = e.position.x, y = e.position.y, l = lines} end
  end
  for _, e in pairs(s.find_entities_filtered{area = area, type = "roboport"}) do
    rec.energy[#rec.energy + 1] = {n = e.name, x = e.position.x, y = e.position.y, e = e.energy}
  end
  local seen = {}
  for _, e in pairs(s.find_entities_filtered{area = area}) do
    if e.unit_number and e.fluids_count > 0 then
      local f, any = {}, false
      for i = 1, e.fluids_count do
        if e.has_fluid_segment(i) then
          local id = e.get_fluid_segment_id(i)
          if not seen[id] then
            seen[id] = true
            local sf, cap = e.get_fluid_segment_fluid(i), e.get_fluid_segment_capacity(i)
            if sf and cap > 0 then
              rec.segs[#rec.segs + 1] = {n = e.name, x = e.position.x, y = e.position.y, i = i, name = sf.name,
                                         level = sf.amount / cap, temp = sf.temperature}
            end
          end
        else
          local fl = e.get_fluid(i)
          f[i] = fl or false
          any = any or fl ~= nil
        end
      end
      if any then rec.fluids[#rec.fluids + 1] = {n = e.name, x = e.position.x, y = e.position.y, f = f} end
    end
  end
  return rec
end

local function restore_belts(s, rec)
  for _, b in ipairs(rec.belts) do
    local e = s.find_entity(b.n, {b.x, b.y})
    if e then
      for i = 1, e.get_max_transport_line_index() do
        local tl = e.get_transport_line(i)
        tl.clear()
        for _, it in ipairs(b.l[i] or {}) do tl.force_insert_at(it[1], {name = it[2], quality = it[3], count = it[4]}, it[4]) end
      end
    end
  end
end

local function restore_energy(s, rec)
  for _, r in ipairs(rec.energy) do
    local e = s.find_entity(r.n, {r.x, r.y})
    if e then e.energy = r.e end
  end
end

local function restore_fluids(s, rec)
  for _, r in ipairs(rec.fluids) do
    local e = s.find_entity(r.n, {r.x, r.y})
    if e then
      for i, f in pairs(r.f) do if f then e.set_fluid(i, f) end end
    end
  end
end

-- A segment's fluid is one number the engine shares out by capacity, so restore whole segments, after the closers
-- have joined them: the level then comes back exactly and the closers add nothing.
local function restore_segments(s, rec)
  for _, r in ipairs(rec.segs) do
    local e = s.find_entity(r.n, {r.x, r.y})
    if e then
      e.set_fluid_segment_fluid(r.i, {name = r.name, amount = r.level * e.get_fluid_segment_capacity(r.i), temperature = r.temp})
    end
  end
end

local function set_disabled(s, area, flag)
  for _, e in pairs(s.find_entities_filtered{area = area}) do
    if e.unit_number and e.type ~= "character" then e.disabled_by_script = flag end
  end
end

-- Fingerprint -----------------------------------------------------------------------------------------------------

local function r6(v) return string.format("%.6f", v) end
local function r3(v) return string.format("%.3f", v) end

local function inventories(e)
  local n = e.get_max_inventory_index()
  if not n or n == 0 then return nil end
  local out
  for i = 1, n do
    local inv = e.get_inventory(i)
    if inv then
      local c = inv.get_contents()
      if #c > 0 then
        local parts = {}
        for _, it in ipairs(c) do parts[#parts + 1] = it.name .. ":" .. (it.quality or "normal") .. "=" .. it.count end
        table.sort(parts)
        out = out or {}
        out[#out + 1] = i .. "{" .. table.concat(parts, ",") .. "}"
      end
    end
  end
  return out and table.concat(out, ";")
end

local function belt_lines(e)
  local out = {}
  for i = 1, e.get_max_transport_line_index() do
    local parts = {}
    for _, d in pairs(e.get_transport_line(i).get_detailed_contents()) do
      parts[#parts + 1] = r3(d.position) .. d.stack.name .. ":" .. d.stack.quality.name .. "x" .. d.stack.count
    end
    if #parts > 0 then out[#out + 1] = i .. "[" .. table.concat(parts, ",") .. "]" end
  end
  return #out > 0 and table.concat(out, ";") or nil
end

local function entity_line(e)
  local p = e.position
  local t = e.type
  local parts = {e.name, r3(p.x), r3(p.y), e.direction}
  if t == "resource" then parts[#parts + 1] = "amount=" .. e.amount return table.concat(parts, "|") end
  if t == "tree" then return table.concat(parts, "|") end
  if t == "entity-ghost" or t == "tile-ghost" then parts[#parts + 1] = "ghost=" .. e.ghost_name end
  if t == "item-entity" then parts[#parts + 1] = e.stack.name .. "x" .. e.stack.count end
  if not e.unit_number then return table.concat(parts, "|") end
  local inv = inventories(e)
  if inv then parts[#parts + 1] = "inv=" .. inv end
  if IS_BELT[t] then
    local b = belt_lines(e)
    if b then parts[#parts + 1] = "belt=" .. b end
  end
  if t == "assembling-machine" or t == "furnace" or t == "rocket-silo" then
    parts[#parts + 1] = "craft=" .. r6(e.crafting_progress)
    local r = e.get_recipe()
    if r then parts[#parts + 1] = "recipe=" .. r.name end
  end
  if t == "inserter" then
    local h = e.held_stack
    if h.valid_for_read then parts[#parts + 1] = "hand=" .. h.name .. ":" .. h.quality.name .. "x" .. h.count end
  end
  if e.fluids_count > 0 then
    local fl = {}
    for i = 1, e.fluids_count do
      local f = e.get_fluid(i)
      if f then fl[#fl + 1] = i .. ":" .. f.name .. "=" .. r6(f.amount) .. "@" .. r3(f.temperature or 0) end
    end
    if #fl > 0 then parts[#parts + 1] = "fluid=" .. table.concat(fl, ",") end
  end
  return table.concat(parts, "|")
end

-- Two 32-bit polynomial hashes over every byte of every line, in chunks so the loop stays in plain arithmetic.
local function digest(lines)
  local h1, h2 = 5381, 7
  local M1, M2 = 4294967296, 2147483647
  for _, s in ipairs(lines) do
    local n = #s
    local i = 1
    while i <= n do
      local j = math.min(i + 3999, n)
      local bytes = {s:byte(i, j)}
      for k = 1, #bytes do
        local b = bytes[k]
        h1 = (h1 * 33 + b) % M1
        h2 = (h2 * 131 + b) % M2
      end
      i = j + 1
    end
    h1 = (h1 * 33 + 10) % M1
    h2 = (h2 * 131 + 10) % M2
  end
  return string.format("%08x%08x", h1, h2)
end

-- Fingerprint of a rectangle: entities sorted by (name, x, y), closers left out.
local function fingerprint(s, area, skip)
  local list = {}
  for _, e in pairs(s.find_entities_filtered{area = area}) do
    local un = e.unit_number
    if not FP_SKIP[e.type] and not (un and skip and skip[un]) then
      local p = e.position
      list[#list + 1] = {e.name, p.x, p.y, entity_line(e)}
    end
  end
  table.sort(list, function(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    if a[2] ~= b[2] then return a[2] < b[2] end
    if a[3] ~= b[3] then return a[3] < b[3] end
    return a[4] < b[4]
  end)
  local lines = {}
  for i, rec in ipairs(list) do lines[i] = rec[4] end
  return {digest = digest(lines), entities = #lines}, lines
end

-- Ports -----------------------------------------------------------------------------------------------------------

local function thing_at(s, p, self)
  for _, e in pairs(s.find_entities_filtered{position = p}) do
    if e ~= self and e.type ~= "item-entity" and e.type ~= "resource" and e.type ~= "tree" then return e end
  end
end

-- what a machine would take from its input belt, by name
local function wants(e)
  local out = {}
  local function ingredients(r)
    if r then for _, i in pairs(r.ingredients) do if i.type == "item" then out[#out + 1] = i.name end end end
  end
  if e.type == "assembling-machine" then
    ingredients(e.get_recipe())
  elseif e.type == "furnace" then
    local r = e.get_recipe() or (e.previous_recipe and prototypes.recipe[e.previous_recipe.name])
    if r then ingredients(r) else out[#out + 1] = "iron-ore" end
  elseif e.type == "lab" then
    for _, i in pairs(e.prototype.lab_inputs) do out[#out + 1] = i end
  elseif e.type == "ammo-turret" then
    out[#out + 1] = "firearm-magazine"
  elseif e.type == "boiler" or e.type == "burner-inserter" then
    out[#out + 1] = "coal"
  end
  return out
end

local function lane_names(b, i, set)
  if i > b.get_max_transport_line_index() then return end
  for _, it in pairs(b.get_transport_line(i).get_contents()) do set[it.name] = true end
end

-- the items inserters take off this belt and the belts after it, for starved lanes
local function demand_along(s, start)
  local need, order, seen, queue = {}, {}, {}, {start}
  while #queue > 0 and #order < 4 do
    local b = table.remove(queue, 1)
    if b.valid and not seen[b.unit_number] then
      seen[b.unit_number] = true
      local x, y = b.position.x, b.position.y
      for _, ins in pairs(s.find_entities_filtered{type = "inserter", area = {{x - 3, y - 3}, {x + 3, y + 3}}}) do
        if thing_at(s, ins.pickup_position, ins) == b then
          local drop = thing_at(s, ins.drop_position, ins)
          if drop then for _, it in pairs(wants(drop)) do if not need[it] then need[it] = true order[#order + 1] = it end end end
        end
      end
      for _, n in pairs(b.belt_neighbours.outputs) do queue[#queue + 1] = n end
      if b.type == "underground-belt" and b.underground_belt_neighbour then queue[#queue + 1] = b.underground_belt_neighbour end
    end
  end
  return order
end

local function sorted(set) local t = {} for k in pairs(set) do t[#t + 1] = k end table.sort(t) return t end

local function belt_for(n)
  if n.type == "transport-belt" then return n.name end
  return BELT_OF[n.name] or "transport-belt"
end

-- Lanes of a cut belt: item names per lane, topped up with what the consumers downstream lack.
local function lanes_of(src, n, b)
  local lanes = {{}, {}}
  if n.type == "splitter" then
    for i = 1, n.get_max_transport_line_index() do lane_names(n, i, lanes[1]) end
    for k in pairs(lanes[1]) do lanes[2][k] = true end
  else
    for i = 1, 2 do
      lane_names(n, i, lanes[i])
      if b and b.type ~= "splitter" and n.direction == b.direction then lane_names(b, i, lanes[i]) end
    end
  end
  if not next(lanes[1]) or not next(lanes[2]) then
    local have = {}
    for _, l in pairs(lanes) do for k in pairs(l) do have[k] = true end end
    for _, it in ipairs(demand_along(src, b or n)) do
      if not have[it] then
        if not next(lanes[1]) then lanes[1][it] = true elseif not next(lanes[2]) then lanes[2][it] = true end
        have[it] = true
      end
    end
  end
  return {sorted(lanes[1]), sorted(lanes[2])}
end

local function pos2(p) return {x = p.x, y = p.y} end

-- Every connection that crosses the edge of `area`, as plain data a closer can be built from.
-- `inside` maps unit numbers of the entities the cut keeps. Returns ports, unhandled, rails and, parallel to
-- ports, the outside entities each port touches (an in-place cut removes them).
local function find_ports(src, area, inside)
  local ports, unhandled, outers = {}, {}, {}
  local function add(p, outer)
    ports[#ports + 1] = p
    outers[#ports] = outer or {}
  end
  local function refuse(e, reason)
    unhandled[#unhandled + 1] = {position = pos2(e.position), name = e.name, reason = reason}
  end
  local function inn(e) return e.unit_number and inside[e.unit_number] end

  for _, b in pairs(src.find_entities_filtered{area = area, type = BELTY}) do
    if inn(b) then
      local d = b.direction
      if b.type == "splitter" then
        local perp = V[LEFT[d]]
        local inputs, outputs = b.belt_neighbours.inputs, b.belt_neighbours.outputs
        for _, side in ipairs{0.5, -0.5} do
          local h = {x = b.position.x + side * perp[1], y = b.position.y + side * perp[2]}
          local tb, to = at(h, -1, d), at(h, 1, d)
          for _, n in pairs(inputs) do
            if not inn(n) and thing_at(src, tb, nil) == n then
              if n.direction ~= d then refuse(b, "splitter fed from the side")
              else
                add({how = "split-in", kind = "splitter", role = "feed", x = b.position.x, y = b.position.y, name = b.name,
                     tee = {x = tb.x, y = tb.y, dir = d, belt = belt_for(n)}, lanes = lanes_of(src, n, nil)}, {n})
              end
            end
          end
          for _, n in pairs(outputs) do
            if not inn(n) and thing_at(src, to, nil) == n then
              add({how = "split-out", kind = "splitter", role = "drain", x = b.position.x, y = b.position.y, name = b.name,
                   load = {x = to.x, y = to.y, dir = d}}, {n})
            end
          end
        end
      else
        for _, n in pairs(b.belt_neighbours.inputs) do
          if not inn(n) then
            local nd = n.direction
            local t = at(b.position, -1, nd)
            add({how = "belt-in", kind = "belt", role = "feed", x = b.position.x, y = b.position.y, name = b.name,
                 tee = {x = t.x, y = t.y, dir = nd, belt = belt_for(n)}, lanes = lanes_of(src, n, b),
                 cut = {name = b.name, x = b.position.x, y = b.position.y}}, {n})
          end
        end
        for _, n in pairs(b.belt_neighbours.outputs) do
          if not inn(n) then
            local o = at(b.position, 1, d)
            add({how = "belt-out", kind = "belt", role = "drain", x = b.position.x, y = b.position.y, name = b.name,
                 load = {x = o.x, y = o.y, dir = d}, cut = {name = b.name, x = b.position.x, y = b.position.y}}, {n})
          end
        end
        if b.type == "underground-belt" then
          local u = b.underground_belt_neighbour
          if u and not inn(u) then
            local ud = u.direction
            if b.belt_to_ground_type == "input" then
              local o = at(u.position, 1, ud)
              add({how = "under-out", kind = "belt", role = "drain", x = b.position.x, y = b.position.y, name = b.name,
                   pair = {name = u.name, x = u.position.x, y = u.position.y, dir = ud, type = "output"},
                   load = {x = o.x, y = o.y, dir = ud}}, {u, thing_at(src, o, u)})
            else
              local t = at(u.position, -1, ud)
              add({how = "under-in", kind = "belt", role = "feed", x = b.position.x, y = b.position.y, name = b.name,
                   pair = {name = u.name, x = u.position.x, y = u.position.y, dir = ud, type = "input"},
                   tee = {x = t.x, y = t.y, dir = ud, belt = BELT_OF[u.name] or "transport-belt"},
                   lanes = lanes_of(src, u, b), cut = {name = b.name, x = b.position.x, y = b.position.y}},
                  {u, thing_at(src, t, u)})
            end
          end
        end
      end
    end
  end

  for _, ins in pairs(src.find_entities_filtered{area = area, type = "inserter"}) do
    if inn(ins) then
      local pick = thing_at(src, ins.pickup_position, ins)
      if pick and pick.unit_number and not inn(pick) then
        local items = {}
        local inv = pick.get_output_inventory and pick.get_output_inventory()
        if IS_BELT[pick.type] then
          for i = 1, pick.get_max_transport_line_index() do lane_names(pick, i, items) end
        elseif inv then
          for _, it in pairs(inv.get_contents()) do items[it.name] = true end
        end
        if ins.held_stack.valid_for_read then items[ins.held_stack.name] = true end
        local drop = thing_at(src, ins.drop_position, ins)
        if not next(items) and drop then for _, it in pairs(wants(drop)) do items[it] = true end end
        local list = sorted(items)
        add({how = "inserter-in", kind = "inserter", role = "feed", x = ins.position.x, y = ins.position.y, name = ins.name,
             chest = pos2(ins.pickup_position), items = list, starved = #list == 0 or nil}, {pick})
      end
      local drop = thing_at(src, ins.drop_position, ins)
      if drop and drop.unit_number and not inn(drop) and drop.type ~= "character" then
        add({how = "inserter-out", kind = "inserter", role = "drain", x = ins.position.x, y = ins.position.y, name = ins.name,
             chest = pos2(ins.drop_position)}, {drop})
      end
    end
  end

  local seen_pipe = {}
  for _, e in pairs(src.find_entities_filtered{area = area}) do
    if inn(e) and e.fluids_count > 0 then
      for i = 1, e.fluids_count do
        for _, pc in pairs(e.get_fluid_box_pipe_connections(i) or {}) do
          local n = pc.target
          if n and not inn(n) then
            local f = e.get_fluid(i)
            local fluid, temp = f and f.name, f and f.temperature
            if not fluid and pc.target_fluidbox_index then
              local g = n.get_fluid(pc.target_fluidbox_index)
              fluid, temp = g and g.name, g and g.temperature
            end
            local kind = e.type == "storage-tank" and "tank" or "pipe"
            local role = pc.flow_direction == "output" and "drain" or "feed"
            local rec = {kind = kind, role = role, x = e.position.x, y = e.position.y, name = e.name, fluid = fluid,
                         temp = temp, starved = fluid == nil or nil}
            if pc.connection_type == "normal" then
              local tp = pc.target_position
              local key = tp.x .. "," .. tp.y
              if not seen_pipe[key] then
                seen_pipe[key] = true
                rec.how = "fluid"
                rec.pipe = {x = tp.x, y = tp.y}
                add(rec, {n})
              end
            elseif pc.connection_type == "underground" and n.type == "pipe-to-ground" then
              local behind
              for _, pc2 in pairs(n.get_fluid_box_pipe_connections(1) or {}) do
                if pc2.connection_type == "normal" then behind = pc2 end
              end
              if behind then
                local key = n.position.x .. "," .. n.position.y
                if not seen_pipe[key] then
                  seen_pipe[key] = true
                  rec.how = "fluid-under"
                  rec.pair = {name = n.name, x = n.position.x, y = n.position.y, dir = n.direction}
                  rec.pipe = {x = behind.target_position.x, y = behind.target_position.y}
                  add(rec, {n, behind.target})
                end
              else
                refuse(e, "underground pipe partner has no open end")
              end
            else
              refuse(e, "fluid connection of type " .. tostring(pc.connection_type))
            end
          end
        end
      end
    end
  end

  for _, e in pairs(src.find_entities_filtered{area = area, type = {"heat-pipe", "reactor"}}) do
    if inn(e) then
      for _, n in pairs(e.heat_neighbours) do
        if not inn(n) then refuse(e, "heat connection to " .. n.name) end
      end
    end
  end

  local rails, rail_count = {}, 0
  local ok, list = pcall(src.find_entities_filtered, {area = area, type = RAIL_T})
  if ok then
    local edge = 4
    for _, r in pairs(list) do
      rail_count = rail_count + 1
      local p = r.position
      if p.x - area[1][1] < edge or area[2][1] - p.x < edge or p.y - area[1][2] < edge or area[2][2] - p.y < edge then
        rails[#rails + 1] = {name = r.name, position = pos2(p), direction = r.direction}
      end
    end
  end
  return ports, unhandled, rails, rail_count, outers
end

-- Closers --------------------------------------------------------------------------------------------------------

local function ctx_new(name, s, force)
  return {name = name, s = s, force = force, made = {}, feeds = {}, drains = {}}
end

local function make(ctx, t)
  t.force = ctx.force
  if not ctx.s.can_place_entity{name = t.name, position = t.position, direction = t.direction, force = ctx.force} then return nil end
  local e = ctx.s.create_entity(t)
  if e then ctx.cur[#ctx.cur + 1] = e end
  return e
end

local function chest_source(ctx, p, items)
  local c = make(ctx, {name = "infinity-chest", position = p})
  if not c then return nil end
  local f = {}
  for i, it in ipairs(items) do f[i] = {name = it, count = 100, mode = "exactly", index = i} end
  c.infinity_container_filters = f
  return c
end

local function chest_void(ctx, p)
  local c = make(ctx, {name = "infinity-chest", position = p})
  if c then c.remove_unfiltered_items = true end
  return c
end

-- a belt that two side-loading loaders on infinity chests feed, one per lane
local function tee(ctx, t, lanes)
  local pos = {x = t.x, y = t.y}
  if not make(ctx, {name = t.belt, position = pos, direction = t.dir}) then return false end
  for lane, d in ipairs{LEFT[t.dir], OPP[LEFT[t.dir]]} do
    local items = lanes[lane]
    if #items > 0 then
      local ld = make(ctx, {name = "loader-1x1", position = at(pos, 1, d), direction = OPP[d], type = "output"})
      if not (ld and chest_source(ctx, at(pos, 2, d), items)) then return false end
    end
  end
  return true
end

local function drain_to_void(ctx, load)
  local o = {x = load.x, y = load.y}
  return make(ctx, {name = "loader-1x1", position = o, direction = load.dir, type = "input"}) ~= nil
    and chest_void(ctx, at(o, 1, load.dir)) ~= nil
end

local function close_port(ctx, p)
  local how = p.how
  if how == "belt-in" or how == "under-in" or how == "split-in" then
    if how == "under-in" and not make(ctx, {name = p.pair.name, position = {p.pair.x, p.pair.y}, direction = p.pair.dir, type = "input"}) then
      return false, "no room to rebuild the underground entrance"
    end
    if not next(p.lanes[1]) and not next(p.lanes[2]) then return true end
    if tee(ctx, p.tee, p.lanes) then return true end
    if how == "split-in" then return false, "no room for the feed beside a splitter input" end
    return "feed", "no room for a feed tee"
  elseif how == "belt-out" or how == "split-out" then
    if drain_to_void(ctx, p.load) then return true end
    if how == "split-out" then return false, "no room for the drain beside a splitter output" end
    return "drain", "no room for a drain loader"
  elseif how == "under-out" then
    if not make(ctx, {name = p.pair.name, position = {p.pair.x, p.pair.y}, direction = p.pair.dir, type = "output"}) then
      return false, "no room to rebuild the underground exit"
    end
    if drain_to_void(ctx, p.load) then return true end
    return false, "no room for a drain loader"
  elseif how == "inserter-in" then
    if p.starved then return true end
    if chest_source(ctx, p.chest, p.items) then return true end
    return false, "no room for the pickup chest"
  elseif how == "inserter-out" then
    if chest_void(ctx, p.chest) then return true end
    return false, "no room for the drop chest"
  elseif how == "fluid" or how == "fluid-under" then
    if p.starved then return true end
    local pair
    if how == "fluid-under" then
      pair = make(ctx, {name = p.pair.name, position = {p.pair.x, p.pair.y}, direction = p.pair.dir})
      if not pair then
        return false, string.format("no room to rebuild the underground pipe at (%.1f,%.1f)", p.pair.x, p.pair.y)
      end
    end
    local ip = make(ctx, {name = "infinity-pipe", position = {p.pipe.x, p.pipe.y}})
    if not ip then return false, string.format("no room for the infinity pipe at (%.1f,%.1f)", p.pipe.x, p.pipe.y) end
    ip.set_infinity_pipe_filter{name = p.fluid, percentage = 0.5, mode = "exactly", temperature = p.temp}
    return true
  end
  return false, "unknown port"
end

-- Close every port on surface `s`. Fills `S.closer_ids/closer_ents/feeds/drains`, ledgers each entity and returns the
-- ports that did close (each with its `closer` unit number) plus the ones that did not.
local function close_all(name, S, s, force, ports)
  local ctx = ctx_new(name, s, force)
  local done, refused = {}, {}
  S.closer_ids, S.closer_ents, S.feeds, S.drains = {}, {}, {}, {}
  -- pipes first: their tile is fixed, while a belt tee can fall back to a scripted feed
  local order = {}
  for i, p in ipairs(ports) do order[i] = {i, (p.kind == "belt" or p.kind == "splitter") and 3 or p.kind == "inserter" and 2 or 1} end
  table.sort(order, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
  for _, o in ipairs(order) do
    local p = ports[o[1]]
    ctx.cur = {}
    local ok, why = close_port(ctx, p)
    local out = {}
    for k, v in pairs(p) do out[k] = v end
    out.closer = nil
    if ok == "feed" or ok == "drain" then
      for _, e in ipairs(ctx.cur) do e.destroy() end
      ctx.cur = {}
      local cut = s.find_entity(p.cut.name, {p.cut.x, p.cut.y})
      if cut then
        if ok == "feed" then S.feeds[#S.feeds + 1] = {e = cut, lanes = p.lanes} else S.drains[#S.drains + 1] = cut end
        out.scripted = true
        ok = true
      else
        ok = false
        why = "the cut belt is gone"
      end
    elseif ok == false then
      for _, e in ipairs(ctx.cur) do e.destroy() end
      ctx.cur = {}
    end
    if ok then
      if ctx.cur[1] then out.closer = ctx.cur[1].unit_number end
      for _, e in ipairs(ctx.cur) do
        S.closer_ids[e.unit_number] = true
        S.closer_ents[#S.closer_ents + 1] = e
        sbx.ledger_add(name, {kind = "entity", entity = e})
      end
      done[#done + 1] = out
    else
      refused[#refused + 1] = {position = {x = p.x, y = p.y}, name = p.name, reason = why or "could not close"}
    end
  end
  return done, refused
end

local function strip(ports)
  local out = {}
  for i, p in ipairs(ports) do
    local c = {}
    for k, v in pairs(p) do if k ~= "cut" and k ~= "lanes_all" then c[k] = v end end
    c.position = {x = p.x, y = p.y}
    out[i] = c
  end
  return out
end

-- One electric-energy-interface on a global electric network powers the whole play surface.
local function power(name, S, s, force, area)
  s.create_global_electric_network()
  local spot = s.find_non_colliding_position("electric-energy-interface", {area[1][1] - 12, area[1][2] - 12}, 64, 1)
    or {area[1][1] - 12, area[1][2] - 12}
  local eei = s.create_entity{name = "electric-energy-interface", position = spot, force = force}
  if not eei then return nil end
  eei.power_production = 1e10
  eei.electric_buffer_size = 1e11
  eei.energy = 1e11
  S.closer_ids[eei.unit_number] = true
  S.closer_ents[#S.closer_ents + 1] = eei
  sbx.ledger_add(name, {kind = "entity", entity = eei})
  return {kind = "power", role = "feed", position = pos2(spot), closer = eei.unit_number}
end

local function prune_ledger(name)
  local list = sbx.ledger(name)
  local keep = 0
  for i = 1, #list do
    local en = list[i]
    if en.kind ~= "entity" or (en.entity and en.entity.valid) then
      keep = keep + 1
      list[keep] = en
    end
  end
  for i = #list, keep + 1, -1 do list[i] = nil end
end

local function destroy_closers(S)
  for _, e in ipairs(S.closer_ents or {}) do if e.valid then e.destroy() end end
  S.closer_ents, S.closer_ids, S.feeds, S.drains = {}, {}, {}, {}
end

-- Feeds and drains by script, for cut belts where no tee fits. The dispatcher calls this on its 6-tick hook.
M.nth = {[6] = function()
  for name, S in pairs(state()) do
    if (S.feeds and #S.feeds > 0) or (S.drains and #S.drains > 0) then
      local box = storage.sbx.boxes[name]
      if box and box.mode ~= "god" then
        S.feeds, S.drains = {}, {}
      else
        for _, f in ipairs(S.feeds) do
          if f.e.valid then
            for i, items in pairs(f.lanes) do
              if #items > 0 then
                local l = f.e.get_transport_line(i)
                local k = 0
                while k < 8 and l.can_insert_at_back() do
                  f.n = (f.n or 0) + 1
                  l.insert_at_back({name = items[f.n % #items + 1]})
                  k = k + 1
                end
              end
            end
          end
        end
        for _, e in ipairs(S.drains) do
          if e.valid then for i = 1, e.get_max_transport_line_index() do e.get_transport_line(i).clear() end end
        end
      end
    end
  end
end}

-- Snapshot and reset ----------------------------------------------------------------------------------------------

local function auto_trains(s)
  for _, t in pairs(game.train_manager.get_trains{surface = s}) do
    if t.manual_mode then t.manual_mode = false end
  end
end

local function record_pollution(src, area)
  local out = {}
  for cx = math.floor(area[1][1] / 32), math.floor(area[2][1] / 32) do
    for cy = math.floor(area[1][2] / 32), math.floor(area[2][2] / 32) do
      local p = {x = cx * 32 + 16, y = cy * 32 + 16}
      local amount = src.get_pollution(p)
      if amount > 0 then out[#out + 1] = {p.x, p.y, amount} end
    end
  end
  return out
end

local function apply_pollution(s, list)
  s.clear_pollution()
  for _, c in ipairs(list) do s.set_pollution({x = c[1], y = c[2]}, c[3]) end
end

local function key_of(e) return e.name .. "@" .. e.position.x .. "," .. e.position.y end

-- Entities clone_area leaves behind: clone them by hand, report what still does not arrive.
local function clone_missed(src, dst, area, big)
  local have = {}
  for _, e in pairs(dst.find_entities_filtered{area = big}) do have[key_of(e)] = true end
  local lost, names = {}, {}
  for _, e in pairs(src.find_entities_filtered{area = area}) do
    if not SKIP[e.type] and not have[key_of(e)] then
      lost[#lost + 1] = e
      names[e.name] = (names[e.name] or 0) + 1
    end
  end
  if #lost > 0 then
    src.clone_entities{entities = lost, destination_surface = dst, destination_offset = {0, 0}}
    have = {}
    for _, e in pairs(dst.find_entities_filtered{area = big}) do have[key_of(e)] = true end
    local still = {}
    for _, e in ipairs(lost) do
      if e.valid and not have[key_of(e)] then still[e.name] = (still[e.name] or 0) + 1 end
    end
    return names, still
  end
  return names, {}
end

local function surface_pair(box, name)
  return sbx.surface(box), game.surfaces[box.surface .. "-snap"]
end

-- Clone the snapshot onto the play surface and bring the play surface up. Used by build and reset.
local function bring_up(name, box, S, trains_auto)
  local play, snap = surface_pair(box, name)
  lap("wipe")
  destroy_closers(S)
  lap("clone")
  snap.clone_area{source_area = S.big, destination_area = S.big, destination_surface = play,
    clear_destination_entities = true, clear_destination_decoratives = true, clone_tiles = false,
    expand_map = false, create_build_effect_smoke = false}
  if S.missed and next(S.missed) then
    local names = {}
    for n in pairs(S.missed) do names[#names + 1] = n end
    local have = {}
    for _, e in pairs(play.find_entities_filtered{area = S.big, name = names}) do have[key_of(e)] = true end
    local lost = {}
    for _, e in pairs(snap.find_entities_filtered{area = S.big, name = names}) do
      if not have[key_of(e)] then lost[#lost + 1] = e end
    end
    if #lost > 0 then snap.clone_entities{entities = lost, destination_surface = play, destination_offset = {0, 0}} end
  end
  lap("enable")
  set_disabled(play, S.big, false)
  lap("restore")
  restore_fluids(play, S.rec)
  restore_energy(play, S.rec)
  if trains_auto ~= false then auto_trains(play) end
  game.forces.enemy.set_evolution_factor(S.evo, play)
  apply_pollution(play, S.pollution)
  lap("close")
  prune_ledger(name)
  local ports = S.ports_data
  S.ports, S.unhandled = {}, {}
  for _, u in ipairs(S.unhandled_find) do S.unhandled[#S.unhandled + 1] = u end
  if box.mode == "god" then
    local done, refused = close_all(name, S, play, sbx.force(box), ports)
    S.ports = strip(done)
    for _, u in ipairs(refused) do S.unhandled[#S.unhandled + 1] = u end
    lap("power")
    local pw = power(name, S, play, sbx.force(box), S.area)
    if pw then S.ports[#S.ports + 1] = pw end
  end
  lap("belts")
  restore_segments(play, S.rec)
  restore_belts(play, S.rec)
  lap(nil)
end

local function summary(S)
  return {area = S.area, entities = S.entities, ports = S.ports, unhandled = S.unhandled, rails = S.rails,
          rail_count = S.rail_count, missed = S.missed_report, ms = {}}
end

M.remote.slice_build = function(a)
  local area = rect(a.area)
  local source = a.source or "nauvis"
  local src = game.surfaces[source]
  if not src then sbx.fail("bad_args", "no surface " .. tostring(source)) end
  local name = a.name
  laps_begin()
  lap("gen")
  local box = sbx.new{name = name, research = a.research}
  local ok, err = pcall(function()
    local state_s = state()
    local big = pad(area, BIG_PAD)
    local play = sbx.surface(box)
    local snap = new_surface(box.surface .. "-snap")
    for _, f in pairs(game.forces) do f.set_surface_hidden(snap, true) end
    chunks_ready(play, pad(area, 64))
    chunks_ready(snap, pad(area, 16))
    lap("clone")
    src.clone_area{source_area = area, destination_area = area, destination_surface = snap,
      clear_destination_entities = true, expand_map = false, create_build_effect_smoke = false}
    lap("audit")
    local missed, still = clone_missed(src, snap, area, big)
    local inside = {}
    for _, e in pairs(src.find_entities_filtered{area = area}) do
      if e.unit_number then inside[e.unit_number] = true end
    end
    lap("ports")
    local ports, unhandled, rails, rail_count = find_ports(src, area, inside)
    lap("record")
    local rec = record(snap, big)
    lap("freeze")
    -- changing a force empties the fluid boxes and drops a ghost that waits on a robot, so the record comes first
    local ghosts = {}
    for _, g in pairs(snap.find_entities_filtered{area = big, type = "entity-ghost"}) do
      ghosts[#ghosts + 1] = {g.ghost_name, g.position.x, g.position.y, g.direction}
    end
    local force = sbx.force(box)
    for _, e in pairs(snap.find_entities_filtered{area = big, force = "player"}) do e.force = force end
    for _, g in ipairs(ghosts) do
      if #snap.find_entities_filtered{position = {g[2], g[3]}, type = "entity-ghost", ghost_name = g[1]} == 0 then
        local ok = pcall(snap.create_entity, {name = "entity-ghost", ghost_name = g[1], position = {g[2], g[3]},
                                                direction = g[4], force = force})
        if not ok then still["entity-ghost"] = (still["entity-ghost"] or 0) + 1 end
      end
    end
    set_disabled(snap, big, true)
    -- a roboport ignores the freeze: left charged, it keeps dispatching robots on the snapshot
    for _, e in pairs(snap.find_entities_filtered{area = big, type = "roboport"}) do e.energy = 0 end
    for _, e in pairs(snap.find_entities_filtered{area = big, type = BELT_T}) do
      for i = 1, e.get_max_transport_line_index() do e.get_transport_line(i).clear() end
    end
    for _, e in pairs(snap.find_entities_filtered{area = big}) do
      if e.unit_number and e.fluids_count > 0 then e.clear_fluid_inside() end
    end
    local S = {area = area, big = big, source = source, rec = rec, ports_data = ports,
               unhandled_find = unhandled, rails = rails, rail_count = rail_count,
               evo = game.forces.enemy.get_evolution_factor(src), pollution = record_pollution(src, big),
               missed = missed, missed_report = {cloned = missed, lost = still}, closer_ids = {}, closer_ents = {}}
    state_s[name] = S
    bring_up(name, box, S, true)
    lap("fingerprint")
    -- taken on the play surface, closers excluded: a reset repeats the same steps and so reproduces it exactly
    local fp, lines = fingerprint(sbx.surface(box), area, S.closer_ids)
    S.fp, S.fp_lines, S.entities = fp, lines, fp.entities
    lap(nil)
  end)
  if not ok then
    lap(nil)
    pcall(sbx.drop, name)
    storage.slice[name] = nil
    if type(err) == "table" then error(err, 0) end
    error(err, 0)
  end
  return summary(state()[name])
end

M.remote.slice_reset = function(a)
  local box = sbx.get(a.name)
  local S = state()[a.name]
  if not S or S.inplace then sbx.fail("not_found", "no slice " .. tostring(a.name)) end
  laps_begin()
  bring_up(a.name, box, S, a.trains_auto)
  S.last_reset = game.tick
  return {entities = S.entities, ports = #S.ports, unhandled = #S.unhandled, ms = {}}
end

M.remote.slice_reset_at = function(a)
  local S = state()[a.name]
  if not S or S.inplace then sbx.fail("not_found", "no slice " .. tostring(a.name)) end
  if type(a.tick) ~= "number" or a.tick < game.tick then sbx.fail("bad_args", "tick must be a number at or after game.tick") end
  S.reset_at = a.tick
  S.reset_auto = a.trains_auto
  return {tick = a.tick, now = game.tick}
end

M.on_tick = function(ev)
  for name, S in pairs(state()) do
    if S.reset_at and ev.tick >= S.reset_at then
      S.reset_at = nil
      local box = storage.sbx.boxes[name]
      if box then
        laps_begin()
        bring_up(name, box, S, S.reset_auto)
        S.last_reset = ev.tick
      end
    end
  end
end

-- In-place arm ----------------------------------------------------------------------------------------------------
-- The same cut on the source surface itself: what connects into the rectangle from outside moves to a stash surface,
-- the closers go where it stood, the copper wires that cross the edge come off, and `slice_drop` puts it all back.

local function ekey(e) return {n = e.name, x = e.position.x, y = e.position.y} end
local function efind(s, k) return s.find_entity(k.n, {k.x, k.y}) end

-- every wire of `e` as {a, aid, b, bid, origin}, once per pair
local function wires_of(e, out, seen)
  local conns = e.get_wire_connectors(false)
  if not conns then return end
  for _, c in pairs(conns) do
    for _, w in ipairs(c.connections) do
      local o = w.target.owner
      if o and o.valid and o.type ~= "entity-ghost" then
        local a, b = ekey(e), ekey(o)
        local ka = a.n .. "@" .. a.x .. "," .. a.y .. ":" .. c.wire_connector_id
        local kb = b.n .. "@" .. b.x .. "," .. b.y .. ":" .. w.target.wire_connector_id
        local key = ka < kb and (ka .. "|" .. kb) or (kb .. "|" .. ka)
        if not seen[key] then
          seen[key] = true
          out[#out + 1] = {a = a, aid = c.wire_connector_id, b = b, bid = w.target.wire_connector_id, origin = w.origin}
        end
      end
    end
  end
end

local function rewire(s, list)
  for _, w in ipairs(list) do
    local ea, eb = efind(s, w.a), efind(s, w.b)
    if ea and eb then
      local ca, cb = ea.get_wire_connector(w.aid, true), eb.get_wire_connector(w.bid, true)
      if ca and cb then ca.connect_to(cb, false, w.origin) end
    end
  end
end

local function supply_overlaps(pole, area)
  local d = pole.prototype.get_supply_area_distance()
  local p = pole.position
  return p.x + d > area[1][1] and p.x - d < area[2][1] and p.y + d > area[1][2] and p.y - d < area[2][2]
end

-- one energy interface on each electric network of the rectangle, placed inside a pole's supply area
local function power_inplace(name, S, s, force, area, inside)
  local made, done = {}, {}
  for _, pole in pairs(s.find_entities_filtered{area = area, type = "electric-pole"}) do
    local id = pole.electric_network_id
    if inside[pole.unit_number] and id and not done[id] then
      local d = pole.prototype.get_supply_area_distance()
      local p = s.find_non_colliding_position("electric-energy-interface", pole.position, d + 1, 0.5)
      local eei = p and s.create_entity{name = "electric-energy-interface", position = p, force = force}
      if eei then
        if eei.is_connected_to_electric_network() then
          eei.power_production = 1e10
          eei.electric_buffer_size = 1e11
          eei.energy = 1e11
          S.closer_ids[eei.unit_number] = true
          S.closer_ents[#S.closer_ents + 1] = eei
          sbx.ledger_add(name, {kind = "entity", entity = eei})
          made[#made + 1] = {kind = "power", role = "feed", position = pos2(p), closer = eei.unit_number}
          done[id] = true
        else
          eei.destroy()
        end
      end
    end
  end
  return made
end

M.remote.slice_inplace = function(a)
  local area = rect(a.area)
  local source = a.source or "nauvis"
  local src = game.surfaces[source]
  if not src then sbx.fail("bad_args", "no surface " .. tostring(source)) end
  local name = a.name
  laps_begin()
  lap("gen")
  local box = sbx.new{name = name, inplace = {surface = source, force = "player"}}
  local S = {area = area, big = pad(area, BIG_PAD), source = source, inplace = true, tick = game.tick,
             closer_ids = {}, closer_ents = {}, feeds = {}, drains = {}, ports = {}, unhandled = {}, stash = {}, wires = {}}
  state()[name] = S
  local ok, err = pcall(function()
    local inside = {}
    for _, e in pairs(src.find_entities_filtered{area = area}) do
      if e.unit_number then inside[e.unit_number] = true end
    end
    lap("ports")
    local ports, unhandled, rails, rail_count, outers = find_ports(src, area, inside)
    S.ports_data, S.unhandled_find, S.rails, S.rail_count = ports, unhandled, rails, rail_count

    local stash, seen = {}, {}
    local function take(e)
      if e and e.valid and e.unit_number and not inside[e.unit_number] and not seen[e.unit_number]
         and e.type ~= "character" then
        seen[e.unit_number] = true
        stash[#stash + 1] = e
      end
    end
    for _, list in pairs(outers) do for _, e in pairs(list) do take(e) end end
    for _, ins in pairs(src.find_entities_filtered{area = pad(area, 4), type = "inserter"}) do
      if not inside[ins.unit_number] and (inrect(area, ins.pickup_position) or inrect(area, ins.drop_position)) then take(ins) end
    end
    for _, pole in pairs(src.find_entities_filtered{area = pad(area, 12), type = "electric-pole"}) do
      if not inside[pole.unit_number] then
        local linked = false
        local c = pole.get_wire_connector(defines.wire_connector_id.pole_copper, false)
        if c then
          for _, w in ipairs(c.connections) do
            local o = w.target.owner
            if o and o.valid and o.unit_number and inside[o.unit_number] then linked = true end
          end
        end
        if linked or supply_overlaps(pole, area) then take(pole) end
      end
    end

    lap("wires")
    local seen_w = {}
    for _, e in ipairs(stash) do wires_of(e, S.wires, seen_w) end
    for _, pole in pairs(src.find_entities_filtered{area = area, type = "electric-pole"}) do
      local c = pole.get_wire_connector(defines.wire_connector_id.pole_copper, false)
      if c then
        for _, w in ipairs(c.connections) do
          local o = w.target.owner
          if o and o.valid and o.unit_number and not inside[o.unit_number] and not seen[o.unit_number] then
            local before = #S.wires
            wires_of(pole, S.wires, seen_w)
            c.disconnect_from(w.target, w.origin)
          end
        end
      end
    end

    lap("stash")
    S.pre = record(src, pad(area, 24))
    local stash_s = new_surface("fxlab-stash-" .. name)
    for _, f in pairs(game.forces) do f.set_surface_hidden(stash_s, true) end
    local rect_stash = pad(area, 24)
    for _, e in ipairs(stash) do
      local p = e.position
      chunks_ready(stash_s, {{p.x - 8, p.y - 8}, {p.x + 8, p.y + 8}})
    end
    if #stash > 0 then
      src.clone_entities{entities = stash, destination_surface = stash_s, destination_offset = {0, 0}}
    end
    S.stash_rec = record(stash_s, rect_stash)
    S.stash_area = rect_stash
    for _, e in ipairs(stash) do e.destroy() end
    S.stashed = #stash

    lap("close")
    local done, refused = close_all(name, S, src, game.forces.player, ports)
    S.ports = strip(done)
    S.unhandled = {}
    for _, u in ipairs(unhandled) do S.unhandled[#S.unhandled + 1] = u end
    for _, u in ipairs(refused) do S.unhandled[#S.unhandled + 1] = u end
    for _, pw in ipairs(power_inplace(name, S, src, game.forces.player, area, inside)) do S.ports[#S.ports + 1] = pw end
    S.entities = src.count_entities_filtered{area = area}
    lap(nil)
  end)
  if not ok then
    lap(nil)
    pcall(M.inplace_drop, name, S)
    pcall(sbx.drop, name)
    state()[name] = nil
    error(err, 0)
  end
  local out = summary(S)
  out.stashed = S.stashed
  return out
end

-- Undo an in-place cut: closers out, stash back, wires back.
function M.inplace_drop(name, S)
  local src = game.surfaces[S.source]
  destroy_closers(S)
  local stash_s = game.surfaces["fxlab-stash-" .. name]
  if stash_s then
    local list = stash_s.find_entities_filtered{}
    if #list > 0 then
      stash_s.clone_entities{entities = list, destination_surface = src, destination_offset = {0, 0}}
    end
  end
  rewire(src, S.wires or {})
  if S.stash_rec then
    restore_belts(src, S.stash_rec)
  end
  -- nothing has run since the cut: put every belt and fluid back exactly
  if S.pre and game.tick == S.tick then
    restore_fluids(src, S.pre)
    restore_segments(src, S.pre)
    restore_belts(src, S.pre)
  end
  if stash_s then game.delete_surface(stash_s) end
end

M.remote.slice_ports = function(a)
  local S = state()[a.name]
  if not S then sbx.fail("not_found", "no slice " .. tostring(a.name)) end
  return {ports = S.ports, unhandled = S.unhandled, rails = S.rails, rail_count = S.rail_count}
end

M.remote.slice_list = function()
  local out = {}
  for name, S in pairs(state()) do
    out[#out + 1] = {name = name, area = S.area, entities = S.entities, ports = #S.ports, unhandled = #S.unhandled,
                     inplace = S.inplace or false, last_reset = S.last_reset}
  end
  table.sort(out, function(x, y) return x.name < y.name end)
  return {slices = out}
end

M.remote.slice_area_of_base = function(a)
  local s = game.surfaces[a.surface or "nauvis"]
  if not s then sbx.fail("bad_args", "no surface " .. tostring(a.surface)) end
  local force = a.force or "player"
  if not game.forces[force] then sbx.fail("bad_args", "no force " .. force) end
  local p = a.pad or 32
  local x0, y0, x1, y1
  for _, e in pairs(s.find_entities_filtered{force = force}) do
    local b = e.bounding_box
    local lx, ly, rx, ry = b.left_top.x, b.left_top.y, b.right_bottom.x, b.right_bottom.y
    if not x0 then x0, y0, x1, y1 = lx, ly, rx, ry
    else
      if lx < x0 then x0 = lx end
      if ly < y0 then y0 = ly end
      if rx > x1 then x1 = rx end
      if ry > y1 then y1 = ry end
    end
  end
  if not x0 then sbx.fail("not_found", "force " .. force .. " owns nothing on " .. s.name) end
  return {area = {{math.floor(x0 - p), math.floor(y0 - p)}, {math.ceil(x1 + p), math.ceil(y1 + p)}}}
end

M.remote.slice_fingerprint = function(a)
  local detail = a.detail and true or false
  if not a.name then
    local s = game.surfaces[a.surface or "nauvis"]
    if not s then sbx.fail("bad_args", "no surface " .. tostring(a.surface)) end
    local fp, lines = fingerprint(s, rect(a.area), nil)
    return {digest = fp.digest, entities = fp.entities, records = detail and lines or nil}
  end
  local box = sbx.get(a.name)
  local S = state()[a.name]
  if not S then sbx.fail("not_found", "no slice " .. a.name) end
  local which = a.which or "play"
  if which == "snapshot" then
    if S.inplace then sbx.fail("bad_args", "an in-place slice has no snapshot") end
    return {digest = S.fp.digest, entities = S.fp.entities, records = detail and S.fp_lines or nil}
  end
  local s
  if which == "play" then s = sbx.surface(box)
  elseif which == "source" then s = game.surfaces[S.source]
  else sbx.fail("bad_args", "which = play | snapshot | source") end
  local fp, lines = fingerprint(s, S.area, which == "play" and S.closer_ids or nil)
  return {digest = fp.digest, entities = fp.entities, records = detail and lines or nil}
end

M.remote.slice_drop = function(a)
  local S = state()[a.name]
  if not S then sbx.fail("not_found", "no slice " .. tostring(a.name)) end
  if S.inplace then M.inplace_drop(a.name, S) end
  sbx.drop(a.name)
  state()[a.name] = nil
  return {}
end

return M
