--- tool: configure
--- kind: call
--- effect: act
--- summary: set machine and entity settings (recipe, inserter filters, chest bar, splitter priority and filter, direction, modules) on built entities or ghosts, all or nothing
--- args: list (up to 100 entries {position = {x, y}, name (optional, picks among overlaps), recipe (false clears), filters (a list of item names, {} clears), filter_mode (whitelist|blacklist), bar (a slot number, false clears), priority = {input, output} (none|left|right), filter (an item name for a splitter, false clears), direction (north|east|south|west), modules (a list of module names)}); surface (default nauvis); force (default player)
--- returns: {ok, done = {{i, name, x, y, ghost, changed = {setting = new value}}}, issues = {{i, code, msg}}, summary} or {error, hint}
--- uses: rd
-- Each target is the entity covering the exact tile, never the nearest. An integer position means the tile whose top-left corner it is.
-- Every entry is checked first; one issue changes nothing. A change the engine then refuses rolls the earlier ones back.
-- Modules fill free slots through an item request, so the entity gets them from the logistic network, as a player's request would.
local rd = use("rd")
local a = ...
local MAX_ENTRIES = 100

local c, err = rd.ctx(a, {bare = true, extra = {"list"}})
if not c then return err end
local list = a.list
if type(list) ~= "table" or #list == 0 or next(list, #list) ~= nil then
  return rd.fail("list must be a non-empty array of entries", "each entry is {position = {x, y}, recipe = \"iron-gear-wheel\"}")
end
if #list > MAX_ENTRIES then return rd.fail(#list .. " entries is too many", "send at most " .. MAX_ENTRIES .. " per call, in several calls") end

local KNOWN = {position = true, name = true, recipe = true, filters = true, filter_mode = true, bar = true,
  priority = true, filter = true, direction = true, modules = true}
local SETTINGS = {"recipe", "direction", "filters", "filter_mode", "bar", "priority", "filter", "modules"}
local KNOWN_LIST = {}
for k in pairs(KNOWN) do KNOWN_LIST[#KNOWN_LIST + 1] = k end
table.sort(KNOWN_LIST)

local D = defines.direction
local DIRECTIONS = {north = D.north, east = D.east, south = D.south, west = D.west}
local PRIORITIES = {none = true, left = true, right = true}
local FILTER_MODES = {whitelist = true, blacklist = true}
local I = defines.inventory
local MODULE_INVENTORY = {
  ["assembling-machine"] = I.crafter_modules, ["furnace"] = I.crafter_modules, ["rocket-silo"] = I.crafter_modules,
  ["lab"] = I.lab_modules, ["mining-drill"] = I.mining_drill_modules, ["beacon"] = I.beacon_modules,
  ["agricultural-tower"] = I.agricultural_tower_modules,
}
local SKIP = {["entity-ghost"] = false, ["item-request-proxy"] = true, ["tile-ghost"] = true, ["item-entity"] = true,
  ["character"] = true, ["corpse"] = true, ["resource"] = true, ["cliff"] = true}

-- shape errors name the entry and stop the call
for i, raw in ipairs(list) do
  if type(raw) ~= "table" then return rd.fail("entry " .. i .. " is not a table", "each entry is {position = {x, y}, ...settings}") end
  for k in pairs(raw) do
    if not KNOWN[k] then
      return rd.fail("entry " .. i .. " has an unknown key '" .. tostring(k) .. "'",
        "accepted: " .. table.concat(KNOWN_LIST, ", ") .. "; clear a setting with false or {}, not nil")
    end
  end
  local p = raw.position
  local x, y
  if type(p) == "table" then x, y = p[1] or p.x, p[2] or p.y end
  if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then
    return rd.fail("entry " .. i .. " needs position = {x, y}", "numbers; an integer means the tile whose top-left corner it is")
  end
  if raw.name ~= nil and type(raw.name) ~= "string" then return rd.fail("entry " .. i .. " has a non-text name", "name is an entity name such as assembling-machine-2") end
end

local function centre(v) return v == math.floor(v) and v + 0.5 or v end
local function name_of(e) return e.type == "entity-ghost" and e.ghost_name or e.name end
local function type_of(e) return e.type == "entity-ghost" and e.ghost_type or e.type end

local function target(raw)
  local x, y = raw.position[1] or raw.position.x, raw.position[2] or raw.position.y
  local hits = {}
  for _, e in pairs(c.s.find_entities_filtered{position = {centre(x), centre(y)}, force = c.force}) do
    if not SKIP[e.type] and (raw.name == nil or name_of(e) == raw.name) then hits[#hits + 1] = e end
  end
  if #hits == 0 then
    return nil, "NO_ENTITY", string.format("nothing%s at (%s, %s)", raw.name and (" named " .. raw.name) or "", centre(x), centre(y))
  end
  if #hits > 1 then
    local names = {}
    for _, e in ipairs(hits) do names[#names + 1] = name_of(e) .. (e.type == "entity-ghost" and " (ghost)" or "") end
    table.sort(names)
    return nil, "AMBIGUOUS", "several entities cover that tile: " .. table.concat(names, ", ") .. "; pass name"
  end
  return hits[1]
end

local function item_exists(n) return type(n) == "string" and prototypes.item[n] ~= nil end

local function plan_slots(plan, inventory)
  local slots = {}
  for _, entry in ipairs(plan or {}) do
    local name = entry.id and entry.id.name
    for _, s in ipairs(entry.items and entry.items.in_inventory or {}) do
      if s.inventory == inventory then slots[s.stack] = name end
    end
  end
  return slots
end

-- Each op: key, new (the value reported in changed), apply(), undo(), ok() (read back after apply)
local function plan_entry(i, raw, e, add, issue)
  local ghost = e.type == "entity-ghost"
  local name, kind = name_of(e), type_of(e)
  local proto = prototypes.entity[name]
  local function has(k) return raw[k] ~= nil end

  if has("direction") then
    local d = DIRECTIONS[raw.direction]
    if not d then
      issue(i, "BAD_VALUE", "direction must be north, east, south or west")
    elseif not proto.supports_direction then
      issue(i, "NO_SETTING", name .. " has no direction to set")
    elseif e.direction ~= d then
      local old = e.direction
      -- a splitter cannot turn in place with the setter, so rotate it as a player would
      local function turn(to)
        pcall(function() e.direction = to end)
        for _ = 1, 3 do
          if e.direction == to then return end
          e.rotate{}
        end
      end
      add{key = "direction", new = raw.direction, apply = function() turn(d) end,
        undo = function() turn(old) end, ok = function() return e.direction == d end}
    end
  end

  if has("recipe") then
    local want = raw.recipe
    if want == "" then want = false end
    if kind ~= "assembling-machine" then
      issue(i, "NO_SETTING", kind == "furnace" and (name .. " picks its recipe from its input")
        or (name .. " has no recipe to set"))
    elseif proto.fixed_recipe then
      issue(i, "NO_SETTING", name .. " has a fixed recipe (" .. proto.fixed_recipe .. ")")
    elseif want ~= false and type(want) ~= "string" then
      issue(i, "BAD_VALUE", "recipe is a recipe name, or false to clear")
    else
      local rec = want and c.f.recipes[want]
      if want and not rec then
        local _, e2 = rd.nameset(want, "recipe", "recipe")
        issue(i, "UNKNOWN_RECIPE", "no recipe named '" .. want .. "'" .. (e2 and e2.hint and ("; " .. e2.hint) or ""))
      elseif want and not rec.enabled then
        issue(i, "NOT_UNLOCKED", "recipe " .. want .. " is not unlocked for force " .. c.force)
      else
        local craftable = not want
        if want then
          for _, cat in ipairs(rec.prototype.categories or {rec.prototype.category}) do
            if proto.crafting_categories and proto.crafting_categories[cat] then craftable = true end
          end
        end
        if not craftable then
          issue(i, "CANNOT_CRAFT", name .. " cannot craft " .. want .. " (category " .. table.concat(rec.prototype.categories or {"?"}, "/") .. ")")
        else
          local cur = e.get_recipe()
          if (cur and cur.name or false) ~= want then
            local old = cur and cur.name or nil
            add{key = "recipe", new = want, apply = function() e.set_recipe(want or nil) end,
              undo = function() e.set_recipe(old) end,
              ok = function() local r = e.get_recipe() return (r and r.name or false) == want end}
          end
        end
      end
    end
  end

  if has("filters") or has("filter_mode") then
    local slots = kind ~= "inserter" and 0 or ghost and (proto.filter_count or 0) or (e.filter_slot_count or 0)
    if kind ~= "inserter" or slots == 0 then
      issue(i, "NO_SETTING", name .. " has no item filters")
    else
      if has("filters") then
        local f = raw.filters
        local bad = type(f) ~= "table"
        for k, v in pairs(bad and {} or f) do
          if type(k) ~= "number" or not item_exists(v) then bad = true end
        end
        if bad then
          issue(i, "BAD_VALUE", "filters is a list of item names, such as {\"iron-plate\"}")
        elseif #f > slots then
          issue(i, "TOO_MANY", name .. " has " .. slots .. " filter slots, " .. #f .. " given")
        else
          local old, differs = {}, false
          for s = 1, slots do
            local cur = e.get_filter(s)
            old[s] = cur and cur.name or nil
            if old[s] ~= f[s] then differs = true end
          end
          if differs then
            add{key = "filters", new = f, apply = function() for s = 1, slots do e.set_filter(s, f[s]) end end,
              undo = function() for s = 1, slots do e.set_filter(s, old[s]) end end,
              ok = function() for s = 1, slots do local cur = e.get_filter(s) if (cur and cur.name or nil) ~= f[s] then return false end end return true end}
          end
        end
      end
      if has("filter_mode") then
        if not FILTER_MODES[raw.filter_mode] then
          issue(i, "BAD_VALUE", "filter_mode is whitelist or blacklist")
        elseif e.inserter_filter_mode ~= raw.filter_mode then
          local old, want = e.inserter_filter_mode, raw.filter_mode
          add{key = "filter_mode", new = want, apply = function() e.inserter_filter_mode = want end,
            undo = function() e.inserter_filter_mode = old end, ok = function() return e.inserter_filter_mode == want end}
        end
      end
    end
  end

  if has("bar") then
    local inv = not ghost and e.get_inventory(I.chest)
    if ghost then
      issue(i, "GHOST_UNSUPPORTED", "a ghost has no inventory to bar; set bar once " .. name .. " is built")
    elseif not inv then
      issue(i, "NO_SETTING", name .. " has no bar")
    else
      local want = raw.bar
      if want ~= false and (type(want) ~= "number" or want ~= math.floor(want) or want < 1 or want > #inv) then
        issue(i, "BAD_VALUE", "bar is a slot number from 1 to " .. #inv .. " (slots from it on are blocked), or false to clear")
      else
        local target_bar = want == false and #inv + 1 or want
        local old = inv.get_bar()
        if old ~= target_bar then
          add{key = "bar", new = want, apply = function() if want then inv.set_bar(want) else inv.set_bar() end end,
            undo = function() if old > #inv then inv.set_bar() else inv.set_bar(old) end end,
            ok = function() return inv.get_bar() == target_bar end}
        end
      end
    end
  end

  if has("priority") or has("filter") then
    if kind ~= "splitter" then
      issue(i, "NO_SETTING", name .. " is not a splitter")
    else
      if has("priority") then
        local p = raw.priority
        local bad = type(p) ~= "table"
        for k, v in pairs(bad and {} or p) do
          if (k ~= "input" and k ~= "output") or not PRIORITIES[v] then bad = true end
        end
        if bad then
          issue(i, "BAD_VALUE", "priority is {input = ..., output = ...} with none, left or right")
        else
          for _, side in ipairs{"input", "output"} do
            local want = p[side]
            local field = "splitter_" .. side .. "_priority"
            if want and e[field] ~= want then
              local old = e[field]
              add{key = "priority_" .. side, new = want, apply = function() e[field] = want end,
                undo = function() e[field] = old end, ok = function() return e[field] == want end}
            end
          end
        end
      end
      if has("filter") then
        local want = raw.filter
        if want ~= false and not item_exists(want) then
          issue(i, "BAD_VALUE", "filter is an item name, or false to clear")
        else
          local cur = e.splitter_filter
          if (cur and cur.name or false) ~= want then
            local old = cur and cur.name or nil
            add{key = "filter", new = want, apply = function() e.splitter_filter = want or nil end,
              undo = function() e.splitter_filter = old end,
              ok = function() local f = e.splitter_filter return (f and f.name or false) == want end}
          end
        end
      end
    end
  end

  if has("modules") then
    local inventory = MODULE_INVENTORY[kind]
    local size = proto.module_inventory_size or 0
    local mods = raw.modules
    local bad = type(mods) ~= "table"
    for k, v in pairs(bad and {} or mods) do
      if type(k) ~= "number" or type(v) ~= "string" then bad = true end
    end
    if not inventory or size == 0 then
      issue(i, "NO_SETTING", name .. " has no module slots")
    elseif bad then
      issue(i, "BAD_VALUE", "modules is a list of module item names, such as {\"speed-module\"}")
    else
      local recipe = kind == "assembling-machine" and e.get_recipe() or nil
      local fine = true
      for _, m in ipairs(mods) do
        local item = prototypes.item[m]
        if not item or item.type ~= "module" then
          issue(i, "NOT_A_MODULE", "'" .. m .. "' is not a module item")
          fine = false
        else
          local cats = proto.allowed_module_categories
          if cats and not cats[item.category] then
            issue(i, "MODULE_NOT_ALLOWED", name .. " takes no " .. item.category .. " modules")
            fine = false
          end
          for effect, v in pairs(item.module_effects or {}) do
            if v ~= 0 and proto.allowed_effects and proto.allowed_effects[effect] == false then
              issue(i, "MODULE_NOT_ALLOWED", name .. " allows no " .. effect .. " effect, which " .. m .. " has")
              fine = false
            end
          end
          if recipe and (item.module_effects or {}).productivity and item.module_effects.productivity > 0
              and prototypes.recipe[recipe.name].allowed_effects and not prototypes.recipe[recipe.name].allowed_effects.productivity then
            issue(i, "MODULE_NOT_ALLOWED", "recipe " .. recipe.name .. " takes no productivity")
            fine = false
          end
        end
      end
      if fine then
        local old_plan = ghost and e.insert_plan or (e.item_request_proxy and e.item_request_proxy.insert_plan) or {}
        local taken = plan_slots(old_plan, inventory)
        if not ghost then
          local inv = e.get_inventory(inventory)
          for s = 1, #inv do if inv[s].valid_for_read then taken[s - 1] = inv[s].name end end
        end
        local have = {}
        for _, n in pairs(taken) do have[n] = (have[n] or 0) + 1 end
        local need, free = {}, {}
        for s = 0, size - 1 do if not taken[s] then free[#free + 1] = s end end
        for _, m in ipairs(mods) do
          if (have[m] or 0) > 0 then have[m] = have[m] - 1 else need[#need + 1] = m end
        end
        if #need > #free then
          issue(i, "MODULE_SLOTS", string.format("%s has %d free module slots, %d more modules needed", name, #free, #need))
        elseif #need > 0 then
          local added = {}
          local plan = {}
          for _, p in ipairs(old_plan) do plan[#plan + 1] = p end
          for k, m in ipairs(need) do
            local g = added[m]
            if not g then
              g = {id = {name = m}, items = {in_inventory = {}}}
              added[m] = g
              plan[#plan + 1] = g
            end
            g.items.in_inventory[#g.items.in_inventory + 1] = {inventory = inventory, stack = free[k]}
          end
          local function has_all()
            local now = plan_slots(ghost and e.insert_plan or (e.item_request_proxy and e.item_request_proxy.insert_plan), inventory)
            for k = 1, #need do if now[free[k]] ~= need[k] then return false end end
            return true
          end
          local function put(p)
            if ghost then e.insert_plan = p return end
            if e.item_request_proxy then e.item_request_proxy.destroy() end
            if #p > 0 then
              assert(c.s.create_entity{name = "item-request-proxy", position = e.position, force = e.force, target = e, modules = p},
                "the engine made no item request")
            end
          end
          add{key = "modules", new = need, apply = function() put(plan) end, undo = function() put(old_plan) end, ok = has_all}
        end
      end
    end
  end
end

local issues, ops, done = {}, {}, {}
local function issue(i, code, msg) issues[#issues + 1] = {i = i, code = code, msg = msg} end

for i, raw in ipairs(list) do
  local e, code, msg = target(raw)
  if not e then
    issue(i, code, msg)
  else
    local mine = {}
    local ok, why = pcall(plan_entry, i, raw, e, function(op) mine[#mine + 1] = op end, issue)
    if not ok then issue(i, "CHECK_FAILED", tostring(why):sub(1, 200)) end
    local record = {e = e, i = i, name = name_of(e), x = rd.r2(e.position.x), y = rd.r2(e.position.y), changed = {}}
    if e.type == "entity-ghost" then record.ghost = true end
    done[#done + 1] = record
    ops[i] = mine
  end
end

if #issues > 0 then
  return {ok = false, done = {}, issues = issues, summary = "nothing changed: " .. #issues .. " issue" .. (#issues == 1 and "" or "s")}
end

local applied, count = {}, 0
local function rollback()
  for k = #applied, 1, -1 do pcall(applied[k].undo) end
end
for _, record in ipairs(done) do
  for _, op in ipairs(ops[record.i]) do
    local ok, why = pcall(op.apply)
    applied[#applied + 1] = op
    if not ok or not op.ok() then
      rollback()
      return {ok = false, done = {}, summary = "nothing changed: the engine refused entry " .. record.i,
        issues = {{i = record.i, code = "ENGINE_REFUSED", msg = op.key .. ": " .. (ok and "the engine kept the old value" or tostring(why):sub(1, 160))}}}
    end
    local key = op.key
    record.changed[key] = op.new
    record.x, record.y = rd.r2(record.e.position.x), rd.r2(record.e.position.y)
    count = count + 1
  end
end
for _, r in ipairs(done) do r.e = nil end
return {ok = true, done = done, issues = {}, summary = string.format("%d settings changed on %d of %d entities", count, (function()
  local n = 0
  for _, r in ipairs(done) do if next(r.changed) then n = n + 1 end end
  return n
end)(), #done)}
