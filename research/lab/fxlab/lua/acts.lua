-- acts.lua: the safe-act surface. Expects ACT = {verb = ..., surface = ..., args = {...}}.
-- Prints JSON {ok = true, did = ...} or {ok = false, refused = reason}. Every act checks before it acts,
-- and none creates an item: entities appear only as ghosts that robots build from storage.
--   look {x0, y0, x1, y1, limit}      entities in an area, with recipe and status
--   ghost {name, x, y, direction, recipe}   place one ghost
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

local function covered(p, item)
  local net = f.find_logistic_network_by_position(p, s)
  if not net then return "outside any robot network" end
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

local acts = {}

function acts.look()
  local list = {}
  for _, e in pairs(s.find_entities_filtered{area = {{A.x0, A.y0}, {A.x1, A.y1}}, force = "player", limit = A.limit or 200}) do
    local r = nil
    if e.type == "assembling-machine" or e.type == "furnace" then r = e.get_recipe() r = r and r.name end
    list[#list + 1] = {name = e.name == "entity-ghost" and e.ghost_name .. " (ghost)" or e.name, x = e.position.x,
      y = e.position.y, direction = dir_name[e.direction], recipe = r, status = e.status and status_name[e.status] or nil,
      deconstruct = e.to_be_deconstructed() or nil}
  end
  out{ok = true, did = list}
end

function acts.ghost()
  local proto = prototypes.entity[A.name]
  if not proto then return refuse("no entity named " .. tostring(A.name)) end
  local items = proto.items_to_place_this
  if not items or not items[1] then return refuse(A.name .. " has no item that places it") end
  local spec = {name = A.name, position = {A.x, A.y}, direction = dir(A.direction), force = "player",
    build_check_type = defines.build_check_type.manual_ghost}
  if not s.can_place_entity(spec) then return refuse(string.format("%s does not fit at (%.1f, %.1f)", A.name, A.x, A.y)) end
  local g = s.create_entity{name = "entity-ghost", inner_name = A.name, position = {A.x, A.y}, direction = dir(A.direction), force = "player"}
  if not g then return refuse("the engine refused the ghost") end
  if A.recipe then
    local ok, err = pcall(g.set_recipe, A.recipe)
    if not ok then g.destroy() return refuse("recipe: " .. tostring(err)) end
  end
  out{ok = true, did = "ghost " .. fmt(g), warn = covered(g.position, items[1].name)}
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
