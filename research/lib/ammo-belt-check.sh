#!/usr/bin/env bash
# ammo-belt-check.sh SEAT X0 Y0 X1 Y1 — inserter statuses, turret ammo, belt ammo and feed chests of a belt-fed turret group in the box.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$LIB/act.sh" exec_lua "$1" code="AREA_BOX={{$2,$3},{$4,$5}} $(cat "$LIB/ammo-belt-check.lua")" | jq -r '.output // .'
