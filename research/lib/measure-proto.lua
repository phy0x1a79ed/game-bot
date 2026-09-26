local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
p('tick='..game.tick)
local chest = surf.find_entity('iron-chest', {-27.5,-16.5})
local circuits = 0
if chest then
  local inv = chest.get_inventory(defines.inventory.chest)
  circuits = inv.get_item_count('electronic-circuit')
end
p('circuits_in_chest='..circuits)
local cab = surf.find_entity('assembling-machine-1', {-34.5,-16.5})
local cir = surf.find_entity('assembling-machine-1', {-30.5,-16.5})
p('cable-asm status='..tostring(cab and cab.status)..' progress='..tostring(cab and cab.crafting_progress))
p('circuit-asm status='..tostring(cir and cir.status)..' progress='..tostring(cir and cir.crafting_progress))
rcon.print(table.concat(out, '\n'))
