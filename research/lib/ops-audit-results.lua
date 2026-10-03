-- ops-audit-results: READ-ONLY. Verification reads for the RESULT lines audited in audit-0138: products_finished + status of named machines (rate = delta over >=120 s), splitter priorities, presence/direction of named entities, copper on the P feed belts.
local ST = {} for k,v in pairs(defines.entity_status) do ST[v]=k end
local s = game.surfaces[1]
local function at(x,y,r) return s.find_entities_filtered{position={x,y}, radius=r or 0.4} end
local function am(x,y)
  for _, e in pairs(at(x,y)) do if e.type=="assembling-machine" or e.type=="furnace" then
    local r = e.get_recipe and e.get_recipe()
    rcon.print(string.format("AM (%.1f,%.1f) %s %s status=%s pf=%d", x,y,e.name,r and r.name or "-",ST[e.status] or "?", e.products_finished)) return end end
  rcon.print(string.format("AM (%.1f,%.1f) NONE", x,y))
end
rcon.print("TICK "..game.tick)
for _, p in ipairs({{-12.5,5.5},{-4.5,17.5},{-9.5,21.5},{3.5,-4.5},{6.5,-4.5},{-11.5,30.5},{-11.5,34.5},{-19.5,34.5}}) do am(p[1],p[2]) end
for _, p in ipairs({{25.5,15},{-14.5,-28}}) do
  for _, e in pairs(at(p[1],p[2],1.2)) do if e.type=="splitter" then rcon.print(string.format("splitter (%.1f,%.1f) out_prio=%s in_prio=%s", e.position.x,e.position.y,tostring(e.splitter_output_priority),tostring(e.splitter_input_priority))) end end
end
for _, p in ipairs({{22.5,-50.5},{24.5,-50.5},{22.5,-47.5},{30.5,-47.5},{-17.5,-7.5},{5.5,-10.5}}) do
  local l = {}
  for _, e in pairs(at(p[1],p[2])) do l[#l+1] = e.name.." dir="..e.direction end
  rcon.print(string.format("ENT (%.1f,%.1f) %s", p[1],p[2],table.concat(l,";")))
end
for _, x in ipairs({15.5,16.5,17.5}) do
  for _, e in pairs(at(x,-49.5)) do if e.type=="transport-belt" then
    local c = {} for i=1,2 do for _, it in pairs(e.get_transport_line(i).get_contents()) do c[#c+1]="L"..i..":"..it.name.."x"..it.count end end
    rcon.print(string.format("belt (%.1f,-49.5) %s", x, table.concat(c,","))) end end
end
for _, p in ipairs({{-15.5,32.5},{-15.5,40.5},{16.5,-37.5},{16.5,-40.5}}) do
  for _, e in pairs(at(p[1],p[2])) do if e.type=="transport-belt" then
    local c = {} for i=1,2 do for _, it in pairs(e.get_transport_line(i).get_contents()) do c[#c+1]="L"..i..":"..it.name.."x"..it.count end end
    rcon.print(string.format("belt (%.1f,%.1f) %s", p[1],p[2], table.concat(c,","))) end end
end
