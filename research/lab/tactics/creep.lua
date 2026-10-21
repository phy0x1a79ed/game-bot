-- creep: turret creep. Every `stage` ticks a group of `n` turrets lands `standoff` tiles short of the nearest live
-- spawner or worm, on the line from the last group, and every live turret is topped up to `load`.
-- params: turret, ammo (null for a fluid turret), fluid, load, n, stage, standoff, stages, from {x, y}
local ctx = ...
local surf, P = ctx.surface, ctx.params
local TURRET = P.turret or "gun-turret"
local AMMO = P.ammo
if AMMO == nil and not P.fluid then AMMO = "piercing-rounds-magazine" end
local FLUID = P.fluid
local LOAD = P.load or 50
local N = P.n or 8
local STAGE = P.stage or 1200
local STANDOFF = P.standoff or 14
local MAXSTAGES = P.stages or 12
local DIRS = {defines.direction.east, defines.direction.southeast, defines.direction.south, defines.direction.southwest,
              defines.direction.west, defines.direction.northwest, defines.direction.north, defines.direction.northeast}
local stage, nextAt = 0, ctx.tick0
local centre = P.from or {x = ctx.nest.x, y = ctx.nest.y - 51}

local function mine()
  return surf.find_entities_filtered{force = ctx.force, name = TURRET, position = ctx.nest, radius = ctx.scan_radius + 40}
end

local function top_up(t)
  if AMMO then
    local have = t.get_inventory(defines.inventory.turret_ammo).get_item_count(AMMO)
    if have < LOAD then ctx.give(t, AMMO, LOAD - have) end
  elseif FLUID then
    local n = t.insert_fluid{name = FLUID, amount = 1000}
    if n > 0 then ctx.book(FLUID, n) end
  end
end

local function place_group(target)
  local dx, dy = centre.x - target.x, centre.y - target.y
  local d = math.max(0.1, math.sqrt(dx * dx + dy * dy))
  local ux, uy = dx / d, dy / d
  local cx, cy = target.x + ux * STANDOFF, target.y + uy * STANDOFF
  local px, py = -uy, ux
  -- face the target: a flamethrower turret only fires inside an arc around its direction
  local dir = DIRS[math.floor(math.atan2(-uy, -ux) / (2 * math.pi) * 8 + 0.5) % 8 + 1]
  for i = 1, N do
    local row = (i - 1) % 2
    local col = math.floor((i - 1) / 2) - (math.ceil(N / 2) - 1) / 2
    local x, y = cx + px * col * 2.5 + ux * row * 2.5, cy + py * col * 2.5 + uy * row * 2.5
    local pos = surf.find_non_colliding_position(TURRET, {x, y}, 6, 0.5)
    local t = pos and ctx.place(TURRET, pos, dir)
    if t then top_up(t) end
  end
  centre = {x = cx, y = cy}
end

return {
  setup = function() end,
  step = function(tick)
    if FLUID and (tick - ctx.tick0) % 60 == 0 then for _, t in pairs(mine()) do top_up(t) end end
    if tick < nextAt then return end
    local live = ctx.statics()
    if #live == 0 or stage >= MAXSTAGES then return true end
    for _, t in pairs(mine()) do top_up(t) end
    local best, bd
    for _, e in pairs(live) do
      local d = (e.position.x - centre.x) ^ 2 + (e.position.y - centre.y) ^ 2
      if not bd or d < bd then best, bd = e, d end
    end
    place_group(best.position)
    stage = stage + 1
    nextAt = tick + STAGE
  end,
  report = function() return {stages = stage} end,
}
