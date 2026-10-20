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

return M
