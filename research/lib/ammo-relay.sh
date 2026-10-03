#!/usr/bin/env bash
# ammo-relay.sh SEAT [KEEP=100] [MAX=400]
# One relay pass: take yellow magazines above KEEP from the yellow block's pickup chest (21.5,-13.5),
# carry them to the piercing block's relay chests (48.5,-29.5) (2/3) and (39.5,-32.5) (1/3),
# and top copper/steel in the piercing input chests from the seat's inventory.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; keep=${2:-100}; max=${3:-400}
lua() { "$LIB/act.sh" exec_lua "$seat" code="local S='$seat' $1" | jq -r '.output // .'; }
"$LIB/walk.sh" "$seat" 24.5 -17 1.5 >/dev/null || { echo "walk to pickup failed"; exit 1; }
lua "local c=game.surfaces[1].find_entity('iron-chest',{21.5,-13.5}).get_inventory(defines.inventory.chest).get_item_count('firearm-magazine') local n=math.min($max,c-$keep) if n>0 then local ok,r=pcall(remote.call,'game_bot','take',{seat=S,x=21.5,y=-13.5,name='firearm-magazine',count=n,target='iron-chest'}) rcon.print('pickup had '..c..' took '..(ok and r.taken or tostring(r))) else rcon.print('pickup had '..c..' took 0') end"
"$LIB/walk.sh" "$seat" 44.5 -27.6 0.8 >/dev/null || { echo "walk to piercing block failed"; exit 1; }
have=$("$LIB/act.sh" observe "$seat" radius=1 | jq -r '.snapshot.inventory["firearm-magazine"] // 0')
lua "local s=game.surfaces[1] local have=$have
local function cnt(x,y,n) return s.find_entity('iron-chest',{x,y}).get_inventory(defines.inventory.chest).get_item_count(n) end
local function I(x,y,n,c) if c<=0 then return 0 end local ok,r=pcall(remote.call,'game_bot','insert',{seat=S,x=x,y=y,name=n,count=c,target='iron-chest'}) return ok and (r.inserted or 0) or 0 end
local a=I(48.5,-29.5,'firearm-magazine',math.floor(have*2/3)) local b=I(39.5,-32.5,'firearm-magazine',have-a)
local cu1=I(39.5,-33.5,'copper-plate',math.max(0,600-cnt(39.5,-33.5,'copper-plate')))
local cu2=I(46.5,-32.5,'copper-plate',math.max(0,600-cnt(46.5,-32.5,'copper-plate')))
local st2=I(46.5,-32.5,'steel-plate',math.max(0,300-cnt(46.5,-32.5,'steel-plate')))
local cu3=I(48.5,-29.5,'copper-plate',math.max(0,300-cnt(48.5,-29.5,'copper-plate')))
local st3=I(48.5,-29.5,'steel-plate',math.max(0,150-cnt(48.5,-29.5,'steel-plate')))
rcon.print('relay yellow +'..a..' (48.5) +'..b..' (39.5); copper +'..cu1..' +'..cu2..' +'..cu3..'; steel +'..st2..' +'..st3..'; relays now '..cnt(48.5,-29.5,'firearm-magazine')..'/'..cnt(39.5,-32.5,'firearm-magazine')..'; piercing chests '..cnt(45.5,-32.5,'piercing-rounds-magazine')..' + '..cnt(54.5,-30.5,'piercing-rounds-magazine')..' tick '..game.tick)"
