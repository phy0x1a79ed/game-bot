#!/usr/bin/env bash
# redesign-a-do.sh 'lua body' — runs body with helpers T(x,y,name,count) I(x,y,name,count) C(name,count) B(name,x,y,dir) on seat-cee084d2
S=seat-cee084d2
H="local seat='$S' local function P(tag,ok,r) if not ok then rcon.print('ERR '..tag..' '..tostring(r):sub(1,150)) else rcon.print(tag..' '..(type(r)=='table' and serpent.line(r):sub(1,200) or tostring(r))) end end
local function T(x,y,n,c) P('T '..n,pcall(remote.call,'game_bot','take',{seat=seat,x=x,y=y,name=n,count=c})) end
local function I(x,y,n,c) P('I '..n,pcall(remote.call,'game_bot','insert',{seat=seat,x=x,y=y,name=n,count=c})) end
local function C(n,c) P('C '..n,pcall(remote.call,'game_bot','craft',{seat=seat,recipe=n,count=c})) end
local function B(n,x,y,d) P('B '..n..' '..x..','..y,pcall(remote.call,'game_bot','build',{seat=seat,name=n,x=x,y=y,direction=d or 'north'})) end
"
/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib/act.sh exec_lua $S code="$H $1" | jq -r '.output // .'
