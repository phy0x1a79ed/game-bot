-- One scripted gun-turret creep against a nest, run by the fidelity fixture on a slice or on nauvis.
-- Input: global FID = {box, surface, force, nest = {x, y, r}, clear_radius, ammo, load, n, stage, standoff, stages,
-- from = {x, y}, t0, cap}. Run it after stop.lua, which owns the tick handler; its state lives in the global `fid`.
-- Ammo is free.
-- Every `stage` ticks a group of `n` turrets lands `standoff` tiles short of the nearest live spawner or worm, on the line
-- from the last group, and every live turret is topped up to `load` magazines through the god `items` verb.
-- Once `fid.arm()` has started the creep, the game pauses when the nest is clear or `cap` ticks have passed.
-- `fid.report()` reads the outcome.

fid = fid or {}
local P = FID
local nest = P.nest
fid.p = P
fid.lost, fid.given, fid.placed, fid.stage = 0, 0, 0, 0
fid.mine = {}
fid.centre = {x = P.from.x, y = P.from.y}
fid.next = P.t0
fid.cleared, fid.err, fid.step = nil, nil, nil

local function surf() return game.surfaces[P.surface] end

local DIRECTIONS = {defines.direction.east, defines.direction.southeast, defines.direction.south, defines.direction.southwest,
                    defines.direction.west, defines.direction.northwest, defines.direction.north, defines.direction.northeast}

local function statics()
  return surf().find_entities_filtered{force = "enemy", type = {"unit-spawner", "turret"}, position = nest, radius = nest.r}
end

local function mine()
  return surf().find_entities_filtered{force = P.force, name = "gun-turret", position = nest, radius = nest.r + 40}
end

local function top_up(turret)
  local have = turret.get_inventory(defines.inventory.turret_ammo).get_item_count(P.ammo)
  if have >= P.load then return end
  local p = turret.position
  local reply = remote.call("sbx", "items", {name = P.box, target = "entity", entity = "gun-turret", at = {p.x, p.y},
                                              items = {{name = P.ammo, count = P.load - have}}})
  if not reply.ok then error("items: " .. tostring(reply.error) .. " " .. tostring(reply.detail)) end
  fid.given = fid.given + (reply.inserted[P.ammo] or 0)
end

local function place_group(target)
  local from = fid.centre
  local dx, dy = from.x - target.x, from.y - target.y
  local d = math.max(0.1, math.sqrt(dx * dx + dy * dy))
  local ux, uy = dx / d, dy / d
  local cx, cy = target.x + ux * P.standoff, target.y + uy * P.standoff
  local px, py = -uy, ux
  for i = 1, P.n do
    local row = (i - 1) % 2
    local col = math.floor((i - 1) / 2) - (math.ceil(P.n / 2) - 1) / 2
    local x, y = cx + px * col * 2.5 + ux * row * 2.5, cy + py * col * 2.5 + uy * row * 2.5
    local pos = surf().find_non_colliding_position("gun-turret", {x, y}, 6, 0.5)
    if pos then
      local a = math.atan2(-uy, -ux)
      local t = surf().create_entity{name = "gun-turret", position = pos, force = P.force,
                                   direction = DIRECTIONS[math.floor(a / (2 * math.pi) * 8 + 0.5) % 8 + 1]}
      if t then
        fid.placed = fid.placed + 1
        fid.mine[t.unit_number] = true
        top_up(t)
      end
    end
  end
  fid.centre = {x = cx, y = cy}
end

local function step(tick)
  if tick >= fid.next then
    local live = statics()
    if #live == 0 or fid.stage >= P.stages then
      fid.next = math.huge
    else
      for _, t in pairs(mine()) do top_up(t) end
      local best, bd
      for _, e in pairs(live) do
        local d = (e.position.x - fid.centre.x) ^ 2 + (e.position.y - fid.centre.y) ^ 2
        if not bd or d < bd then best, bd = e, d end
      end
      place_group(best.position)
      fid.stage = fid.stage + 1
      fid.next = tick + P.stage
    end
  end
  if tick % 30 == 0 and not fid.cleared then
    local left = surf().count_entities_filtered{force = "enemy", type = {"unit-spawner", "turret"}, position = nest,
                                              radius = P.clear_radius}
    if left == 0 then fid.cleared = tick - P.t0 end
  end
end

function fid.arm() fid.step = step end

function fid.report()
  local s = surf()
  local left = {spawners = 0, worms = 0}
  for _, e in pairs(s.find_entities_filtered{force = "enemy", type = {"unit-spawner", "turret"}, position = nest, radius = nest.r}) do
    if e.type == "unit-spawner" then left.spawners = left.spawners + 1 else left.worms = left.worms + 1 end
  end
  return {cleared = fid.cleared, ticks = fid.stopped and fid.stopped - P.t0, lost = fid.lost, given = fid.given,
          placed = fid.placed, stages = fid.stage, left = left, err = fid.err,
          evo = game.forces.enemy.get_evolution_factor(s)}
end

script.on_event(defines.events.on_entity_died, function(ev)
  local e = ev.entity
  if e.valid and e.unit_number and fid.mine[e.unit_number] then fid.lost = fid.lost + 1 end
end)

fid.on_tick = function(tick)
  if not (fid.step and tick >= P.t0) then return false end
  local ok, err = pcall(step, tick)
  if not ok then fid.err = tostring(err) end
  local over = not ok or fid.cleared ~= nil or tick >= P.t0 + P.cap
  if over then fid.step = nil end
  return over
end
rcon.print("ok")
