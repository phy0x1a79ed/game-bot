--- tool: tech
--- kind: call
--- effect: act
--- summary: read the research state (current, progress, queue), find the technologies that unlock an item or recipe with what each still needs, and set the research queue
--- args: item (a name or list); recipe (a name or list); queue (a list of technology names); mode (replace|append, default replace); prerequisites (default true: queue the unresearched prerequisites first); force (default player)
--- returns: {current = {name, progress, level}, queue = {names}, researched, unlocks = {{recipe, item, unlocked, techs = {{tech, state, needs = {names in research order}, trigger}}}}, set = {queued, added}, total, more} or {error, hint}
-- state is researched | available (every prerequisite researched) | locked. A trigger technology (one a player earns by an action)
-- cannot be queued, and needs lists it so the crew knows to do the action. The queue is set only through force.research_queue, as a player queues.
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {bare = true, extra = {"item", "recipe", "queue", "mode", "prerequisites"}})
if not c then return err end
local f = c.f
local T = f.technologies
local MAX_QUEUE, MAX_NEEDS, MAX_RECIPES = 50, 30, 12

local function names_of(v, kind, field)
  if v == nil then return nil end
  local set, list = rd.nameset(v, kind, field)
  if not set then return nil, list end
  return list
end

local items, e1 = names_of(a.item, "item", "item")
if e1 then return e1 end
local recipes, e2 = names_of(a.recipe, "recipe", "recipe")
if e2 then return e2 end

local mode = a.mode or "replace"
if mode ~= "replace" and mode ~= "append" then return rd.fail("mode must be replace or append", "got " .. tostring(a.mode)) end
if a.prerequisites ~= nil and type(a.prerequisites) ~= "boolean" then return rd.fail("prerequisites must be true or false") end
local with_prereqs = a.prerequisites ~= false

local function state_of(t)
  if t.researched then return "researched" end
  for _, p in pairs(t.prerequisites) do
    if not p.researched then return "locked" end
  end
  return "available"
end

local function is_trigger(t) return t.prototype.research_trigger ~= nil end

local function trigger_text(t)
  local tr = t.prototype.research_trigger
  local what = tr.item and tr.item.name or tr.entity and tr.entity.name or tr.fluid or tr.technology or ""
  return string.format("%s%s%s", tr.type, tr.count and (" " .. tr.count) or "", what ~= "" and (" " .. what) or "")
end

-- the unresearched technologies that must be researched for t, t last, prerequisites first
local function needs_of(t)
  local out, seen = {}, {}
  local function visit(x)
    if seen[x.name] or x.researched then return end
    seen[x.name] = true
    local pre = {}
    for _, p in pairs(x.prerequisites) do pre[#pre + 1] = p.name end
    table.sort(pre)
    for _, n in ipairs(pre) do visit(T[n]) end
    out[#out + 1] = x.name
  end
  visit(t)
  return out
end

local function queue_names()
  local out = {}
  for _, t in ipairs(f.research_queue or {}) do out[#out + 1] = t.name end
  return out
end

local res = {}

if a.queue ~= nil then
  local q = a.queue
  if type(q) ~= "table" or (#q == 0 and next(q) ~= nil) then
    return rd.fail("queue must be a list of technology names", "for example queue = {\"advanced-electronics\"}; an empty list clears the queue")
  end
  for _, n in ipairs(q) do
    local t = type(n) == "string" and T[n]
    if not t then
      local hits = {}
      for tn in pairs(prototypes.technology) do
        if type(n) == "string" and (tn:find(n, 1, true) or n:find(tn, 1, true)) then hits[#hits + 1] = tn end
      end
      table.sort(hits)
      while #hits > 5 do hits[#hits] = nil end
      return rd.fail("no technology named '" .. tostring(n) .. "'", #hits > 0 and ("similar: " .. table.concat(hits, ", ")) or "technology names are such as 'automation-2'")
    end
    if not t.enabled then return rd.fail("technology " .. n .. " is disabled", "it cannot be researched") end
    if is_trigger(t) and not t.researched then
      return rd.fail("technology " .. n .. " is earned by an action, not by research: " .. trigger_text(t), "do that, then queue it")
    end
  end

  local want, seen = {}, {}
  if mode == "append" then
    for _, n in ipairs(queue_names()) do want[#want + 1] = n seen[n] = true end
  end
  local skipped = {}
  for _, n in ipairs(q) do
    local t = T[n]
    if t.researched then
      skipped[#skipped + 1] = n
    else
      for _, m in ipairs(with_prereqs and needs_of(t) or {n}) do
        local mt = T[m]
        if is_trigger(mt) then
          return rd.fail("technology " .. n .. " needs " .. m .. ", which is earned by an action: " .. trigger_text(mt), "do that first, then queue " .. n)
        end
        if not seen[m] then seen[m] = true want[#want + 1] = m end
      end
    end
  end
  if #want > MAX_QUEUE then return rd.fail(#want .. " technologies is too many to queue", "queue at most " .. MAX_QUEUE) end
  local before = queue_names()
  f.research_queue = want
  local after = queue_names()
  -- the engine keeps only the first few entries of a long queue (7 in the labs), so a shorter prefix is a good answer
  local ok = #after > 0 or #want == 0
  for i, n in ipairs(after) do if want[i] ~= n then ok = false end end
  if not ok then
    f.research_queue = before
    return rd.fail("the engine did not take that queue", "asked for " .. table.concat(want, ", ") .. "; the engine kept " .. table.concat(after, ", ") .. "; a technology whose prerequisites are not queued or researched is dropped (prerequisites = true queues them)")
  end
  local added, was = {}, {}
  for _, n in ipairs(before) do was[n] = true end
  for _, n in ipairs(after) do if not was[n] then added[#added + 1] = n end end
  res.set = {queued = after, added = added, skipped = #skipped > 0 and skipped or nil}
  if #after < #want then
    local rest = {}
    for i = #after + 1, #want do rest[#rest + 1] = want[i] end
    res.set.not_queued = rest
  end
end

local cur = f.current_research
if cur then
  res.current = {name = cur.name, progress = rd.r2(f.research_progress or 0), level = cur.level}
end
res.queue = queue_names()
local researched = 0
for _, t in pairs(T) do if t.researched then researched = researched + 1 end end
res.researched = researched

local wanted = {}
for _, r in ipairs(recipes or {}) do wanted[r] = {recipe = r} end
for _, it in ipairs(items or {}) do
  for rn, rp in pairs(prototypes.recipe) do
    local recycling = false
    for _, cat in ipairs(rp.categories or {}) do if cat == "recycling" then recycling = true end end
    for _, p in ipairs(recycling and {} or rp.products) do
      if p.name == it and (p.type == "item" or p.type == "fluid") then
        wanted[rn] = wanted[rn] or {recipe = rn}
        wanted[rn].item = it
      end
    end
  end
end

if next(wanted) then
  local sorted = {}
  for rn in pairs(wanted) do sorted[#sorted + 1] = rn end
  table.sort(sorted)
  local unlockers = {}
  for tn, tp in pairs(prototypes.technology) do
    for _, ef in ipairs(tp.effects) do
      if ef.type == "unlock-recipe" and wanted[ef.recipe] then
        local l = unlockers[ef.recipe]
        if not l then l = {} unlockers[ef.recipe] = l end
        l[#l + 1] = tn
      end
    end
  end
  local out = {}
  res.total = #sorted
  for i, rn in ipairs(sorted) do
    if i > MAX_RECIPES then res.more = true break end
    local entry = wanted[rn]
    entry.unlocked = f.recipes[rn].enabled
    entry.techs = {}
    local names = unlockers[rn] or {}
    table.sort(names)
    for _, tn in ipairs(names) do
      local t = T[tn]
      local needs = needs_of(t)
      local trimmed = {}
      for k = 1, math.min(#needs, MAX_NEEDS) do trimmed[k] = needs[k] end
      entry.techs[#entry.techs + 1] = {tech = tn, state = state_of(t), needs = trimmed, trigger = is_trigger(t) and trigger_text(t) or nil}
    end
    out[#out + 1] = entry
  end
  res.unlocks = out
end

return res
