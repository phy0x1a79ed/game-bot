#!/usr/bin/env bash
# iron-from-gear.sh SEAT WANT [FLOOR]
# Tops the seat's iron-plate up to WANT from the gear assembler's input chest
# (-38.5,-8.5), never taking that chest below FLOOR (default 700). The iron
# belt backs up into that chest, so its surplus is free iron for the ammo
# assembler and the green-line chests.
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat=$1; want=$2; floor=${3:-700}
have=$("$LIB/act.sh" observe "$seat" radius=1 2>/dev/null | jq -r '.snapshot.inventory["iron-plate"] // 0')
need=$((want - have))
[ "$need" -le 0 ] && { echo "iron on hand $have >= $want"; exit 0; }
lvl=$(RLM_SEAT="$seat" "$LIB/../rlm.sh" exec-lua --code 'local c=game.surfaces[1].find_entity("iron-chest",{-38.5,-8.5}) rcon.print(c and c.get_inventory(defines.inventory.chest).get_item_count("iron-plate") or -1)' 2>/dev/null | jq -r '.output // "-1"' | tr -d '[:space:]')
spare=$((lvl - floor))
[ "$spare" -le 0 ] && { echo "gear chest at $lvl, nothing spare above $floor"; exit 0; }
[ "$need" -gt "$spare" ] && need=$spare
"$LIB/walk.sh" "$seat" -38 -5 3 >/dev/null 2>&1
got=$("$LIB/act.sh" take "$seat" x=-38.5 y=-8.5 name=iron-plate count="$need" target=iron-chest 2>/dev/null | jq -r '.taken // 0')
echo "took $got iron from gear chest (was $lvl)"
