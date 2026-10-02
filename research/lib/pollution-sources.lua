-- pollution-sources.lua: pollution per minute by source and absorption (spawners, tiles). Baseline tick 1009266: 286/min made, 183 absorbed by tiles, 12.6 by spawners.
local surf=game.surfaces[1]
local ps=game.get_pollution_statistics(surf)
local out={'tick='..game.tick}
local tot=0
for name,_ in pairs(ps.input_counts) do
  local v=ps.get_flow_count{name=name,category='input',precision_index=defines.flow_precision_index.ten_minutes}
  tot=tot+v
  out[#out+1]=string.format('%-26s %7.1f /min (10min avg)',name,v)
end
out[#out+1]='TOTAL '..string.format('%.1f',tot)
local ab=0
for name,_ in pairs(ps.output_counts) do
  local v=ps.get_flow_count{name=name,category='output',precision_index=defines.flow_precision_index.ten_minutes}
  ab=ab+v out[#out+1]=string.format('absorbed by %-22s %7.1f /min',name,v)
end
local tp=0 for gx=-640,640,32 do for gy=-640,640,32 do tp=tp+surf.get_pollution({gx,gy}) end end
out[#out+1]='cloud sum(32-grid samples)='..string.format('%.0f',tp)
rcon.print(table.concat(out,'\n'))
