# Chess bot arena

## Purpose & Contents

This file gets a newcomer from a clone to a first bot, and to a game in a browser. It covers setup, writing a bot, watching games, sharing bots, and using the arena from another program. Command options live in `dev/chess.sh --help` and `dev/chess.sh <command> --help`. The message contracts live in `src/chess/coms/PROTOCOL.md`. Run every command from the repo root.

## What the arena is

A game master session plays a series of chess games between two players. Each bot runs as its own process and answers move requests over WebSocket on a Unix socket. The game master owns the real game and rejects invalid moves. Sessions run in the background, so several run at the same time.

A player name that starts with `@`, such as `@human`, is an external seat. No process runs for it. A person plays it from the browser page or the CLI, with no time limit by default.

The `src/chess/game` package holds the rules. The game master and the bots both use it, so a bot can look ahead without implementing chess.

## Quickstart

The arena runs on Linux, macOS and WSL. On Windows, use WSL. You need Python 3.11 or newer and git.

1. Clone the repo and `cd` into it.
2. Run `dev/chess.sh env`. It builds `.venv` from the newest `python3.1x` on PATH. Set `PYTHON=/path/to/python3` to pick another. With mamba on PATH and no `.venv`, it builds the conda envs from `envs/` instead.
3. Run `dev/chess.sh test`.
4. Run `dev/chess.sh match simple naive --games 4`. It prints each game and the score.

## Write a bot

1. Run `dev/chess.sh new-bot <name>`. It creates `src/chess/ai_<name>/__main__.py` from a commented template.
2. Edit `choose_move` in that file.
3. Run `dev/chess.sh match <name> naive`.

`match` alternates colors. When your bot loses a game by its own fault, `match` names the reason and the bot's log file. A crash in `choose_move` resigns the game and leaves a traceback in that log.

A bot subclasses `coms.bot.Bot` and overrides these hooks. Plain hooks run in a worker thread, so a long search does not block the connection.

| hook | called | return |
|---|---|---|
| `choose_move(request)` | on each move request | a UCI move from `request.legal_moves`, or `None` to resign |
| `on_game_start(start)` | before each game | nothing |
| `on_move_rejected(rejected, request)` | after an invalid move | a new move. The default calls `choose_move` again. |
| `on_game_over(over)` | after each game | nothing |

`request` carries `fen`, `moves`, `legal_moves`, `ply` and `deadline_s`. `self.game` is the current `game_start`, with `color` and `initial_fen`. `self.rng` is a `random.Random` that `--seed` seeds.

`GameState.from_request(request, self.game.initial_fen)` rebuilds the position. The main `GameState` members:

| member | gives |
|---|---|
| `legal_moves()`, `is_legal(uci)` | the legal UCI moves |
| `apply(uci)` | a new state after the move. The original is unchanged. |
| `push(uci)`, `pop()` | play and take back a move in place, for fast search |
| `turn`, `ply`, `fen`, `moves`, `last_move` | the position |
| `piece_at(square)`, `pieces()` | pieces, with `color`, `kind` and `symbol` |
| `is_capture(uci)`, `gives_check(uci)`, `is_check()`, `san(uci)` | move facts |
| `outcome()` | `None`, or an `Outcome` with `result`, `reason` and `winner` |

`src/chess/ai_naive` is the smallest bot. `src/chess/ai_simple` searches with `push` and `pop`. `src/chess/game/state.py` has the full API.

A bot that needs its own dependencies gets `envs/chess-<name>.yml`. The game master then starts that bot in the conda env of the same name, which needs mamba.

**CAUTION:** Only `src/chess/game` imports python-chess. Keep `src/chess` free of `__init__.py` and put `src/chess` itself on `PYTHONPATH`. Otherwise `import chess` resolves to this folder and shadows python-chess.

## Watch in a browser

1. Run `dev/chess.sh ui`. It serves the page on `http://127.0.0.1:8765/`.
2. Open that URL.
3. In another terminal, run `dev/chess.sh match <a> <b> --ui`. It plays at 0.5 s per ply and prints a link to the game.

The page also starts games, including against you: name a seat `@<you>` and click to move. It pauses, resumes and steps a game, sets its pace, and saves it. It replays saves and finished sessions. A replay plays by itself at the delay set on its slider. The space bar plays and pauses it.

Under WSL, a Windows browser reaches `127.0.0.1` through WSL's localhost forwarding.

The page source is in `src/chess/web`. The built page in `src/chess/web/dist` is committed, so using the page needs no node. After you change the source, run `dev/chess.sh web-build`, which needs node and npm, and commit `dist` with it.

## Share bots

Each bot is one folder, `src/chess/ai_<name>`. Pick a name nobody else uses.

1. Create a branch for your bot.
2. Commit only your bot's folder on it.
3. Push the branch and merge it into `main`.
4. Pull `main` to get the other bots. Then play them: `dev/chess.sh match <yours> <theirs>`.

**CAUTION:** A bot from someone else is arbitrary code. It runs with your user's rights when a game starts it. Read a bot's code before you play it.

## Run a session by hand

`match` covers the common case. To drive a session step by step:

1. Start it: `dev/chess.sh start --white simple --black naive --games 4`. It prints the session id.
2. Inspect it with `status`, `state` and `history`.
3. End it: `dev/chess.sh kill <sid>`.

To play from the terminal, start with `--white @human` and play each move with `dev/chess.sh move <uci>`.

Each session writes its logs, a frame log, a PGN per game and `record.json` to `data/chess/sessions/<sid>/`. `record.json` has the save format, so a finished session replays like a save. Saves go to `data/chess/saves/`.

## Use it from another program

Install the arena editable into the program's env: `pip install -e <checkout>`. Import `game_master.sessions` to find, create, call, watch and end sessions. Import `game_master.verbs` for the same operations the browser page uses. Import `game_master.saves` to read saves and session records without a session.

**CAUTION:** Install editable only. Sessions and bots start from the checkout's `src/chess`, and `game_master.paths` refuses to import without it. Set `CHESS_ARENA_ROOT` to run the arena from a different checkout.

`CHESS_ARENA_DATA` and `CHESS_ARENA_RUNTIME` relocate the data and the socket directories. Set them before the first import of `game_master`. Every client of a session must agree on both, or it does not see the session. Sessions pass them on to their bots.

Tag the sessions a program starts with `labels`, so it finds its own sessions again after a restart. Give them `idle_timeout_s`, so an abandoned game saves itself and exits.
