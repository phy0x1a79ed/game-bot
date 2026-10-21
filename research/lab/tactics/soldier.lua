-- soldier: the run-4 doctrine. A scripted body assaults the nest from a turret anchor outside worm range:
-- defenders up before the approach, poison on the target, SMG fire, retreat to the anchor under `hp_retreat`,
-- and a new body at the anchor `respawn` ticks after a death.
-- params: anchor_turrets, defenders, poison (bool), hp_retreat, respawn, armor ("power-armor" | "none"), fire_range, from {x, y}
local ctx = ...
local surf, P = ctx.surface, ctx.params
local ANCHOR_N = P.anchor_turrets or 4
local DEFENDERS = P.defenders or 5
local POISON = P.poison ~= false
local HP_RETREAT = P.hp_retreat or 0.4
local RESPAWN = P.respawn or 600
local ARMOR = P.armor or "power-armor"
local FIRE = P.fire_range or 15
local GEAR = {"fission-reactor-equipment", "exoskeleton-equipment", "exoskeleton-equipment",
              "energy-shield-mk2-equipment", "energy-shield-mk2-equipment", "energy-shield-mk2-equipment",
              "energy-shield-mk2-equipment", "personal-laser-defense-equipment", "personal-laser-defense-equipment",
              "personal-laser-defense-equipment", "battery-mk2-equipment", "battery-mk2-equipment"}
local DIRS = {defines.direction.east, defines.direction.southeast, defines.direction.south, defines.direction.southwest,
              defines.direction.west, defines.direction.northwest, defines.direction.north, defines.direction.northeast}
local C = {deaths = 0, respawns = 0, defenders = 0, poison = 0, retreats = 0, mode = "arm", next_def = 0, next_poison = 0}
local body, anchor, respawn_at
local detour = {sign = 1, until_tick = 0, check = 0}

local function equip(c)
  ctx.give(c, "submachine-gun", 1)
  ctx.give(c, "piercing-rounds-magazine", 200)
  ctx.give(c, "defender-capsule", 40)
  if POISON then ctx.give(c, "poison-capsule", 30) end
  if ARMOR ~= "none" then
    ctx.give(c, ARMOR, 1)
    if c.grid then
      for _, name in ipairs(GEAR) do
        if c.grid.put{name = name} then ctx.book(name, 1) end
      end
    end
  end
end

local function spawn()
  body = ctx.body(anchor)
  equip(body)
  C.mode = "arm"
end

local function nearest(list, p)
  local best, bd
  for _, e in pairs(list) do
    local d = (e.position.x - p.x) ^ 2 + (e.position.y - p.y) ^ 2
    if not bd or d < bd then best, bd = e, d end
  end
  return best, bd and math.sqrt(bd)
end

local function throw(c, item, target)
  local main = c.get_main_inventory()
  if main.get_item_count(item) == 0 then return false end
  main.remove{name = item, count = 1}
  surf.create_entity{name = item, position = c.position, target = target, source = c, force = ctx.force, speed = 0.3}
  return true
end

local function walk_angle(c, a)
  c.walking_state = {walking = true, direction = DIRS[math.floor(a / (2 * math.pi) * 8 + 0.5) % 8 + 1]}
end

local function walk(c, to)
  if not to then c.walking_state = {walking = false} return end
  walk_angle(c, math.atan2(to.y - c.position.y, to.x - c.position.x))
end

-- A body walks in a straight line, so a cliff stops it. Not moving for 30 ticks sends it sideways for 45.
local function approach(c, to, tick)
  local a = math.atan2(to.y - c.position.y, to.x - c.position.x)
  if tick < detour.until_tick then walk_angle(c, a + detour.sign * math.pi / 2) return end
  if tick >= detour.check then
    local p = detour.pos
    if p and (p.x - c.position.x) ^ 2 + (p.y - c.position.y) ^ 2 < 1 then
      detour.until_tick, detour.sign = tick + 45, -detour.sign
    end
    detour.pos, detour.check = {x = c.position.x, y = c.position.y}, tick + 30
  end
  walk_angle(c, a)
end

local function defenders_of(c)
  local n = 0
  for _, d in pairs(surf.find_entities_filtered{name = "defender", position = c.position, radius = 40}) do
    if d.combat_robot_owner == c then n = n + 1 end
  end
  return n
end

-- Health share counting shields, the way a player reads the bar.
local function hp(c)
  local h, m = c.health, c.max_health
  if c.grid then h, m = h + c.grid.shield, m + c.grid.max_shield end
  return h / m
end

return {
  setup = function()
    local from = P.from or {x = ctx.nest.x, y = ctx.nest.y - 51}
    local tgt = nearest(ctx.statics(), from)
    local dx, dy = from.x - tgt.position.x, from.y - tgt.position.y
    local d = math.sqrt(dx * dx + dy * dy)
    anchor = {x = tgt.position.x + dx / d * 36, y = tgt.position.y + dy / d * 36}
    for i = 1, ANCHOR_N do
      local pos = surf.find_non_colliding_position("gun-turret", {anchor.x - 4 + (i - 1) * 2.5, anchor.y + 2.5}, 6, 0.5)
      local t = ctx.place("gun-turret", pos)
      ctx.give(t, "piercing-rounds-magazine", 50)
    end
    spawn()
  end,

  step = function(tick)
    local c = body
    if not (c and c.valid) then
      if not respawn_at then C.deaths = C.deaths + 1 respawn_at = tick + RESPAWN end
      if tick >= respawn_at then respawn_at = nil C.respawns = C.respawns + 1 spawn() end
      return
    end
    local live = ctx.statics()
    if #live == 0 then return true end
    -- defenders first, whatever the mode
    if tick >= C.next_def and defenders_of(c) < DEFENDERS then
      if throw(c, "defender-capsule", c.position) then C.defenders = C.defenders + 1 end
      C.next_def = tick + 15
    end
    local h = hp(c)
    if C.mode == "retreat" then
      c.shooting_state = {state = defines.shooting.not_shooting}
      local d = math.sqrt((c.position.x - anchor.x) ^ 2 + (c.position.y - anchor.y) ^ 2)
      walk(c, d > 2 and anchor or nil)
      if h >= 0.95 then C.mode = "arm" end
      return
    end
    if h < HP_RETREAT then C.mode = "retreat" C.retreats = C.retreats + 1 return end
    if C.mode == "arm" then
      walk(c, nil)
      -- out of capsules, waiting for defenders would wait for ever
      if defenders_of(c) >= DEFENDERS or c.get_main_inventory().get_item_count("defender-capsule") == 0 then
        C.mode = "attack"
      end
      return
    end
    local tgt, d = nearest(live, c.position)
    c.shooting_state = {state = defines.shooting.shooting_enemies, position = tgt.position}
    if d > FIRE then approach(c, tgt.position, tick) else walk(c, nil) detour.pos = nil end
    if POISON and d <= 24 and tick >= C.next_poison
       and surf.count_entities_filtered{name = "poison-cloud", position = tgt.position, radius = 6} == 0 then
      if throw(c, "poison-capsule", tgt.position) then C.poison = C.poison + 1 end
      C.next_poison = tick + 30
    end
  end,

  report = function() return C end,
}
