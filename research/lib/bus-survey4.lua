local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end

p('=== RECIPE COSTS ===')
for _, n in pairs({'transport-belt','splitter','underground-belt','stone-wall','gun-turret','small-electric-pole','medium-electric-pole','firearm-magazine','iron-gear-wheel','electronic-circuit','copper-cable','automation-science-pack','logistic-science-pack','steel-plate'}) do
  local proto = prototypes.recipe[n]
  if proto then
    local ings = {}
    for _, ing in pairs(proto.ingredients) do ings[#ings+1] = ing.name..'x'..ing.amount end
    p(n..' <- '..table.concat(ings, '+')..' (time='..proto.energy..'s)')
  else
    p(n..' <- NO RECIPE FOUND')
  end
end

p('=== IRON BELT GEOMETRY (collector column + turn) ===')
for _, e in pairs(surf.find_entities_filtered{name='transport-belt', area={{-21,-64},{-18,-6}}}) do
  p(string.format('belt @ (%.1f,%.1f) dir=%d', e.position.x, e.position.y, e.direction))
end

p('=== TURN CORNER + WEST LEG belts (y=-7.5 to -8.5, x=-38 to -19) ===')
for _, e in pairs(surf.find_entities_filtered{name='transport-belt', area={{-40,-9},{-18,-6}}}) do
  p(string.format('belt @ (%.1f,%.1f) dir=%d', e.position.x, e.position.y, e.direction))
end

rcon.print(table.concat(out, '\n'))
