# research/basic — play Factorio through the realm, aim for automated red science

## Purpose & Contents

This folder holds what playing Factorio taught us, not the means of playing it.
The agent plays through the **rlm-factorio** awm realm (`awm/services/rlm-factorio`,
MCP domain `rlm`, CLI `awm rlm factorio-*`), which is owned by the awm project and
is never modified from here. Each capability worked out in the live world is
written up as a replayable recipe in `tech/<name>.md`, with reusable scripts in
`lib/`. `tech/INDEX.md` tracks which rungs are done.

## Watch the game

- **Address:** Factorio → *Multiplayer → Connect to address* → `localhost:12140`.
  From another LAN machine, use the Windows host's LAN IP with UDP allowed.
  The LAN-games browser never lists this world. The engine broadcasts onto the
  Docker bridge subnet, which does not reach the host LAN.
- **Version:** the deployed realm pins Factorio **2.1.20** (experimental). Match
  it exactly — Steam → Factorio → Properties → Betas.
- **DLC:** own Space Age. The server enables space-age, quality, elevated-rails
  and recycler.
- **Mod:** copy `game-bot-control_<ver>.zip` from the realm's
  `appliance/dist/` into `%APPDATA%\Factorio\mods`. Enable it. Restart the
  client. The realm's copy is the only authority on the version — a stale copy
  is refused as `ModsMismatch`.
- **CAUTION** Edit `mod-list.json` only while Factorio is closed. The game
  rewrites that file from memory on exit and silently reverts the change.
- **World:** `railworld-218` seed. Rich ore patches, no enemy expansion.

## Use the realm from a shell

`./rlm.sh <verb> [--flag value ...]` wraps `awm rlm factorio-<verb>` with the
live session id from `.session`. `./rlm.sh observe --help` shows a verb's flags.
`rlm(verb="describe")` lists the current surface and cannot go stale.

## The seat model superseded the scripted body

**CAUTION** Every recipe in `tech/` predates 2026-09-23 and was proven against a
script-spawned `character` driven by `body-*` verbs. The realm now seats an agent
as a **real multiplayer player** in its own client container, and renamed those
verbs accordingly (`body-move` → `move`, `body-mine` → `mine`). Read the recipes
for their measurements and geometry, which still hold. Re-derive any verb name
from `describe`.

Three findings in `tech/` are obsolete because a seat is a real player:

- Mining is no longer instant and scripted. The engine extracts at the game's
  own rate, so `manual-basics` §3 overstates what one call yields.
- Crafting counts toward production statistics, so craft-item research triggers
  now fire on their own. The `research` cheat is no longer the only path.
- A seat carries its own inventory. Nothing a previous body held survived.
