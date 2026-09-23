# research/basic — play Factorio through the realm, aim for automated red science

The agent plays via the **rlm-factorio** awm realm (`awm/services/rlm-factorio`,
MCP domain `rlm`, CLI `awm rlm factorio-*`). The realm is the core toolset and
is not modified here; everything learned lives in this folder.

## Watch the game

- **Address:** Factorio → *Multiplayer → Connect to address* → `localhost:12140`
  (from another LAN machine: the Windows host's LAN IP, `:12140`, UDP allowed).
- **Version:** the deployed realm pins Factorio **2.1.8** (experimental). Your
  client must be exactly 2.1.8 — Steam → Factorio → Properties → Betas.
- **DLC:** Space Age must be owned (server enables space-age, quality,
  elevated-rails, recycler).
- **Mod:** `game-bot-control` is a private mod and does not auto-sync. Copy
  `dist/game-bot-control_<ver>.zip` from this folder into
  `%APPDATA%\Factorio\mods`, enable it, restart the client.
- The agent's body is a script-spawned `character`; you spawn as your own player.
- World: `railworld-218` seed (rich ore patches, no enemy expansion).

## Use the realm from a shell

`./rlm.sh <verb> [--flag value ...]` wraps `awm rlm factorio-<verb>` with the
live session id from `.session`. `./rlm.sh observe --help` shows a verb's flags.

## Tech ladder

Each "technology" is a capability a Sonnet researcher worked out in the live
world and wrote up in `tech/<name>.md` (a recipe the main agent can replay),
with reusable scripts in `lib/`. Status is kept in `tech/INDEX.md`.
