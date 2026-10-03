-- Copper redesign stage 2: mark the old in-line copper line for deconstruction (furnaces, their inserters, centre belt, splitter, loop, east drills, coal turn, items on ground). Set POLES=true to also mark the 4 old small poles.
local s=game.surfaces[1] local n=0 local o={}
local function mark(e) if e and e.valid and not e.to_be_deconstructed() then if e.order_deconstruction('player') then n=n+1 end end end
local function box(x1,y1,x2,y2,f) for _,e in pairs(s.find_entities_filtered{area={{x1,y1},{x2,y2}},type=f}) do mark(e) end end
box(14.6,53.6,22.4,67.4,'furnace')
box(17,54,20,67,'inserter')
box(18.1,52.1,18.9,66.9,'transport-belt')
box(18.1,52.1,19.9,52.9,'splitter')
box(19.1,51.1,27.9,51.9,'transport-belt')
box(28.1,51.1,28.9,67.9,'transport-belt')
box(18.1,67.1,27.9,67.9,'transport-belt')
box(29.1,55.1,31.9,55.9,'transport-belt') box(31.1,54.1,31.9,54.9,'transport-belt')
for _,y in pairs{55.5,58.5,61.5,64.5} do mark(s.find_entity('electric-mining-drill',{23.5,y})) end
box(10,52,29,70,'item-entity')
if POLES then for _,p in pairs{{16.5,57.5},{16.5,63.5},{20.5,57.5},{20.5,63.5}} do mark(s.find_entity('small-electric-pole',p)) end end
rcon.print('marked '..n)
