--- tool: fluid
--- kind: call
--- effect: read
--- summary: fluid segments (connected pipe systems) that touch an area: fluid, amount, capacity and the entities on each
--- args: x0, y0, x1, y1 (numbers); fluid (a fluid name or a list: only these); limit (segments, default 200, max 300), offset; surface, force (default player)
--- returns: {segments = {{id, fluid, temperature, amount, capacity, fill, x0, y0, x1, y1, partial, n, entities = {name = n}, ends = {{name, x, y, recipe}}}, ...}, total, more, next}; the box is the whole segment, partial = true when it reaches outside the area, n and entities count what is inside the area, ends are the machines, tanks and pumps (up to 8), fluid is absent for an empty segment; {error, hint} on bad args
--- uses: rd
local rd = use("rd")
local a = ...
local c, err = rd.ctx(a, {area = true, paged = true, extra = {"fluid"}})
if not c then return err end

local want
if a.fluid ~= nil then
  local set, list = rd.nameset(a.fluid, "fluid", "fluid")
  if not set then return list end
  want = set
end

local list = {"pipe", "pipe-to-ground", "storage-tank", "pump", "offshore-pump", "boiler", "generator",
  "assembling-machine", "furnace", "mining-drill", "fluid-turret", "fluid-wagon", "valve", "reactor"}

local PLUMBING = {pipe = true, ["pipe-to-ground"] = true}
local segments, order = {}, {}
local members, cut = rd.find(c, {types = list, ghosts = false, unsorted = true})
if not members then return cut end
for _, e in ipairs(members) do
  for i = 1, e.fluids_count do
    if e.has_fluid_segment(i) then
      local id = e.get_fluid_segment_id(i)
      local seg = segments[id]
      if not seg then
        local f = e.get_fluid_segment_fluid(i)
        local capacity = e.get_fluid_segment_capacity(i)
        local box = e.get_fluid_segment_extent_bounding_box(i)
        seg = {id = id, fluid = f and f.name, temperature = f and rd.r2(f.temperature), amount = f and rd.r2(f.amount) or 0,
          capacity = rd.r2(capacity), fill = capacity > 0 and rd.r2((f and f.amount or 0) / capacity) or 0,
          x0 = math.floor(box.left_top.x), y0 = math.floor(box.left_top.y),
          x1 = math.ceil(box.right_bottom.x), y1 = math.ceil(box.right_bottom.y), n = 0, entities = {}, ends = {}}
        seg.partial = (seg.x0 < c.x0 or seg.y0 < c.y0 or seg.x1 > c.x1 or seg.y1 > c.y1) or nil
        segments[id] = seg
        order[#order + 1] = seg
      end
      seg.n = seg.n + 1
      seg.entities[e.name] = (seg.entities[e.name] or 0) + 1
      if not PLUMBING[e.type] then
        if #seg.ends < 8 then
          local r = {name = e.name, x = rd.r2(e.position.x), y = rd.r2(e.position.y)}
          if e.type == "assembling-machine" then
            local recipe = e.get_recipe()
            if recipe then r.recipe = recipe.name end
          end
          seg.ends[#seg.ends + 1] = r
        else
          seg.ends_more = true
        end
      end
    end
  end
end

local kept = {}
for _, seg in ipairs(order) do
  if not want or (seg.fluid and want[seg.fluid]) then kept[#kept + 1] = seg end
end
table.sort(kept, function(p, q)
  if p.capacity ~= q.capacity then return p.capacity > q.capacity end
  return p.id < q.id
end)
return rd.page({}, "segments", kept, c)
