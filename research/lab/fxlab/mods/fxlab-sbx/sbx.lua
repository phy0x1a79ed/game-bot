-- Core: the sandbox registry and the god ledger, shared by slice.lua, god.lua and view.lua.
-- storage.sbx = {boxes = {[name] = box}, ledger = {[name] = {entry, ...}}}
-- box = {name, surface = <surface name>, force = <force name>, mode = "god" | "standard", created = tick,
--        inplace = true when the box adopts an existing surface and force instead of owning its own}
local M = {remote = {}}

local NAME = "^[%w_%-]+$"
M.FORCE_CAP = 64

-- Raise a contract error: the dispatcher turns it into {ok = false, error = code, detail = detail}.
function M.fail(code, detail)
  error({sbx_error = code, detail = detail}, 0)
end

local function init()
  storage.sbx = storage.sbx or {}
  storage.sbx.boxes = storage.sbx.boxes or {}
  storage.sbx.ledger = storage.sbx.ledger or {}
end
M.on_init = init
M.on_configuration_changed = init

function M.get(name)
  local box = storage.sbx.boxes[name or ""]
  if not box then M.fail("no_sandbox", tostring(name)) end
  return box
end

function M.surface(box) return game.surfaces[box.surface] end
function M.force(box) return game.forces[box.force] end

-- Refuse a god call on a standard-mode sandbox.
function M.require_god(name)
  local box = M.get(name)
  if box.mode ~= "god" then M.fail("standard_mode", name .. " plays by standard rules; switch with sbx_mode") end
  return box
end

-- new{name, research = "copy" | "none"}: a sandbox surface and force, in god mode.
-- new{name, inplace = {surface, force}}: a box over an existing surface and force, for an in-place arm.
function M.new(a)
  local name = a.name
  if type(name) ~= "string" or #name > 32 or not name:match(NAME) then
    M.fail("bad_args", "name must be 1-32 letters, digits, - or _")
  end
  if storage.sbx.boxes[name] then M.fail("exists", name) end
  if a.inplace then
    local s, f = game.surfaces[a.inplace.surface or ""], game.forces[a.inplace.force or ""]
    if not (s and f) then M.fail("bad_args", "inplace needs an existing surface and force") end
    local box = {name = name, surface = s.name, force = f.name, mode = "god", created = game.tick, inplace = true}
    storage.sbx.boxes[name] = box
    storage.sbx.ledger[name] = {}
    return box
  end
  if #game.forces >= M.FORCE_CAP then M.fail("force_cap", "the game allows 64 forces") end
  local fname = "sbx-" .. name
  local f = game.forces[fname] or game.create_force(fname)
  if (a.research or "copy") == "copy" then f.copy_from(game.forces.player) end
  f.set_friend("player", true) game.forces.player.set_friend(f, true)
  f.set_cease_fire("player", true) game.forces.player.set_cease_fire(f, true)
  local s = game.surfaces[fname]
  if not s then
    s = game.create_surface(fname, {width = 4096, height = 4096})
    s.generate_with_lab_tiles = true
    s.always_day = true
  end
  for _, other in pairs(game.forces) do other.set_surface_hidden(s, true) end
  f.set_surface_hidden(s, false)
  local box = {name = name, surface = s.name, force = f.name, mode = "god", created = game.tick}
  storage.sbx.boxes[name] = box
  storage.sbx.ledger[name] = {}
  return box
end

-- drop{name}: delete the sandbox's surfaces and merge its force away. An in-place box only loses its record:
-- its owner (slice.lua) must remove what it placed before it drops the box.
function M.drop(name)
  local box = M.get(name)
  if box.inplace then
    storage.sbx.boxes[name] = nil
    storage.sbx.ledger[name] = nil
    return
  end
  for sname in pairs(game.surfaces) do
    if sname == box.surface or sname:sub(1, #box.surface + 1) == box.surface .. "-" then game.delete_surface(sname) end
  end
  local f = M.force(box)
  if f then game.merge_forces(f, "neutral") end
  storage.sbx.boxes[name] = nil
  storage.sbx.ledger[name] = nil
end

-- ledger_add(name, entry): record what a god call did, so sbx_mode can undo it.
-- entry.kind is "entity" (entry.entity = LuaEntity), "bonus" (field, before, after), "research"
-- (tech, before, after) or "body" (entity, before = {reach, build, mine, destructible}).
function M.ledger_add(name, entry)
  local list = storage.sbx.ledger[name]
  if not list then M.fail("no_sandbox", tostring(name)) end
  entry.tick = game.tick
  list[#list + 1] = entry
end

function M.ledger(name) return storage.sbx.ledger[name] or {} end

M.remote.sandbox_new = function(a) return {sandbox = M.new(a)} end
M.remote.sandbox_drop = function(a) M.drop(a.name) return {} end
M.remote.sandbox_list = function()
  local out = {}
  for _, box in pairs(storage.sbx.boxes) do
    out[#out + 1] = {name = box.name, surface = box.surface, force = box.force, mode = box.mode,
                     created = box.created, inplace = box.inplace or false,
                     ledger = #(storage.sbx.ledger[box.name] or {})}
  end
  return {sandboxes = out}
end

return M
