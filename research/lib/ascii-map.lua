-- ascii-map.lua: ASCII map of a region. Run via ascii-map.sh X0 Y0 X1 Y1 SEAT (substitutes X0,Y0,X1,Y1).
-- Legend: ^>v< belt, U underground, S splitter, n inserter, m burner inserter, C chest, P pole, A assembler, L lab, T turret, W wall, F furnace, D burner drill, E electric drill, B boiler, G engine, = pipe/pump, i/c/k/s ore, ~ water, X rock/wreck, t tree
local surf = game.surfaces[1]
local x0,y0,x1,y1 = X0,Y0,X1,Y1
local g = {}
for y=y0,y1-1 do g[y]={} for x=x0,x1-1 do g[y][x]='.' end end
local function put(x,y,c) if g[y] and g[y][x] then g[y][x]=c end end
-- tiles
for y=y0,y1-1 do for x=x0,x1-1 do
  local t = surf.get_tile(x,y)
  if t.collides_with('player') then put(x,y,'~') end
end end
local ch = {['transport-belt']=true}
local arrows = {[0]='^',[4]='>',[8]='v',[12]='<'}
for _,e in pairs(surf.find_entities_filtered{area={{x0,y0},{x1,y1}}}) do
  if e.type~='character' then
    local c='?'
    local n=e.name
    if e.type=='resource' then c=(n=='iron-ore' and 'i') or (n=='copper-ore' and 'c') or (n=='coal' and 'k') or (n=='stone' and 's') or 'r'
    elseif n=='transport-belt' then c=arrows[e.direction] or 'b'
    elseif n=='underground-belt' then c='U'
    elseif n=='splitter' then c='S'
    elseif n=='inserter' then c='n'
    elseif n=='burner-inserter' then c='m'
    elseif n=='iron-chest' then c='C'
    elseif n=='small-electric-pole' then c='P'
    elseif n=='assembling-machine-1' then c='A'
    elseif n=='lab' then c='L'
    elseif n=='gun-turret' then c='T'
    elseif n=='stone-wall' then c='W'
    elseif n=='stone-furnace' then c='F'
    elseif n=='burner-mining-drill' then c='D'
    elseif n=='electric-mining-drill' then c='E'
    elseif n=='boiler' then c='B'
    elseif n=='steam-engine' then c='G'
    elseif n=='pipe' or n=='offshore-pump' then c='='
    elseif e.type=='tree' then c='t'
    elseif e.type=='simple-entity' or e.type=='cliff' or e.type=='simple-entity-with-owner' then c='X'
    elseif e.type=='item-entity' then c='*'
    else c=string.sub(n,1,1) end
    if e.type=='resource' then if g[math.floor(e.position.y)] and g[math.floor(e.position.y)][math.floor(e.position.x)]=='.' then put(math.floor(e.position.x),math.floor(e.position.y),c) end
    elseif e.type=='item-entity' then put(math.floor(e.position.x),math.floor(e.position.y),c)
    else
      local bb=e.bounding_box
      local ax,ay,bx,by=math.floor(bb.left_top.x+0.01),math.floor(bb.left_top.y+0.01),math.ceil(bb.right_bottom.x-0.01)-1,math.ceil(bb.right_bottom.y-0.01)-1
      for yy=ay,by do for xx=ax,bx do put(xx,yy,c) end end
    end
  end
end
local out={}
local hdr='     '
for x=x0,x1-1 do hdr=hdr..(math.abs(x)%10==0 and tostring(math.floor(math.abs(x)/10)%10) or ' ') end
out[#out+1]=hdr
local hdr2='     '
for x=x0,x1-1 do hdr2=hdr2..tostring(math.abs(x)%10) end
out[#out+1]=hdr2
for y=y0,y1-1 do local row={} for x=x0,x1-1 do row[#row+1]=g[y][x] end out[#out+1]=string.format('%4d ',y)..table.concat(row) end
rcon.print(table.concat(out,'\n'))
