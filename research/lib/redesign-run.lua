-- redesign-run.lua: shared runner appended to a redesign layout by redesign-ghosts.sh (place / recipes / can_place count).
local out = {}
-- ===== run =====
local function exists(e)
  return s.find_entities_filtered{position = {e.x, e.y}, radius = 0.3, name = e.name}[1]
      or s.find_entities_filtered{position = {e.x, e.y}, radius = 0.3, ghost_name = e.name}[1]
end
local cnt, bad, ok, skip, placed, fail = {}, {}, 0, 0, 0, {}
if MODE == 'place' then -- trees and rocks in the footprint get deconstruction marks; rerun 'place' once robots clear them
  for _, t in pairs(s.find_entities_filtered{area = {{96, 16}, {155, 54}}, type = {'tree', 'simple-entity'}}) do t.order_deconstruction('player') end
end
if MODE == 'recipes' then
  local set = 0
  for _, e in pairs(L) do if e.extra and e.extra.recipe then
    local m = s.find_entities_filtered{position = {e.x, e.y}, radius = 0.3, name = e.name}[1]
    if m and (not m.get_recipe() or m.get_recipe().name ~= e.extra.recipe) then m.set_recipe(e.extra.recipe) set = set + 1 end
  end end
  rcon.print('recipes set=' .. set) return
end
for _, e in pairs(L) do
  cnt[e.name] = (cnt[e.name] or 0) + 1
  if exists(e) then skip = skip + 1
  else
    local p = {name = e.name, position = {e.x, e.y}, direction = e.dir, force = 'player', build_check_type = defines.build_check_type.manual_ghost}
    if e.extra and e.extra.type then p.type = e.extra.type end
    if s.can_place_entity(p) then
      ok = ok + 1
      if MODE == 'place' then
        local c = {name = 'entity-ghost', inner_name = e.name, position = {e.x, e.y}, direction = e.dir, force = 'player'}
        if e.extra and e.extra.type then c.type = e.extra.type end
        if e.extra and e.extra.recipe then c.recipe = e.extra.recipe end
        local g = s.create_entity(c)
        if g then placed = placed + 1 else fail[#fail + 1] = string.format('%s(%.1f,%.1f)', e.name, e.x, e.y) end
      end
    else bad[#bad + 1] = string.format('%s(%.1f,%.1f)', e.name, e.x, e.y) end
  end
end
-- CHECK
local c = {} for k, v in pairs(cnt) do c[#c + 1] = k .. '=' .. v end
table.sort(c)
rcon.print(string.format('mode=%s total=%d ok=%d skip=%d placed=%d bad=%d %s | fail=%s | %s\n%s', MODE, #L, ok, skip, placed, #bad,
  table.concat(bad, ' '), table.concat(fail, ' '), table.concat(c, ','), table.concat(out, '\n')))
