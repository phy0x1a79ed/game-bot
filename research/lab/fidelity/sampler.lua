-- Counts, every 61 ticks, how many machines of each recipe have the status working. A prime interval cannot lock
-- onto an inserter or crafting cycle. Needs no RCON call per sample.
-- fid.sample_start({{key, surface, area}, ...}) begins; fid.sample_stop() returns {key = {recipe = {n, working}}}.
-- A machine counts when its centre lies inside the rectangle, as in measure.lua.

fid = fid or {}

function fid.sample_start(queries)
  fid.sampling = {queries = queries, counts = {}}
  for _, q in ipairs(queries) do fid.sampling.counts[q[1]] = {} end
end

function fid.sample_stop()
  local counts = fid.sampling and fid.sampling.counts or {}
  fid.sampling = nil
  return counts
end

script.on_nth_tick(61, function()
  local s = fid.sampling
  if not s then return end
  for _, q in ipairs(s.queries) do
    local a, counts = q[3], s.counts[q[1]]
    for _, e in pairs(game.surfaces[q[2]].find_entities_filtered{area = a, type = {"assembling-machine", "furnace", "rocket-silo"}}) do
      local p = e.position
      local recipe = e.get_recipe()
      if not recipe and e.type == "furnace" then recipe = e.previous_recipe end
      if recipe and p.x >= a[1][1] and p.x < a[2][1] and p.y >= a[1][2] and p.y < a[2][2] then
        local name = type(recipe.name) == "string" and recipe.name or recipe.name.name
        local c = counts[name] or {n = 0, working = 0}
        counts[name] = c
        c.n = c.n + 1
        if e.status == defines.entity_status.working then c.working = c.working + 1 end
      end
    end
  end
end)
rcon.print("ok")
