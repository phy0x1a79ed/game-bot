local surf = player.surface
local pts = {
  {name="spawn/depot", x=4, y=-22},
  {name="lab/power", x=-44, y=-18},
  {name="stone-drill", x=60, y=-30},
  {name="coal-ring-north", x=70, y=-47},
  {name="copper-modules", x=26, y=53},
}
for _,p in pairs(pts) do
  local n = surf.find_entities_filtered{force="enemy", type="unit", position={p.x,p.y}, radius=40}
  rcon.print(p.name.." ("..p.x..","..p.y.."): "..#n.." enemies within 40")
end
