#!/usr/bin/env bash
# body-take plates from every furnace built by this tech's line. Only the
# furnace(s) within reach (10.5) of the body's CURRENT position succeed --
# the iron pair and the copper furnace are ~75-95 tiles apart, so walk to a
# site (see automated-smelting.md layout coords) before running this, or
# just run it opportunistically and ignore the "no entity"/"out of reach"
# errors for sites you're not standing next to.
#
# Usage: ./lib/harvest-plates.sh
set -euo pipefail
cd "$(dirname "$0")/.."

try_take() {
  local x="$1" y="$2" name="$3"
  echo "-- take $name @ ($x,$y)"
  ./rlm.sh body-take --x "$x" --y "$y" --name "$name" 2>&1 || true
}

# Iron pair (near iron patch, ~(-7,-35))
try_take -4 -36 iron-plate
try_take -8 -32 iron-plate
# Copper (near copper patch, ~(8,43))
try_take 10 43 copper-plate
