local surf = game.surfaces[1]
local out = {}
local function p(s) out[#out+1] = s end
-- everything (any force, any type) near the two failed spots
for _, pos in pairs({{-44.5,-16.5},{-40.5,-16.5}}) do
  local near = surf.find_entities_filtered{area={{pos[1]-2,pos[2]-2},{pos[1]+2,pos[2]+2}}}
  p('near '..pos[1]..','..pos[2]..': '..#near)
  for _, e in pairs(near) do p('  '..e.name..'('..e.type..') @ '..string.format('%.2f,%.2f',e.position.x,e.position.y)) end
  local tiles = surf.find_tiles_filtered{area={{pos[1]-1.5,pos[2]-1.5},{pos[1]+1.5,pos[2]+1.5}}}
  local tn = {}
  for _, t in pairs(tiles) do tn[t.name] = (tn[t.name] or 0) + 1 end
  local ts = {}
  for k,v in pairs(tn) do ts[#ts+1]=k..':'..v end
  p('  tiles: '..table.concat(ts,' '))
end
rcon.print(table.concat(out, '\n'))
