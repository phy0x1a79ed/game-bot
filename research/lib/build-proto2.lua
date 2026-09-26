local seat = player.name
local surf = game.surfaces[1]
local function try(name, args)
  local ok, res = pcall(remote.call, 'game_bot', name, args)
  return ok, res
end
local out = {}
local function p(s) out[#out+1] = s end

local builds = {
  {name='assembling-machine-1', x=-30.5, y=-16.5},
  {name='inserter', x=-28.5, y=-16.5, direction='west'},
  {name='iron-chest', x=-27.5, y=-16.5},
  {name='small-electric-pole', x=-29.5, y=-18.5},
}
for _, b in pairs(builds) do
  local args = {seat=seat, name=b.name, x=b.x, y=b.y}
  if b.direction then args.direction = b.direction end
  local ok, res = try('build', args)
  p('build '..b.name..'@'..b.x..','..b.y..': ok='..tostring(ok)..' res='..tostring(res))
end

local e = surf.find_entity('assembling-machine-1', {-30.5, -16.5})
local ok, err = false, 'no entity'
if e then ok, err = pcall(function() e.set_recipe('electronic-circuit') end) end
p('set_recipe electronic-circuit@-30.5,-16.5: ok='..tostring(ok)..' err='..tostring(err))

local ok2, res2 = try('insert', {seat=seat, x=-30.5, y=-16.5, name='iron-plate', count=50, target='assembling-machine-1'})
p('insert iron-plate@-30.5,-16.5: ok='..tostring(ok2)..' res='..tostring(res2))

rcon.print(table.concat(out, '\n'))
