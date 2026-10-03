#!/usr/bin/env bash
# safe-walk.sh SEAT X Y [TOL] — walk.sh with a threat watch (chair TRAVEL RULE).
# The seat walks in legs of at most LEG tiles (one waypoint each), so it never covers more than LEG
# tiles on a stale read however slow RCON is. Every leg reads seat hp and enemy units within R, aims
# the equipped gun at the nearest unit in range (shooting_state) and keeps a defender screen up: on
# first contact the seat stops and throws defenders until SCREEN are out, then moves on, re-throwing
# as they expire. A unit within gun range halts the walk until it is dead (hold).
# Retreats (continuous walk, still firing and screening) to a point behind the nearest armed turret
# group when hp < HPFRAC of max, CLOSE_N+ units stand within CLOSE_R, a worm can reach the seat,
# the gun is dry with units near, or a hold lasts MAXHOLD legs.
# Final line: "RESULT arrived|retreated|aborted <reason> ..."; exit 0 / 2 / 1.
# Env: LEG=10 R=30 CLOSE_R=20 CLOSE_N=3 HPFRAC=0.6 SCREEN=6 MAXHOLD=20 MAXT=600 (wall s)
#      RMAX=300 turret-group search radius for a retreat; RFX,RFY = fallback retreat point when no
#      group lies within RMAX (otherwise the seat may retreat 200+ tiles through unscouted ground).
#      Tests: FORCE_SCREEN=1 throws the screen with no enemy present; HPFRAC=1.01 forces a retreat.
L=/home/tony/agentic_workspace/projects/game-bot/factorio/research/lib
seat=$1; gx=$2; gy=$3; tol=${4:-2}
LEG=${LEG:-10}; R=${R:-30}; CLOSE_R=${CLOSE_R:-20}; CLOSE_N=${CLOSE_N:-3}; HPFRAC=${HPFRAC:-0.6}
SCREEN=${SCREEN:-6}; MAXHOLD=${MAXHOLD:-20}; MAXT=${MAXT:-600}; FORCE_SCREEN=${FORCE_SCREEN:-0}
RMAX=${RMAX:-300}; RFX=${RFX:-}; RFY=${RFY:-}
tmp=$(mktemp /tmp/safe-walk-XXXX.lua); trap 'rm -f "$tmp"' EXIT

step() {  # step MODE TX TY -> sets V_<key> from the Lua's key=value line
  { echo "local SEAT,MODE,TX,TY,R,CLOSE_R,SCREEN,FORCE_SCREEN,LEG,RMAX='$seat','$1',$2,$3,$R,$CLOSE_R,$SCREEN,$FORCE_SCREEN,$LEG,$RMAX"
    grep -v "^[[:space:]]*--" "$L/safe-walk.lua" | sed "s/^[[:space:]]*//"; } >"$tmp"
  local out try
  for try in 1 2 3; do   # a transport error (broken pipe, timeout) is retried; a Lua error is not
    out=$("$L/act.sh" exec_lua "$seat" path="$tmp" | jq -r '.output // .')
    [[ $out == *RpcError* ]] || break; sleep 1
  done
  unset ${!V_*}
  for kv in $out; do [[ $kv == *=* ]] && printf -v "V_${kv%%=*}" '%s' "${kv#*=}"; done
  [ -n "$V_dead" ] || { echo "ERR step $1: $out"; V_dead=err; }
}
move() { "$L/act.sh" move "$seat" x="$1" y="$2" >/dev/null 2>&1; }
halt() { "$L/act.sh" stop "$seat" >/dev/null 2>&1; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<b)}'; }
add() { awk -v a="$1" -v b="$2" 'BEGIN{print a+b}'; }
finish() { step cease 0 0 >/dev/null; echo "RESULT $1"; exit "$2"; }
line() {
  printf 'leg %d %-7s t%s (%s,%s) hp %s/%s d %s units %s close %s near %s@%s fire %s fol %s+%s defs %s ammo %s%s\n' \
    "$leg" "$1" "$V_tick" "$V_x" "$V_y" "$V_hp" "$V_max" "$V_d" "$V_units" "$V_close" "$V_near" "$V_nd" \
    "$V_fire" "$V_fol" "$V_fly" "$V_defs" "$V_ammo" "${2:+ | $2}"
}

cid0=""; mode=walk; tx=$gx; ty=$gy; leg=0; stall=0; hold=0; screened=0; start=$SECONDS; lastpos=""; grp=""
nudges=("0 0" "1 0" "0 1" "-1 0" "0 -1" "2 2" "-2 -2" "3 -3")
while :; do
  leg=$((leg + 1))
  step leg "$tx" "$ty"
  [ "$V_dead" = 1 ] && finish "aborted seat dead at leg $leg" 1
  [ "$V_dead" = err ] && { halt; finish "aborted lua error" 1; }
  [ -z "$cid0" ] && cid0=$V_cid
  [ -n "$V_cid" ] && [ "$V_cid" != "$cid0" ] && { halt; finish "aborted seat died and RESPAWNED at ($V_x,$V_y) during the walk (character changed)" 1; }
  (( SECONDS - start > MAXT )) && { halt; finish "aborted time limit ${MAXT}s at ($V_x,$V_y) hp $V_hp" 1; }
  note=""; [ "$V_dep" = 1 ] && note="defender thrown"

  if [ $mode = walk ]; then
    why=""
    lt "$V_hp" "$(awk -v m="$V_max" -v f="$HPFRAC" 'BEGIN{print m*f}')" && why="hp $V_hp < $HPFRAC x $V_max"
    (( V_close >= CLOSE_N )) && why="$V_close units within $CLOSE_R"
    [ "$V_worm" != none ] && why="worm in range $V_worm"
    (( V_units > 0 && V_ammo == 0 )) && why="gun dry"
    (( hold > MAXHOLD )) && why="hold over $MAXHOLD legs"
    if [ -n "$why" ]; then
      line walk "RETREAT: $why"
      step retreat 0 0
      [ "$V_dead" = err ] && { halt; finish "aborted ($why) and the retreat read failed" 1; }
      if [ "$V_group" = none ] && [ -n "$RFX" ]; then V_group=0; V_rx=$RFX; V_ry=$RFY; V_gx=$RFX; V_gy=$RFY; V_gd=fallback; fi
      [ "$V_group" = none ] && { halt; finish "aborted ($why) and no armed turret group within $RMAX (armed $V_armed)" 1; }
      echo "retreat target ($V_rx,$V_ry) behind $V_group armed turrets centred ($V_gx,$V_gy), $V_gd tiles"
      mode=retreat; grp=$V_group; tx=$V_rx; ty=$V_ry; stall=0; move "$tx" "$ty"; continue
    fi
    if (( (V_units > 0 || FORCE_SCREEN == 1) && screened == 0 )); then   # screen first, then move
      halt; line screen "$note"
      for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
        (( V_fol + V_fly >= SCREEN || V_defs == 0 )) && break
        step leg "$tx" "$ty"; [ "$V_dead" = 1 ] && finish "aborted seat dead while screening" 1
        line screen "$([ "$V_dep" = 1 ] && echo 'defender thrown')"
      done
      screened=1; continue
    fi
    if [ "$V_fire" = 1 ]; then   # a unit in gun range: stand and shoot
      (( hold == 0 )) && halt; hold=$((hold + 1)); line hold "$note"; continue
    fi
    hold=0
    if lt "$V_d" "$tol"; then line walk "$note"; finish "arrived ($V_x,$V_y) hp $V_hp/$V_max units $V_units fol $V_fol legs $leg" 0; fi
    # next leg; a leg that gained no ground re-routes straight at the target, then nudges
    if [ "$V_x,$V_y" = "$lastpos" ]; then stall=$((stall + 1)); else stall=0; fi
    lastpos="$V_x,$V_y"
    (( stall >= ${#nudges[@]} )) && finish "aborted stuck at ($V_x,$V_y), $V_d from target" 1
    if (( stall == 0 )); then move "$V_wx" "$V_wy"; note="${note:+$note; }to ($V_wx,$V_wy)"
    else set -- ${nudges[$stall]}; move "$(add "$tx" "$1")" "$(add "$ty" "$2")"; note="${note:+$note; }stalled, direct re-move $stall"; fi
    line walk "$note"; continue
  fi

  # retreat: one continuous walk order, re-issued if it ends short
  if lt "$V_d" 2.5; then
    line retreat "$note"
    finish "retreated to ($V_x,$V_y) behind $grp turrets, hp $V_hp/$V_max units $V_units fol $V_fol legs $leg" 2
  fi
  if [ "$V_walk" = 0 ]; then
    stall=$((stall + 1))
    (( stall >= ${#nudges[@]} )) && finish "aborted retreat stuck at ($V_x,$V_y), $V_d from the turrets" 1
    set -- ${nudges[$stall]}; move "$(add "$tx" "$1")" "$(add "$ty" "$2")"; note="${note:+$note; }re-move $stall"
  fi
  line retreat "$note"
done
