#!/usr/bin/env bash
# map.sh SEAT X1 Y1 X2 Y2 — ASCII map, 1 char per tile (integer tile coords, tile centre = x+0.5).
# belts ^>v< ; underground: in = capital arrow-ish 'n e s w' lower=entrance, upper=exit ; splitter S ; inserter i ; pole + ; chest C ; furnace F ; drill D ; assembler A ; lab L ; turret T ; wall W ; pipe p ; water ~ ; ore: c copper, a iron, o coal, t stone (when empty)
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; x1=$2; y1=$3; x2=$4; y2=$5; tmp=$(mktemp /tmp/map.XXXXXX.lua)
cat > "$tmp" <<EOL
local x1,y1,x2,y2=$x1,$y1,$x2,$y2
local s=game.surfaces[1]
local g={}
for y=y1,y2-1 do g[y]={} for x=x1,x2-1 do g[y][x]=' ' end end
local function put(x,y,c) if g[y] and g[y][x] then g[y][x]=c end end
for _,r in pairs(s.find_entities_filtered{area={{x1,y1},{x2,y2}},type='resource'}) do
  local c=({['copper-ore']='c',['iron-ore']='a',['coal']='o',['stone']='t',['uranium-ore']='u'})[r.name] or 'r'
  put(math.floor(r.position.x),math.floor(r.position.y),c)
end
for y=y1,y2-1 do for x=x1,x2-1 do
  local t=s.get_tile(x,y)
  if t.name:find('water') then g[y][x]='~' end
end end
local arrows={[0]='^',[4]='>',[8]='v',[12]='<'}
local ug={[0]='n',[4]='e',[8]='s',[12]='w'}
for _,e in pairs(s.find_entities_filtered{area={{x1,y1},{x2,y2}}}) do
  if e.type~='character' and e.type~='resource' and e.type~='tree' and e.type~='cliff' and e.type~='simple-entity' then
    local bb=e.bounding_box
    local c='?'
    local t=e.type
    if t=='transport-belt' then c=arrows[e.direction]
    elseif t=='underground-belt' then c=ug[e.direction]; if e.belt_to_ground_type=='output' then c=string.upper(c) end
    elseif t=='splitter' then c='S'
    elseif t=='inserter' then c='i'
    elseif t=='electric-pole' then c='+'
    elseif t=='container' then c='C'
    elseif t=='furnace' then c='F'
    elseif t=='mining-drill' then c='D'
    elseif t=='assembling-machine' then c='A'
    elseif t=='lab' then c='L'
    elseif t=='ammo-turret' then c='T'
    elseif t=='wall' then c='W'
    elseif t=='pipe' or t=='pipe-to-ground' then c='p'
    elseif t=='boiler' then c='B' elseif t=='generator' then c='E' elseif t=='offshore-pump' then c='P'
    end
    if t=='transport-belt' or t=='underground-belt' or t=='splitter' or t=='inserter' or t=='electric-pole' or t=='container' then
      if t=='splitter' then
        for xx=math.floor(bb.left_top.x+0.01),math.ceil(bb.right_bottom.x-0.01)-1 do for yy=math.floor(bb.left_top.y+0.01),math.ceil(bb.right_bottom.y-0.01)-1 do put(xx,yy,'S') end end
      else put(math.floor(e.position.x),math.floor(e.position.y),c) end
    else
      for xx=math.floor(bb.left_top.x+0.01),math.ceil(bb.right_bottom.x-0.01)-1 do for yy=math.floor(bb.left_top.y+0.01),math.ceil(bb.right_bottom.y-0.01)-1 do put(xx,yy,c) end end
    end
  end
end
local out={}
local hdr='     '
for x=x1,x2-1 do hdr=hdr..(x%10==0 and tostring(math.floor(math.abs(x)%100/10)) or ' ') end
out[#out+1]=hdr
for y=y1,y2-1 do local row={} for x=x1,x2-1 do row[#row+1]=g[y][x] end out[#out+1]=string.format('%4d ',y)..table.concat(row) end
rcon.print(table.concat(out,'\n'))
EOL
"$LIB/act.sh" exec_lua "$seat" path="$tmp" | jq -r '.output // .'
rm -f "$tmp"
