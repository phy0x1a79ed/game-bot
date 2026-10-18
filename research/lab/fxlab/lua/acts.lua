-- acts.lua: the safe-act surface. Expects ACT = {verb = ..., surface = ..., args = {...}}.
-- Prints JSON {ok = true, did = ...} or {ok = false, refused = reason}. Every act checks before it acts,
-- and none creates an item: entities appear only as ghosts that robots build from storage.
--   look {x0, y0, x1, y1, limit, count}   entities in an area, with recipe and status; count = true tallies names
--   resources {x0, y0, x1, y1}        ore patches in an area: tiles, amount, extent and drills on each
--   network {x, y}                    the robot network that builds at a point: robots, roboports, storage contents
--   rate {items}                      made and used per minute, over the last minute and the last ten
--   ghost {name, x, y, direction, recipe}   place one ghost
--   ghosts {list}                     place many: list of [name, x, y, direction, recipe], each checked like ghost
--   blueprint {bp, x, y, direction}   place a blueprint string as ghosts
--   remove {name, x, y}               order deconstruction of the one entity of that name on that tile
--   cancel {name, x, y}               cancel a deconstruction order the same way
--   recipe {x, y, recipe}             set an assembler's recipe; displaced items spill for robots to collect
--   research {tech}                   queue a technology
local A, s, f = ACT.args or {}, game.surfaces[ACT.surface or "nauvis"], game.forces.player
local status_name = {} for k, v in pairs(defines.entity_status) do status_name[v] = k end
local function out(t) rcon.print(helpers.table_to_json(t)) end
local function refuse(why) out{ok = false, refused = why} end
local function pos(e) return {x = e.position.x, y = e.position.y} end
local function dir(d) return d and defines.direction[d] or defines.direction.north end
local dir_name = {} for k, v in pairs(defines.direction) do dir_name[v] = k end
local function fmt(e) return string.format("%s at (%.1f, %.1f)", e.name == "entity-ghost" and e.ghost_name .. " ghost" or e.name, e.position.x, e.position.y) end

-- the network whose robots build at p: construction area, which reaches past the logistic area
local function builder(p) return s.find_logistic_networks_by_construction_area(p, f)[1] end

local function nearest_roboport(p)
  local r = s.get_closest(p, s.find_entities_filtered{type = "roboport", force = "player"})
  if not r then return "" end
  local x, y = p.x or p[1], p.y or p[2]
  return string.format("; nearest roboport is at (%.1f, %.1f), %d tiles away, and builds within %d tiles", r.position.x,
    r.position.y, math.floor(math.sqrt((r.position.x - x) ^ 2 + (r.position.y - y) ^ 2)), r.prototype.construction_radius)
end

local function covered(p, item)
  local net = builder(p)
  if not net then return "outside every roboport's construction area: robots will not build it" .. nearest_roboport(p) end
  if not item then return nil end
  local have = net.get_item_count(item)
  if have == 0 then return "robot network holds no " .. item end
end

local function on_tile(name)
  local p = {A.x, A.y}
  local hits = {}
  for _, e in pairs(s.find_entities_filtered{position = p, force = "player"}) do
    if e.name == name or (e.name == "entity-ghost" and e.ghost_name == name) then hits[#hits + 1] = e end
  end
  if #hits == 1 then return hits[1] end
  if #hits > 1 then return nil, string.format("%d entities named %s cover (%.1f, %.1f)", #hits, name, A.x, A.y) end
  local near = s.find_entities_filtered{name = name, position = p, radius = 8, force = "player", limit = 1}[1]
  return nil, string.format("no %s covers (%.1f, %.1f)%s", name, A.x, A.y, near and "; nearest is " .. fmt(near) or "")
end

-- the centre nearest (x, y) on proto's tile grid: odd sizes sit on half tiles, even sizes on tile corners
local function on_grid(proto, x, y)
  local b = proto.collision_box
  local ox = math.ceil(b.right_bottom.x - b.left_top.x) % 2 == 1 and 0.5 or 0
  local oy = math.ceil(b.right_bottom.y - b.left_top.y) % 2 == 1 and 0.5 or 0
  return math.floor(x - ox + 0.5) + ox, math.floor(y - oy + 0.5) + oy
end

-- can_place_entity also passes a rotate or replace over a same-sized entity, which a new ghost cannot do
local PASSABLE = {resource = true, ["item-entity"] = true, corpse = true}
local function fits(proto, spec)
  if not s.can_place_entity(spec) then return false end
  local b, x, y = proto.collision_box, spec.position[1], spec.position[2]
  for _, e in pairs(s.find_entities_filtered{area = {{x + b.left_top.x + 0.01, y + b.left_top.y + 0.01},
      {x + b.right_bottom.x - 0.01, y + b.right_bottom.y - 0.01}}}) do
    if not PASSABLE[e.type] then return false end
  end
  return true
end

-- why spec does not fit, and the nearest position where it does
local function blocked_by(proto, spec)
  local b, x, y = proto.collision_box, spec.position[1], spec.position[2]
  local area = {{x + b.left_top.x, y + b.left_top.y}, {x + b.right_bottom.x, y + b.right_bottom.y}}
  local what = {}
  for _, e in pairs(s.find_entities_filtered{area = area}) do
    if e.type ~= "resource" then
      local n = e.name == "entity-ghost" and e.ghost_name .. " ghost" or e.name
      what[n] = (what[n] or 0) + 1
    end
  end
  local water = s.count_tiles_filtered{area = area, collision_mask = "water_tile"}
  if water > 0 then what["water tile"] = water end
  local parts = {}
  for n, c in pairs(what) do parts[#parts + 1] = c .. " " .. n end
  table.sort(parts)
  if proto.type == "mining-drill" and s.count_entities_filtered{area = area, type = "resource"} == 0 then
    parts[#parts + 1] = "no ore under it"
  end
  local msg = string.format("%s does not fit at (%.1f, %.1f): %s", spec.name, x, y,
    #parts > 0 and table.concat(parts, ", ") or "blocked by terrain")
  -- nearest fitting position on this entity's grid, ring by ring
  local cx, cy = on_grid(proto, x, y)
  for r = 1, 16 do
    local best, bd
    for dx = -r, r do for dy = -r, r do
      if math.max(math.abs(dx), math.abs(dy)) == r then
        spec.position = {cx + dx, cy + dy}
        local d = dx * dx + dy * dy
        if (not bd or d < bd) and fits(proto, spec) then best, bd = spec.position, d end
      end
    end end
    if best then return msg .. string.format("; nearest spot that fits is (%.1f, %.1f)", best[1], best[2]) end
  end
  return msg .. "; nothing fits within 16 tiles"
end

local acts = {}

function acts.look()
  local list = {}
  if A.count then
    for _, e in pairs(s.find_entities_filtered{area = {{A.x0, A.y0}, {A.x1, A.y1}}, force = "player"}) do
      local n = e.name == "entity-ghost" and e.ghost_name .. " (ghost)" or e.name
      list[n] = (list[n] or 0) + 1
    end
    return out{ok = true, did = list}
  end
  local limit = A.limit or 200
  local area = {{A.x0, A.y0}, {A.x1, A.y1}}
  for _, e in pairs(s.find_entities_filtered{area = area, force = "player", limit = limit}) do
    local r = nil
    if e.type == "assembling-machine" or e.type == "furnace" then r = e.get_recipe() r = r and r.name end
    list[#list + 1] = {name = e.name == "entity-ghost" and e.ghost_name .. " (ghost)" or e.name, x = e.position.x,
      y = e.position.y, direction = dir_name[e.direction], recipe = r, status = e.status and status_name[e.status] or nil,
      deconstruct = e.to_be_deconstructed() or nil}
  end
  local total = #list < limit and #list or s.count_entities_filtered{area = area, force = "player"}
  out{ok = true, did = list, more = total > #list and string.format("%d more not shown: narrow the area, or count=true", total - #list) or nil}
end

function acts.resources()
  -- group ore by 32-tile chunk, then join touching chunks of the same ore into patches
  local chunks = {}
  for _, r in pairs(s.find_entities_filtered{area = {{A.x0, A.y0}, {A.x1, A.y1}}, type = "resource"}) do
    local key = r.name .. "|" .. math.floor(r.position.x / 32) .. "|" .. math.floor(r.position.y / 32)
    local c = chunks[key]
    if not c then
      c = {name = r.name, cx = math.floor(r.position.x / 32), cy = math.floor(r.position.y / 32), tiles = 0, amount = 0,
        x0 = r.position.x, y0 = r.position.y, x1 = r.position.x, y1 = r.position.y}
      chunks[key] = c
    end
    c.tiles, c.amount = c.tiles + 1, c.amount + r.amount
    c.x0, c.y0 = math.min(c.x0, r.position.x), math.min(c.y0, r.position.y)
    c.x1, c.y1 = math.max(c.x1, r.position.x), math.max(c.y1, r.position.y)
  end
  local patches, seen = {}, {}
  for key, c in pairs(chunks) do
    if not seen[key] then
      local p = {name = c.name, tiles = 0, amount = 0, x0 = c.x0, y0 = c.y0, x1 = c.x1, y1 = c.y1}
      local todo = {key}
      seen[key] = true
      while #todo > 0 do
        local k = table.remove(todo)
        local d = chunks[k]
        p.tiles, p.amount = p.tiles + d.tiles, p.amount + d.amount
        p.x0, p.y0, p.x1, p.y1 = math.min(p.x0, d.x0), math.min(p.y0, d.y0), math.max(p.x1, d.x1), math.max(p.y1, d.y1)
        for dx = -1, 1 do for dy = -1, 1 do
          local n = d.name .. "|" .. (d.cx + dx) .. "|" .. (d.cy + dy)
          if chunks[n] and not seen[n] then seen[n] = true todo[#todo + 1] = n end
        end end
      end
      p.drills = s.count_entities_filtered{area = {{p.x0, p.y0}, {p.x1 + 1, p.y1 + 1}}, type = "mining-drill", force = "player"}
      patches[#patches + 1] = p
    end
  end
  table.sort(patches, function(a, b) return a.amount > b.amount end)
  out{ok = true, did = patches}
end

function acts.network()
  local net = builder{A.x, A.y}
  if not net then return refuse(string.format("no roboport's construction area covers (%.1f, %.1f)%s", A.x, A.y,
    nearest_roboport{A.x, A.y})) end
  local items = {}
  for _, it in pairs(net.get_contents()) do items[it.name] = (items[it.name] or 0) + it.count end
  out{ok = true, did = {roboports = #net.cells, construction_robots = net.all_construction_robots,
    construction_idle = net.available_construction_robots, logistic_robots = net.all_logistic_robots, items = items}}
end

function acts.rate()
  local st = f.get_item_production_statistics(s)
  local P = defines.flow_precision_index
  local res = {}
  for _, item in pairs(A.items or {}) do
    if not prototypes.item[item] then return refuse("no item named " .. tostring(item)) end
    local function flow(cat, idx) return st.get_flow_count{name = item, category = cat, precision_index = idx, count = false} end
    res[item] = {made_1m = flow("input", P.one_minute), used_1m = flow("output", P.one_minute),
      made_10m = flow("input", P.ten_minutes), used_10m = flow("output", P.ten_minutes)}
  end
  out{ok = true, did = res}
end

-- place one ghost after the same checks a player's ghost gets; returns ok and what happened or why not
local function place(name, x, y, direction, recipe)
  local proto = prototypes.entity[name]
  if not proto then return false, "no entity named " .. tostring(name) end
  local items = proto.items_to_place_this
  if not items or not items[1] then return false, name .. " has no item that places it" end
  x, y = on_grid(proto, x, y)
  local spec = {name = name, position = {x, y}, direction = dir(direction), force = "player",
    build_check_type = defines.build_check_type.manual_ghost}
  if not fits(proto, spec) then return false, blocked_by(proto, spec) end
  local g = s.create_entity{name = "entity-ghost", inner_name = name, position = {x, y}, direction = dir(direction), force = "player"}
  if not g then return false, "the engine refused the ghost" end
  if recipe then
    local ok, err = pcall(g.set_recipe, recipe)
    if not ok then g.destroy() return false, "recipe: " .. tostring(err) end
  end
  return true, "ghost " .. fmt(g), covered(g.position, items[1].name)
end

function acts.ghost()
  local ok, msg, warn = place(A.name, A.x, A.y, A.direction, A.recipe)
  if not ok then return refuse(msg) end
  out{ok = true, did = msg, warn = warn}
end

function acts.ghosts()
  -- list of [name, x, y, direction, recipe]; each placed or refused on its own
  local placed, refused, warns = 0, {}, {}
  for i, g in ipairs(A.list or {}) do
    local ok, msg, warn = place(g[1], g[2], g[3], g[4], g[5])
    if ok then placed = placed + 1 else refused[#refused + 1] = i .. ": " .. msg end
    if warn then warns[warn] = true end
  end
  local w = {} for k in pairs(warns) do w[#w + 1] = k end
  out{ok = #refused == 0, did = string.format("placed %d of %d ghosts", placed, #(A.list or {})),
    refused = #refused > 0 and refused or nil, warn = #w > 0 and w or nil}
end

function acts.blueprint()
  local inv = game.create_inventory(1)
  local stack = inv[1]
  if stack.import_stack(A.bp) ~= 0 or not stack.is_blueprint then inv.destroy() return refuse("not a blueprint string") end
  local total = stack.get_blueprint_entity_count()
  local ghosts = stack.build_blueprint{surface = s, force = "player", position = {A.x, A.y}, direction = dir(A.direction),
    build_mode = defines.build_mode.normal}
  inv.destroy()
  if #ghosts == 0 then return refuse("nothing in the blueprint fits there") end
  out{ok = #ghosts == total, did = string.format("placed %d of %d ghosts", #ghosts, total),
    warn = covered({A.x, A.y})}
end

function acts.remove()
  local e, why = on_tile(A.name)
  if not e then return refuse(why) end
  if e.name == "entity-ghost" then local d = fmt(e) e.destroy() return out{ok = true, did = "removed " .. d} end
  if e.to_be_deconstructed() then return refuse(fmt(e) .. " is already marked") end
  if not e.order_deconstruction("player") then return refuse("the engine refused to mark " .. fmt(e)) end
  out{ok = true, did = "marked " .. fmt(e), warn = covered(e.position)}
end

function acts.cancel()
  local e, why = on_tile(A.name)
  if not e then return refuse(why) end
  if not e.to_be_deconstructed() then return refuse(fmt(e) .. " is not marked") end
  e.cancel_deconstruction("player")
  out{ok = true, did = "unmarked " .. fmt(e)}
end

function acts.recipe()
  local e
  for _, c in pairs(s.find_entities_filtered{position = {A.x, A.y}, force = "player"}) do
    local t = c.name == "entity-ghost" and c.ghost_type or c.type
    if t == "assembling-machine" then e = c end
  end
  if not e then return refuse(string.format("no assembler covers (%.1f, %.1f)", A.x, A.y)) end
  local r = f.recipes[A.recipe]
  if not r then return refuse("no recipe named " .. tostring(A.recipe)) end
  if not r.enabled then return refuse(A.recipe .. " is not researched") end
  local ok, removed = pcall(e.set_recipe, A.recipe)
  if not ok then return refuse(tostring(removed)) end
  local spilled = {}
  for _, it in pairs(removed or {}) do
    s.spill_item_stack{position = e.position, stack = {name = it.name, count = it.count, quality = it.quality},
      enable_looted = true, force = "player", allow_belts = false}
    spilled[#spilled + 1] = it.count .. " " .. it.name
  end
  out{ok = true, did = "recipe " .. A.recipe .. " on " .. fmt(e), spilled = spilled}
end

function acts.research()
  local t = f.technologies[A.tech]
  if not t then return refuse("no technology named " .. tostring(A.tech)) end
  if t.researched then return refuse(A.tech .. " is already researched") end
  if t.prototype.research_trigger then return refuse(A.tech .. " is a trigger tech: it completes by doing, not in labs") end
  for name, pre in pairs(t.prerequisites) do
    if not pre.researched then return refuse(A.tech .. " needs " .. name .. " first") end
  end
  if f.current_research == t then return refuse(A.tech .. " is being researched now") end
  for _, q in pairs(f.research_queue or {}) do
    if q.name == A.tech then return refuse(A.tech .. " is already queued") end
  end
  if not f.add_research(t) then return refuse("the engine refused to queue " .. A.tech) end
  out{ok = true, did = "queued " .. A.tech}
end

local fn = acts[ACT.verb]
if not fn then return refuse("no act named " .. tostring(ACT.verb)) end
fn()
