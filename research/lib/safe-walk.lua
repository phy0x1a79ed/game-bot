-- safe-walk.lua: one read-and-react step for safe-walk.sh. safe-walk.sh prepends a header
-- that sets SEAT, MODE ('leg' | 'retreat' | 'cease'), TX, TY, R, CLOSE_R, SCREEN, FORCE_SCREEN, LEG, RMAX.
-- leg:     read seat hp + enemy units within R; aim the equipped gun at the nearest unit
--          (shooting_state, only when it is in gun range and ammo is loaded); throw ONE defender
--          when an enemy is within R (or FORCE_SCREEN) and followers + capsules in flight < SCREEN
--          (the capsule cooldown allows one throw per call). Prints one key=value line, including
--          the next waypoint (wx,wy): LEG tiles toward (TX,TY), nudged off any colliding tile.
-- retreat: pick the nearest armed turret group (>= 2 armed turrets within 12), preferring one
--          that lies away from the threat centroid, and print a walkable point behind it.
-- cease:   stop shooting.
local p = game.players[SEAT]
local c = p and p.character
if not c then rcon.print('dead=1') return end
local s, pos = c.surface, c.position
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

if MODE == 'cease' then
  p.shooting_state = {state = defines.shooting.not_shooting}
  rcon.print('dead=0 ceased=1') return
end

local units = s.find_entities_filtered{force = 'enemy', type = 'unit', position = pos, radius = R}
local near, nd, close, cx, cy = nil, 1e9, 0, 0, 0
for _, u in pairs(units) do
  local d = dist(u.position, pos)
  if d < nd then near, nd = u, d end
  if d <= CLOSE_R then close = close + 1 end
  cx, cy = cx + u.position.x, cy + u.position.y
end
if #units > 0 then cx, cy = cx / #units, cy / #units else cx, cy = pos.x, pos.y end

-- a worm (enemy turret) whose range reaches within 6 tiles of the seat
local worm = 'none'
for _, w in pairs(s.find_entities_filtered{force = 'enemy', type = 'turret', position = pos, radius = R + 25}) do
  local ap = prototypes.entity[w.name].attack_parameters
  local r = (ap and ap.range or 25) + 6
  if dist(w.position, pos) <= r then
    worm = string.format('%s@%.0f,%.0f', w.name, w.position.x, w.position.y)
    cx, cy = w.position.x, w.position.y
    break
  end
end

if MODE == 'retreat' then
  local armed = {}
  for _, t in pairs(s.find_entities_filtered{force = 'player', type = {'ammo-turret', 'electric-turret', 'fluid-turret'}, position = pos, radius = RMAX or 300}) do
    local ok = false
    if t.type == 'ammo-turret' then
      local inv = t.get_inventory(defines.inventory.turret_ammo)
      ok = inv and not inv.is_empty()
    elseif t.type == 'fluid-turret' then
      local okf, n = pcall(function() return t.get_fluid_count() end)
      ok = okf and n > 0
    else
      ok = t.energy > 0
    end
    if ok then armed[#armed + 1] = t end
  end
  local threat = {x = cx, y = cy}
  local hasthreat = #units > 0 or worm ~= 'none'
  local best, bestd, bestg, bestn
  for pass = 1, 2 do
    for _, t in pairs(armed) do
      local d = dist(t.position, pos)
      local away = (not hasthreat) or pass == 2 or (dist(t.position, threat) - dist(pos, threat) >= -5)
      if away and (not bestd or d < bestd) then
        local gx, gy, n = 0, 0, 0
        for _, o in pairs(armed) do
          if dist(o.position, t.position) <= 12 then gx, gy, n = gx + o.position.x, gy + o.position.y, n + 1 end
        end
        if n >= 2 then best, bestd, bestg, bestn = t, d, {x = gx / n, y = gy / n}, n end
      end
    end
    if best then break end
  end
  if not best then rcon.print('dead=0 group=none armed=' .. #armed) return end
  -- step 3 tiles behind the group: away from the threat, or toward spawn when nothing threatens
  local fx, fy
  if hasthreat then fx, fy = bestg.x - cx, bestg.y - cy else fx, fy = -bestg.x, -bestg.y end
  local fl = math.sqrt(fx * fx + fy * fy)
  if fl < 0.01 then fx, fy, fl = 0, 1, 1 end
  local want = {x = bestg.x + 3 * fx / fl, y = bestg.y + 3 * fy / fl}
  local rp = s.find_non_colliding_position('character', want, 8, 0.5) or want
  rcon.print(string.format('dead=0 group=%d gx=%.1f gy=%.1f rx=%.1f ry=%.1f gd=%.0f', bestn, bestg.x, bestg.y, rp.x, rp.y, bestd))
  return
end

-- MODE == 'leg'
local gi = c.selected_gun_index
local gun = c.get_inventory(defines.inventory.character_guns)[gi]
local am = c.get_inventory(defines.inventory.character_ammo)[gi]
local range, ammo = 0, 0
if gun.valid_for_read then
  local ap = prototypes.item[gun.name].attack_parameters
  range = ap and ap.range or 0
end
if am.valid_for_read then ammo = am.count end
local fire = 0
if near and ammo > 0 and nd <= range + 1 then
  p.shooting_state = {state = defines.shooting.shooting_enemies, position = near.position}
  fire = 1
else
  p.shooting_state = {state = defines.shooting.not_shooting}
end

local fol = #c.following_robots
local flying = #s.find_entities_filtered{type = 'projectile', name = 'defender-capsule', position = pos, radius = 25}
local defs = c.get_item_count('defender-capsule')
local cap = p.force.maximum_following_robot_count
local dep = 0
if (#units > 0 or worm ~= 'none' or FORCE_SCREEN == 1) and defs > 0 and fol + flying < math.min(SCREEN, cap) then
  local st = c.get_main_inventory().find_item_stack('defender-capsule')
  if st then
    p.clear_cursor()
    p.cursor_stack.transfer_stack(st)
    local before = p.cursor_stack.count
    p.use_from_cursor(pos)
    if not p.cursor_stack.valid_for_read or p.cursor_stack.count < before then dep = 1 end
    p.clear_cursor()
  end
end

local dt = dist(pos, {x = TX, y = TY})
local wp = {x = TX, y = TY}
if dt > LEG then wp = {x = pos.x + (TX - pos.x) * LEG / dt, y = pos.y + (TY - pos.y) * LEG / dt} end
wp = s.find_non_colliding_position('character', wp, 3, 0.5) or wp

rcon.print(string.format(
  'dead=0 wx=%.1f wy=%.1f tick=%d x=%.1f y=%.1f hp=%.0f max=%.0f d=%.1f walk=%d units=%d close=%d near=%s nd=%.1f cx=%.1f cy=%.1f worm=%s ammo=%d range=%.0f fire=%d fol=%d fly=%d dep=%d defs=%d',
  wp.x, wp.y, game.tick, pos.x, pos.y, c.health, c.max_health, dt, c.walking_state.walking and 1 or 0,
  #units, close, near and near.name or 'none', near and nd or -1, cx, cy, worm, ammo, range, fire, fol, flying, dep - 0, defs - dep))
