local seat = player.name
local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
local e = surf.find_entity('assembling-machine-1', {-30.5, -16.5})
local ok, err = false, 'no entity'
if e then ok, err = pcall(function() e.set_recipe('electronic-circuit') end) end
p('set_recipe electronic-circuit: ok='..tostring(ok)..' err='..tostring(err))
local ok2, res2 = pcall(remote.call, 'game_bot', 'insert', {seat=seat, x=-30.5, y=-16.5, name='iron-plate', count=50, target='assembling-machine-1'})
p('insert iron-plate: ok='..tostring(ok2)..' res='..tostring(res2))
-- report status of both assemblers + power
local cab = surf.find_entity('assembling-machine-1', {-34.5,-16.5})
local cir = surf.find_entity('assembling-machine-1', {-30.5,-16.5})
p('cable-asm status='..tostring(cab and cab.status))
p('circuit-asm status='..tostring(cir and cir.status))
local ins1 = surf.find_entity('inserter', {-32.5,-16.5})
local ins2 = surf.find_entity('inserter', {-28.5,-16.5})
p('link-inserter status='..tostring(ins1 and ins1.status)..' pickup='..tostring(ins1 and ins1.pickup_position and (ins1.pickup_position.x..','..ins1.pickup_position.y))..' drop='..tostring(ins1 and ins1.drop_position and (ins1.drop_position.x..','..ins1.drop_position.y)))
p('output-inserter status='..tostring(ins2 and ins2.status))
rcon.print(table.concat(out, '\n'))
