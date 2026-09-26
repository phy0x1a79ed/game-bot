local names = {
  'iron-gear-wheel','copper-cable','electronic-circuit','automation-science-pack',
  'logistic-science-pack','transport-belt','inserter','small-electric-pole',
  'assembling-machine-1','electric-mining-drill','stone-furnace','burner-mining-drill',
  'firearm-magazine','stone-wall','repair-pack','gun-turret','pipe','iron-chest',
  'iron-plate','copper-plate','stone-brick','steel-plate','gun-turret'
}
local out = {}
local recs = (prototypes and prototypes.recipe) or game.recipe_prototypes
for _, n in pairs(names) do
  local r = recs[n]
  if r then
    local ing = {}
    for _, i in pairs(r.ingredients) do ing[#ing+1] = i.name..'x'..i.amount end
    local prod = {}
    for _, pr in pairs(r.products) do
      local amt = pr.amount or ((pr.amount_min or 0 + (pr.amount_max or 0))/2)
      prod[#prod+1] = pr.name..'x'..tostring(amt)..(pr.probability and pr.probability<1 and ('@'..pr.probability) or '')
    end
    out[#out+1] = n..' | energy='..r.energy..' | in: '..table.concat(ing,', ')..' | out: '..table.concat(prod,', ')
  else
    out[#out+1] = n..' | MISSING'
  end
end
rcon.print(table.concat(out, '\n'))
