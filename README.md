# game-bot

## Purpose & Contents

This repo holds bot harnesses for several games. A harness runs a game and lets bots play it, whether a bot is a hand-written program or an LLM agent. This file lists the games, where each one lives, and the conventions they share. Each game's own README covers its setup and use.

## Games

| game | where | state |
|---|---|---|
| Chess | `src/chess` on `main`. Start at [`src/chess/README.md`](src/chess/README.md). | Playable. Bots play series in a local arena, and a browser page shows the games. |
| Factorio | branch `feat/factorio` | Research. The branch keeps the first harness prototype and the notes and scripts from playing through its successor. |
| Web games | branch `feat/web` | Design only. The branch holds the spec. |

## Layout

Each game keeps to its own paths, so games do not collide on one branch.

- `src/<game>/` holds the harness, its bots, its tests and its README.
- `dev/<game>.sh` is the game's one entry point.
- `envs/<game>*.yml` holds conda env specs for a game that uses them.
- `data/<game>/` holds what a game writes at run time.
- `research/` holds notes from playing.

**CAUTION:** `pyproject.toml` belongs to chess today. A second Python game on `main` needs its own package config, or a shared one that names both.

## Branches

`main` holds the games that are ready to use. A game in progress lives on `feat/<game>` until it is ready. Merge it into `main` then, and add its row to the table above.

Bots for a game that is on `main` follow that game's README. For chess, that is one branch per bot, merged into `main`.

**CAUTION:** A bot from someone else is arbitrary code. It runs with your user's rights. Read a bot's code before you run it.
