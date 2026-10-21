-- The camera booth and screenshots. storage.view = {player = <camera player name>, shots = <counter>}.
-- The camera is a real peer, so every state change here must stay deterministic.
local sbx = require("sbx")

local M = {remote = {}}

local BOOTH = "cam-booth"
local MAX_SIDE = 4096
local PX_PER_TILE = 32

local function init()
  storage.view = storage.view or {}
end
M.on_init = init
M.on_configuration_changed = init

local function xy(t) return {x = t.x or t[1], y = t.y or t[2]} end

local function booth_surface()
  local s = game.surfaces[BOOTH]
  if s then return s end
  s = game.create_surface(BOOTH, {width = 64, height = 64, starting_area = "none",
                                  no_enemies_mode = true, peaceful_mode = true})
  s.generate_with_lab_tiles = true
  s.always_day = true
  s.request_to_generate_chunks({0, 0}, 1)
  s.force_generate_chunk_requests()
  for _, f in pairs(game.forces) do f.set_surface_hidden(s, true) end
  return s
end

-- view_booth{player}: park the camera player on the hidden booth surface, as a spectator with no character.
function M.remote.view_booth(a)
  init()
  local p = game.players[a.player or ""]
  if not p then sbx.fail("not_found", "no player " .. tostring(a.player)) end
  local s = booth_surface()
  local body = p.character
  if p.controller_type ~= defines.controllers.spectator then
    p.set_controller{type = defines.controllers.spectator}
  end
  if body and body.valid then body.destroy() end
  if p.surface ~= s then p.teleport({0, 0}, s) end
  storage.view.player = p.name
  return {player = p.name, surface = p.surface.name, controller = tostring(p.controller_type)}
end

-- view_shot{surface, area | position, resolution, zoom, info, path, player}: the camera client writes a PNG
-- under script-output. An area is centred and sized to fill the frame at the zoom, each side capped at 4096.
function M.remote.view_shot(a)
  init()
  local p = game.players[a.player or storage.view.player or "fxcam"]
  if not (p and p.connected) then sbx.fail("not_found", "no connected camera player") end
  local s = game.surfaces[a.surface or "nauvis"]
  if not s then sbx.fail("bad_args", "no surface " .. tostring(a.surface)) end
  local zoom = a.zoom or 1
  local position, resolution
  if a.area then
    local lt, rb = xy(a.area[1] or a.area.left_top), xy(a.area[2] or a.area.right_bottom)
    position = {x = (lt.x + rb.x) / 2, y = (lt.y + rb.y) / 2}
    resolution = {x = math.ceil(math.abs(rb.x - lt.x) * PX_PER_TILE * zoom),
                  y = math.ceil(math.abs(rb.y - lt.y) * PX_PER_TILE * zoom)}
  elseif a.position then
    position = xy(a.position)
    resolution = a.resolution and xy(a.resolution) or {x = 1280, y = 720}
  else
    sbx.fail("bad_args", "need area or position")
  end
  resolution = {x = math.max(1, math.min(MAX_SIDE, resolution.x)), y = math.max(1, math.min(MAX_SIDE, resolution.y))}
  storage.view.shots = (storage.view.shots or 0) + 1
  local path = a.path or ("fxlab/shot-" .. game.tick .. "-" .. storage.view.shots .. ".png")
  game.take_screenshot{by_player = p, surface = s, position = position, resolution = resolution, zoom = zoom,
                       path = path, show_gui = false, show_entity_info = a.info and true or false,
                       daytime = 0, anti_alias = false}
  return {path = path, resolution = {resolution.x, resolution.y}, position = {position.x, position.y}}
end

local STAMP_PREFIX = "bp-view"
local STAMP_RADIUS = 3
local STAMP_MAX_RADIUS = 30
local STAMP_AT = {0, 0}

local function stamp_surface(name, radius)
  local s = game.surfaces[name]
  if not s then
    s = game.create_surface(name, {width = 2048, height = 2048, starting_area = "none",
                                   no_enemies_mode = true, peaceful_mode = true})
    s.generate_with_lab_tiles = true
    s.always_day = true
    for _, f in pairs(game.forces) do f.set_surface_hidden(s, true) end
  end
  s.request_to_generate_chunks({0, 0}, radius)
  s.force_generate_chunk_requests()
  return s
end

-- The blueprint's farthest entity or tile from its centre, in tiles.
local function blueprint_reach(stack)
  local reach = 0
  for _, e in pairs(stack.get_blueprint_entities() or {}) do
    reach = math.max(reach, math.abs(e.position.x), math.abs(e.position.y))
  end
  for _, t in pairs(stack.get_blueprint_tiles() or {}) do
    reach = math.max(reach, math.abs(t.position.x), math.abs(t.position.y))
  end
  return reach
end

local function owned_by_a_sandbox(name)
  for _, box in pairs((storage.sbx and storage.sbx.boxes) or {}) do
    if box.surface == name then return true end
    for _, extra in ipairs(box.surfaces or {}) do
      if extra == name then return true end
    end
  end
  return false
end

-- storage.view.stamped[surface] = {{x, y, name}, ...}: the tile each stamped tile replaced, in stamp order.
local function restore_tiles(s)
  local stamped = storage.view.stamped or {}
  local saved = stamped[s.name]
  if saved and #saved > 0 then
    local tiles = {}
    for i, t in ipairs(saved) do tiles[i] = {name = t[3], position = {t[1], t[2]}} end
    s.set_tiles(tiles)
  end
  stamped[s.name] = {}
  storage.view.stamped = stamped
end

local function remember_tile(s, pos, seen)
  local x, y = pos.x - 0.5, pos.y - 0.5
  local key = x .. "," .. y
  if seen[key] then return end
  seen[key] = true
  local list = storage.view.stamped[s.name]
  list[#list + 1] = {x, y, s.get_tile(pos.x, pos.y).name}
end

local function grow(box, lt, rb)
  if not box then return {lt[1], lt[2], rb[1], rb[2]} end
  return {math.min(box[1], lt[1]), math.min(box[2], lt[2]), math.max(box[3], rb[1]), math.max(box[4], rb[2])}
end

-- view_stamp{blueprint, surface = "bp-view", clear = true}: build a blueprint string on a hidden lab-tile surface
-- and revive every ghost. Returns built, left (ghosts that would not revive), area and surface. The string is
-- checked before the surface is touched, so a bad string leaves nothing behind. Only surfaces named bp-view* that
-- no sandbox record names are accepted, because clear destroys what stands on the surface (never a character) and
-- puts back the tiles an earlier stamp replaced.
function M.remote.view_stamp(a)
  init()
  local name = a.surface or STAMP_PREFIX
  if type(name) ~= "string" or name:sub(1, #STAMP_PREFIX) ~= STAMP_PREFIX then
    sbx.fail("bad_args", "surface must start with " .. STAMP_PREFIX)
  end
  if owned_by_a_sandbox(name) then sbx.fail("bad_args", "surface " .. name .. " belongs to a sandbox") end
  if type(a.blueprint) ~= "string" or a.blueprint == "" then sbx.fail("bad_args", "need a blueprint string") end
  local inv = game.create_inventory(1)
  local ok, err = pcall(function()
    local rc = inv[1].import_stack(a.blueprint)
    if rc == 1 or not inv[1].valid_for_read or not inv[1].is_blueprint or not inv[1].is_blueprint_setup() then
      sbx.fail("bad_args", "not a blueprint string")
    end
  end)
  if not ok then
    inv.destroy()
    if type(err) == "table" then error(err, 0) end
    sbx.fail("bad_args", "not a blueprint string: " .. tostring(err))
  end
  local reach = blueprint_reach(inv[1])
  local radius = math.max(STAMP_RADIUS, math.ceil((reach + 8) / 32))
  if radius > STAMP_MAX_RADIUS then
    inv.destroy()
    sbx.fail("bad_args", "blueprint reaches " .. reach .. " tiles from its centre; the limit is " .. (STAMP_MAX_RADIUS * 32 - 8))
  end
  local s = stamp_surface(name, radius)
  if a.clear ~= false then
    for _, e in pairs(s.find_entities()) do
      if e.type ~= "character" then e.destroy() end
    end
    restore_tiles(s)
  end
  storage.view.stamped = storage.view.stamped or {}
  storage.view.stamped[name] = storage.view.stamped[name] or {}
  local ghosts = inv[1].build_blueprint{surface = s, force = "player", position = STAMP_AT,
                                        build_mode = defines.build_mode.forced}
  inv.destroy()
  local seen = {}
  for _, t in ipairs(storage.view.stamped[name]) do seen[t[1] .. "," .. t[2]] = true end
  local built, tiles, left, box = 0, 0, {}, nil
  for _, g in ipairs(ghosts) do
    if g.valid then
      local gname, pos, is_tile = g.ghost_name, g.position, g.type == "tile-ghost"
      if is_tile then remember_tile(s, pos, seen) end
      local revived, placed = g.revive{raise_revive = false}
      if revived == nil then
        left[#left + 1] = {name = gname, position = {pos.x, pos.y}}
      elseif is_tile then
        tiles = tiles + 1
        box = grow(box, {pos.x - 0.5, pos.y - 0.5}, {pos.x + 0.5, pos.y + 0.5})
      else
        built = built + 1
        local bb = placed.bounding_box
        box = grow(box, {bb.left_top.x, bb.left_top.y}, {bb.right_bottom.x, bb.right_bottom.y})
      end
    end
  end
  return {built = built, tiles = tiles, left = left, surface = name,
          area = box and {{box[1], box[2]}, {box[3], box[4]}} or {{0, 0}, {0, 0}}}
end

return M
