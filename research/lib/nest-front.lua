-- nest-front.lua: pollution along the line from each nest toward the base, plus evolution. Baseline tick 988020: N1 +16:14.8, N2 +32:14.8, SW +16:8.8, W +32:14.8.
local surf=game.surfaces[1]
local nests={{'N1',-17,-237},{'N2',46,-245},{'SW',-186,134},{'W',-252,14},{'NW',-241,-185},{'W2',-296,-39},{'S',-24,336}}
local out={'tick='..game.tick..' evo='..string.format('%.4f',game.forces.enemy.get_evolution_factor(surf))}
for _,n in ipairs(nests) do
  local row={}
  for _,off in ipairs{0,16,32,48,64} do
    local dx,dy=-20-n[2],-45-n[3]
    local L=math.sqrt(dx*dx+dy*dy)
    local x,y=n[2]+dx/L*off,n[3]+dy/L*off
    row[#row+1]=string.format('+%d:%.1f',off,surf.get_pollution({x,y}))
  end
  out[#out+1]=n[1]..' '..table.concat(row,' ')
end
rcon.print(table.concat(out,'\n'))
