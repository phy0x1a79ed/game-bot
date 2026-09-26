local seat = player.name
local surf = game.surfaces[1]
local function try(name, args)
  local ok, res = pcall(remote.call, 'game_bot', name, args)
  return ok, res
end
local out = {}
local function p(s) out[#out+1] = s end

local builds = {
  {name='assembling-machine-1', x=-34.5, y=-16.5},
  {name='inserter', x=-32.5, y=-16.5, direction='west'},
  {name='assembling-machine-1', x=-30.5, y=-16.5},
  {name='inserter', x=-28.5, y=-16.5, direction='west'},
  {name='iron-chest', x=-27.5, y=-16.5},
  {name='small-electric-pole', x=-35.5, y=-14.5},
  {name='small-electric-pole', x=-29.5, y=-18.5},
}
for _, b in pairs(builds) do
  local args = {seat=seat, name=b.name, x=b.x, y=b.y}
  if b.direction then args.direction = b.direction end
  local ok, res = try('build', args)
  p('build '..b.name..'@'..b.x..','..b.y..': ok='..tostring(ok)..' res='..tostring(res and (res.ok or res) or res))
end

local recipes = {
  {x=-34.5, y=-16.5, recipe='copper-cable'},
  {x=-30.5, y=-16.5, recipe='electronic-circuit'},
}
for _, r in pairs(recipes) do
  local e = surf.find_entity('assembling-machine-1', {r.x, r.y})
  local ok, err = false, 'no entity'
  if e then ok, err = pcall(function() e.set_recipe(r.recipe) end) end
  p('set_recipe '..r.recipe..'@'..r.x..','..r.y..': ok='..tostring(ok)..' err='..tostring(err))
end

local inserts = {
  {x=-34.5, y=-16.5, name='copper-plate', count=100, target='assembling-machine-1'},
  {x=-30.5, y=-16.5, name='iron-plate', count=50, target='assembling-machine-1'},
}
for _, i in pairs(inserts) do
  local ok, res = try('insert', {seat=seat, x=i.x, y=i.y, name=i.name, count=i.count, target=i.target})
  p('insert '..i.name..'@'..i.x..','..i.y..': ok='..tostring(ok)..' res='..tostring(res))
end

rcon.print(table.concat(out, '\n'))
