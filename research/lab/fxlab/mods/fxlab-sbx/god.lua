-- God mode: research, items, enemies and bodies on a sandbox, and the switch back to standard rules.
-- Every call that changes the world is recorded with sbx.ledger_add, so sbx_mode can undo it.
-- storage.god = {waves = {[group id] = {box, group, units = {LuaEntity}, total, tick}}}
local sbx = require("sbx")
local M = {remote = {}}
local R = M.remote

local INF_LEVEL = 1000000
local SCALARS = {
  "manual_mining_speed_modifier", "manual_crafting_speed_modifier", "laboratory_speed_modifier",
  "laboratory_productivity_bonus", "worker_robots_speed_modifier", "worker_robots_storage_bonus",
  "worker_robots_battery_modifier", "character_trash_slot_count", "maximum_following_robot_count",
  "following_robots_lifetime_modifier", "mining_drill_productivity_bonus", "train_braking_force_bonus",
  "inserter_stack_size_bonus", "bulk_inserter_capacity_bonus", "belt_stack_size_bonus",
  "stack_inserter_capacity_bonus", "character_running_speed_modifier", "character_build_distance_bonus",
  "character_item_drop_distance_bonus", "character_reach_distance_bonus", "character_resource_reach_distance_bonus",
  "character_item_pickup_distance_bonus", "character_loot_pickup_distance_bonus", "character_inventory_slots_bonus",
  "character_health_bonus", "character_crafting_speed_modifier", "character_mining_speed_modifier",
  "deconstruction_time_to_live", "ghost_time_to_live", "artillery_range_modifier",
  "max_successful_attempts_per_tick_per_construction_queue", "max_failed_attempts_per_tick_per_construction_queue",
}
local TURRET_TYPES = {["ammo-turret"] = true, ["electric-turret"] = true, ["fluid-turret"] = true, turret = true}
local BODY_FIELDS = {
  reach = "character_reach_distance_bonus", build = "character_build_distance_bonus",
  mine = "character_resource_reach_distance_bonus", drop = "character_item_drop_distance_bonus",
}

M.on_init = function() storage.god = {waves = {}} end
M.on_configuration_changed = function() storage.god = storage.god or {waves = {}} end

local function point(p)
  if type(p) ~= "table" or not (p.x or p[1]) then sbx.fail("bad_args", "a position is {x, y}") end
  return {x = p.x or p[1], y = p.y or p[2]}
end

-- Generate the chunks within r chunks of p, so create_entity has ground to stand on.
local function ground(s, p, r)
  r = r or 1
  local d = r * 32
  for _, c in ipairs{{p.x - d, p.y - d}, {p.x + d, p.y - d}, {p.x - d, p.y + d}, {p.x + d, p.y + d}} do
    if not s.is_chunk_generated{math.floor(c[1] / 32), math.floor(c[2] / 32)} then
      s.request_to_generate_chunks(p, r)
      s.force_generate_chunk_requests()
      return
    end
  end
end

local function ledger_entity(name, e)
  sbx.ledger_add(name, {kind = "entity", entity = e, unit = e.unit_number, name = e.name, position = e.position})
end

local function reassert_diplomacy(f)
  if f.name == "player" then return end
  f.set_friend("player", true) game.forces.player.set_friend(f, true)
  f.set_cease_fire("player", true) game.forces.player.set_cease_fire(f, true)
end

local function copy_research(f)
  if f.name == "player" then return end
  f.copy_from(game.forces.player)
  reassert_diplomacy(f)
end

local function is_infinite(t) return t.prototype.max_level > INF_LEVEL end

local function snapshot(f)
  local s = {}
  for n, t in pairs(f.technologies) do s[n] = {researched = t.researched, level = t.level} end
  return s
end

local function count_researched(f)
  local n = 0
  for _, t in pairs(f.technologies) do if t.researched then n = n + 1 end end
  return n
end

local function recipe_states(f)
  local s = {}
  for n, r in pairs(f.recipes) do s[n] = r.enabled end
  return s
end

local function count_recipes(f)
  local n = 0
  for _, r in pairs(f.recipes) do if r.enabled then n = n + 1 end end
  return n
end

-- Research a tech and its prerequisites. An infinite tech counts its first level.
local function take(t)
  if is_infinite(t) then
    for _, p in pairs(t.prerequisites) do take(p) end
    if t.level <= t.prototype.level then t.level = t.prototype.level + 1 end
  elseif not t.researched then
    for _, p in pairs(t.prerequisites) do take(p) end
    t.researched = true
  end
end

local function tech_of(f, name)
  local t = f.technologies[name]
  if not t then sbx.fail("bad_args", "no technology " .. tostring(name)) end
  return t
end

-- research{name, mode = "copy" | "list" | "levels" | "all" | "none", techs, levels = {tech = N}, recipes}
R.research = function(a)
  local box = sbx.require_god(a.name)
  local f = sbx.force(box)
  local mode = a.mode or "copy"
  if box.inplace and (mode == "none" or mode == "all") then
    sbx.fail("bad_args", "research mode " .. mode .. " would rewrite the real " .. f.name .. " force; use list or levels")
  end
  local before, recipes_before = snapshot(f), recipe_states(f)
  if mode == "copy" then
    copy_research(f)
  elseif mode == "list" then
    for _, n in ipairs(a.techs or {}) do take(tech_of(f, n)) end
  elseif mode == "levels" then
    for n, lv in pairs(a.levels or {}) do
      local t = tech_of(f, n)
      for _, p in pairs(t.prerequisites) do take(p) end
      if is_infinite(t) then
        t.level = math.max(lv + 1, t.prototype.level)
      elseif lv >= 1 then
        t.researched = true
      end
    end
  elseif mode == "all" then
    f.research_all_technologies()
  elseif mode == "none" then
    for _, t in pairs(f.technologies) do
      t.researched = false
      if is_infinite(t) then t.level = t.prototype.level end
    end
    f.reset_technology_effects()
  else
    sbx.fail("bad_args", "research mode: copy, list, levels, all or none")
  end
  if a.recipes == "all" then
    f.enable_all_recipes()
  elseif type(a.recipes) == "table" then
    for _, n in ipairs(a.recipes) do
      local r = f.recipes[n]
      if not r then sbx.fail("bad_args", "no recipe " .. tostring(n)) end
      r.enabled = true
    end
  end
  -- Recipe entries go first: sbx_mode replays newest first, so the techs are undone before the recipes are restored.
  for n, r in pairs(f.recipes) do
    if recipes_before[n] ~= r.enabled then
      sbx.ledger_add(a.name, {kind = "research", recipe = n, before = recipes_before[n], after = r.enabled})
    end
  end
  local changed = {}
  for n, t in pairs(f.technologies) do
    local b = before[n]
    if b.researched ~= t.researched or b.level ~= t.level then
      changed[#changed + 1] = n
      sbx.ledger_add(a.name, {kind = "research", tech = n, before = b, after = {researched = t.researched, level = t.level}})
    end
  end
  table.sort(changed)
  return {changed = changed, count = #changed, researched = count_researched(f), recipes = count_recipes(f)}
end

-- bonuses{name}: every numeric bonus of the sandbox force, the researched tech count and the enabled recipe count.
R.bonuses = function(a)
  local f = sbx.force(sbx.get(a.name))
  local out = {}
  for _, k in ipairs(SCALARS) do
    local ok, v = pcall(function() return f[k] end)
    if ok and type(v) == "number" then out[k] = v end
  end
  for cat in pairs(prototypes.ammo_category) do
    out["ammo_damage:" .. cat] = f.get_ammo_damage_modifier(cat)
    out["gun_speed:" .. cat] = f.get_gun_speed_modifier(cat)
  end
  for n, p in pairs(prototypes.entity) do
    if TURRET_TYPES[p.type] then
      local ok, v = pcall(f.get_turret_attack_modifier, n)
      if ok then out["turret_attack:" .. n] = v end
    end
  end
  return {bonuses = out, researched = count_researched(f), recipes = count_recipes(f)}
end

local function check_stacks(items)
  if type(items) ~= "table" or #items == 0 then sbx.fail("bad_args", "items is a list of {name, count, quality}") end
  for _, it in ipairs(items) do
    if not (type(it.name) == "string" and prototypes.item[it.name]) then
      sbx.fail("bad_args", "no item " .. tostring(it.name))
    end
    it.count = it.count or 1
  end
end

-- An infinity chest has a unit number that get_entity_by_unit_number cannot find, so look in the ledger too.
local function entity_by_unit(name, unit)
  local e = unit and game.get_entity_by_unit_number(unit)
  if e then return e end
  for _, entry in ipairs(sbx.ledger(name)) do
    if entry.entity and entry.unit and entry.unit == unit and entry.entity.valid then return entry.entity end
  end
end

local function stack(it) return {name = it.name, count = it.count, quality = it.quality} end

local function insert_all(inv, items, totals)
  for _, it in ipairs(items) do
    local n = inv.insert(stack(it))
    totals[it.name] = (totals[it.name] or 0) + n
  end
end

-- Lay items along the belt line that starts at belt b: insert_at, because insert_at_back takes one item per tick.
local function fill_belt(b, items)
  local queue = {}
  for _, it in ipairs(items) do queue[#queue + 1] = {name = it.name, quality = it.quality, left = it.count} end
  local totals, seen, cur, qi = {}, {}, b, 1
  while cur and not seen[cur.unit_number] and qi <= #queue do
    seen[cur.unit_number] = true
    for lane = 1, 2 do
      local line = cur.get_transport_line(lane)
      local pos = 0
      while pos <= line.line_length and qi <= #queue do
        local q = queue[qi]
        if line.can_insert_at(pos) and line.insert_at(pos, {name = q.name, count = 1, quality = q.quality}) then
          totals[q.name] = (totals[q.name] or 0) + 1
          q.left = q.left - 1
          if q.left == 0 then qi = qi + 1 end
        end
        pos = pos + 0.25
      end
    end
    cur = cur.belt_neighbours.outputs[1]
  end
  return totals
end

-- items{name, at, items = {{name, count, quality}}, target = "chest" | "infinity" | "belt" | "entity" | "ground", entity}
R.items = function(a)
  local box = sbx.require_god(a.name)
  local s, f = sbx.surface(box), sbx.force(box)
  check_stacks(a.items)
  local target = a.target or "chest"
  local units, totals = {}, {}
  if target == "entity" then
    local e
    if type(a.entity) == "number" then
      e = entity_by_unit(a.name, a.entity)
    elseif type(a.entity) == "string" and a.at then
      -- turrets and chests are not found by unit number, so they are addressed by name and position
      e = s.find_entities_filtered{name = a.entity, position = point(a.at), radius = 0.5, limit = 1}[1]
    else
      sbx.fail("bad_args", "target entity needs entity, a unit number, or an entity name with at")
    end
    if not e then sbx.fail("not_found", "no entity " .. tostring(a.entity) .. (a.at and " at the given position" or "")) end
    insert_all(e, a.items, totals)
    return {units = {}, inserted = totals}
  end
  local at = point(a.at)
  ground(s, at)
  if target == "chest" or target == "infinity" then
    local proto = target == "chest" and "steel-chest" or "infinity-chest"
    local p = s.find_non_colliding_position(proto, at, 8, 1) or at
    local e = s.create_entity{name = proto, position = p, force = f}
    if not e then sbx.fail("bad_args", "cannot place " .. proto .. " at " .. p.x .. "," .. p.y) end
    ledger_entity(a.name, e)
    units[1] = e.unit_number
    if target == "chest" then
      insert_all(e, a.items, totals)
    else
      local filters = {}
      for i, it in ipairs(a.items) do
        filters[i] = {name = it.name, quality = it.quality, count = it.count, mode = "exactly", index = i}
        totals[it.name] = it.count
      end
      e.infinity_container_filters = filters
    end
    return {units = units, inserted = totals, position = e.position}
  elseif target == "belt" then
    local b = s.find_entities_filtered{position = at, radius = 0.5, type = {"transport-belt", "underground-belt", "splitter"}}[1]
    if not b then sbx.fail("not_found", "no belt at " .. at.x .. "," .. at.y) end
    return {units = {}, inserted = fill_belt(b, a.items)}
  elseif target == "ground" then
    for _, it in ipairs(a.items) do
      local spilled = s.spill_item_stack{position = at, stack = stack(it), enable_looted = true, allow_belts = false}
      for _, e in pairs(spilled or {}) do
        if e.valid then ledger_entity(a.name, e) end
      end
      totals[it.name] = it.count
    end
    return {units = {}, inserted = totals}
  end
  sbx.fail("bad_args", "items target: chest, infinity, belt, entity or ground")
end

local function set_evolution(name, box, value)
  local e = game.forces.enemy
  local s = sbx.surface(box)
  local before = e.get_evolution_factor(s)
  e.set_evolution_factor(value, s)
  local after = e.get_evolution_factor(s)
  sbx.ledger_add(name, {kind = "bonus", field = "evolution", surface = s.name, before = before, after = after})
  return after
end

-- evo{name, set}: the enemy evolution factor of the sandbox surface.
R.evo = function(a)
  local box = sbx.require_god(a.name)
  if type(a.set) ~= "number" or a.set < 0 or a.set > 1 then sbx.fail("bad_args", "set is a number from 0 to 1") end
  return {evo = set_evolution(a.name, box, a.set)}
end

-- nest{name, at, names, evo}: spawners and worms in a row, 8 tiles apart.
R.nest = function(a)
  local box = sbx.require_god(a.name)
  local s = sbx.surface(box)
  local at = point(a.at)
  if type(a.names) ~= "table" or #a.names == 0 then sbx.fail("bad_args", "names is a list of spawner and worm names") end
  ground(s, at, 2)
  local evo = a.evo and set_evolution(a.name, box, a.evo)
  local units, failed = {}, {}
  for i, n in ipairs(a.names) do
    if not prototypes.entity[n] then sbx.fail("bad_args", "no entity " .. tostring(n)) end
    local p = {x = at.x + (i - 1) * 8, y = at.y}
    local e = s.create_entity{name = n, position = s.find_non_colliding_position(n, p, 20, 1) or p, force = "enemy"}
    if e then
      ledger_entity(a.name, e)
      units[#units + 1] = e.unit_number
    else
      failed[#failed + 1] = n
    end
  end
  return {units = units, failed = failed, evo = evo or game.forces.enemy.get_evolution_factor(s)}
end

local STATES = {}
for k, v in pairs(defines.group_state) do STATES[v] = k end

-- wave{name, from, target, units = {name = count}, radius}: a unit group that attacks the area around target.
R.wave = function(a)
  local box = sbx.require_god(a.name)
  local s = sbx.surface(box)
  local from, target = point(a.from), point(a.target)
  if type(a.units) ~= "table" or next(a.units) == nil then sbx.fail("bad_args", "units is {name = count}") end
  ground(s, from, 2)
  ground(s, target, 2)
  local g = s.create_unit_group{position = from, force = "enemy"}
  local members = {}
  for n, c in pairs(a.units) do
    if not prototypes.entity[n] then sbx.fail("bad_args", "no entity " .. tostring(n)) end
    for _ = 1, c do
      local p = s.find_non_colliding_position(n, from, 30, 0.5)
      local u = p and s.create_entity{name = n, position = p, force = "enemy"}
      if u then
        g.add_member(u)
        ledger_entity(a.name, u)
        members[#members + 1] = u
      end
    end
  end
  g.set_command{type = defines.command.attack_area, destination = target, radius = a.radius or 16,
                distraction = defines.distraction.by_anything}
  local id = g.unique_id
  storage.god.waves[id] = {box = a.name, group = g, units = members, total = #members, tick = game.tick}
  return {group = id, members = #members}
end

-- wave_status{name, group}: how many of a wave's units live, and the state of its group.
R.wave_status = function(a)
  sbx.get(a.name)
  local w = storage.god.waves[a.group]
  if not w or w.box ~= a.name then sbx.fail("not_found", "no wave " .. tostring(a.group)) end
  local alive = 0
  for _, u in ipairs(w.units) do if u.valid then alive = alive + 1 end end
  local state = w.group.valid and STATES[w.group.state] or "dissolved"
  return {alive = alive, killed = w.total - alive, total = w.total, state = state, tick = game.tick}
end

-- body{name, at, reach = 1000, invulnerable = true}: a player-less character with script-given reach.
R.body = function(a)
  local box = sbx.require_god(a.name)
  local s = sbx.surface(box)
  local at = point(a.at)
  local reach = a.reach or 1000
  local invulnerable = a.invulnerable ~= false
  ground(s, at)
  local p = s.find_non_colliding_position("character", at, 10, 0.5) or at
  local c = s.create_entity{name = "character", position = p, force = sbx.force(box)}
  if not c then sbx.fail("bad_args", "cannot place a body at " .. at.x .. "," .. at.y) end
  local before = {destructible = c.destructible}
  for k, field in pairs(BODY_FIELDS) do
    before[k] = c[field]
    c[field] = reach
  end
  c.destructible = not invulnerable
  sbx.ledger_add(a.name, {kind = "body", entity = c, unit = c.unit_number, name = c.name, position = c.position, before = before})
  return {unit = c.unit_number, position = c.position}
end

-- body_tp{name, at, surface, unit}: move a body, by default the newest one, to a position on a surface.
-- A character without a player cannot teleport across surfaces, so it is cloned there and the old one destroyed.
R.body_tp = function(a)
  local box = sbx.require_god(a.name)
  local at = point(a.at)
  local s = a.surface and game.surfaces[a.surface] or sbx.surface(box)
  if not s then sbx.fail("not_found", "no surface " .. tostring(a.surface)) end
  local entry
  for _, e in ipairs(sbx.ledger(a.name)) do
    if e.kind == "body" and e.entity.valid and (not a.unit or e.unit == a.unit) then entry = e end
  end
  if not entry then sbx.fail("not_found", "no body") end
  local body = entry.entity
  ground(s, at)
  if body.surface.index == s.index then
    if not body.teleport(at, s) then sbx.fail("bad_args", "cannot teleport the body to " .. at.x .. "," .. at.y) end
    return {teleported = true, unit = body.unit_number, position = body.position}
  end
  local p = s.find_non_colliding_position("character", at, 10, 0.5) or at
  local new = body.clone{position = p, surface = s, force = body.force}
  if not new then sbx.fail("bad_args", "cannot clone the body to " .. s.name .. " at " .. p.x .. "," .. p.y) end
  for _, field in pairs(BODY_FIELDS) do new[field] = body[field] end
  new.destructible = body.destructible
  local old = body.unit_number
  body.destroy()
  entry.entity, entry.unit, entry.position = new, new.unit_number, new.position
  return {teleported = true, unit = new.unit_number, old_unit = old, position = new.position}
end

local function restore_research(f, e)
  if e.recipe then
    f.recipes[e.recipe].enabled = e.before
    return
  end
  local t = f.technologies[e.tech]
  t.researched = e.before.researched
  if is_infinite(t) then t.level = e.before.level end
end

-- sbx_mode{name, mode = "standard" | "god", research = "copy" | "keep", power = "keep" | "cut"}
-- power = "keep" leaves the slice's energy interface in place: it stands for the grid the slice was cut from.
R.sbx_mode = function(a)
  local box = sbx.get(a.name)
  if a.mode == "god" then
    box.mode = "god"
    sbx.free_humans()
    return {mode = "god"}
  elseif a.mode ~= "standard" then
    sbx.fail("bad_args", "mode is standard or god")
  end
  if a.power ~= nil and a.power ~= "keep" and a.power ~= "cut" then sbx.fail("bad_args", "power is keep or cut") end
  local cut_power = a.power == "cut"
  local f = sbx.force(box)
  local keep = a.research == "keep"
  -- A box on the player force has no copy to fall back on, so its research is replayed from the ledger.
  local replay = f.name == "player"
  local skip_research = keep and not replay
  local list = sbx.ledger(a.name)
  local undone, skipped, researched = 0, 0, 0
  for i = #list, 1, -1 do
    local e = list[i]
    if not e.undone and not (skip_research and e.kind == "research") and not (e.power and not cut_power) then
      if e.kind == "entity" then
        if e.entity.valid then e.entity.destroy() else skipped = skipped + 1 end
      elseif e.kind == "body" then
        if e.entity.valid then
          for k, field in pairs(BODY_FIELDS) do e.entity[field] = e.before[k] or 0 end
          e.entity.destructible = e.before.destructible
        else
          skipped = skipped + 1
        end
      elseif e.kind == "bonus" then
        if e.field == "evolution" then
          local s = game.surfaces[e.surface]
          if s then game.forces.enemy.set_evolution_factor(e.before, s) end
        else
          f[e.field] = e.before
        end
      elseif e.kind == "research" then
        researched = researched + 1
        if replay then restore_research(f, e) end
      end
      e.undone = true
      undone = undone + 1
    end
  end
  if not keep then copy_research(f) end
  -- a slice powers itself through a global network in god mode; standard rules run on its own generators
  if cut_power and not box.inplace then sbx.surface(box).destroy_global_electric_network() end
  box.mode, box.power = "standard", cut_power and "cut" or "keep"
  sbx.free_humans()
  return {mode = "standard", undone = undone, skipped = skipped, research_entries = researched}
end

-- ledger{name}: the entries as plain data. An entity entry keeps the unit number, name and position it had when recorded.
R.ledger = function(a)
  local out = {}
  for _, e in ipairs(sbx.ledger(sbx.get(a.name).name)) do
    local row = {kind = e.kind, tick = e.tick, undone = e.undone or false, field = e.field, tech = e.tech,
                 before = e.before, after = e.after, surface = e.surface, recipe = e.recipe}
    if e.entity then
      local v = e.entity.valid
      row.valid = v
      row.unit = v and e.entity.unit_number or e.unit
      row.name = v and e.entity.name or e.name
      row.position = v and e.entity.position or e.position
    end
    out[#out + 1] = row
  end
  return {entries = out, count = #out}
end

return M
