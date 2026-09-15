# Chess bot arena

## Purpose & Contents

This file introduces the chess arena: what it is for, how to run it, how another program uses it, and how to add a bot. It points at the sources of truth for everything else. Command options live in `dev/chess.sh --help`. The message contracts live in `src/chess/coms/PROTOCOL.md`.

## What the arena is

A game master session plays a series of chess games between two players. Each bot runs as its own process and answers move requests over WebSocket on a Unix socket. The game master owns the real game and rejects invalid moves with the legal move set. The CLI starts sessions in the background and sends them one control request per call, so several sessions run at the same time.

A player name that starts with `@`, such as `@human`, is an external seat. No process runs for it. A person or an agent plays it through control calls, with no time limit by default. Other programs can also watch a session's events live. `src/chess/coms/PROTOCOL.md` defines both.

The `src/chess/game` package holds the rules. The game master and the bots both use it, so a bot can play out hypothetical lines without implementing chess.

**CAUTION:** Only `src/chess/game` imports python-chess. Keep `src/chess` free of `__init__.py` and put `src/chess` itself on `PYTHONPATH`. Otherwise `import chess` resolves to this folder and shadows python-chess.

## Run it

1. Create the conda env: `dev/chess.sh env`.
2. Start a session: `dev/chess.sh start --white simple --black naive --games 4`. The command prints the new session id.
3. Inspect the session with `status`, `state` and `history`. List every command with `dev/chess.sh --help`.
4. End the session: `dev/chess.sh kill <sid>`.

To play a bot yourself, start with `--white @human`. Then play each move with `dev/chess.sh move <uci>`.

Run the tests with `dev/chess.sh test`.

Each session writes its logs, a frame log, a PGN per game and `record.json` to `data/chess/sessions/<sid>/`. `record.json` has the save format, so a finished session can be replayed like a save. Saves go to `data/chess/saves/`.

## Use it from another program

Install the arena editable into the program's env: `mamba run -n <env> pip install -e <checkout>`. Import `game_master.sessions` to find, create, call, watch and end sessions. Import `game_master.saves` to read saves and session records without a daemon.

**CAUTION:** Install editable only. Daemons and bots start from the checkout's `src/chess`, and `game_master.paths` refuses to import without it. Set `CHESS_ARENA_ROOT` to run the arena from a different checkout.

`CHESS_ARENA_DATA` and `CHESS_ARENA_RUNTIME` relocate the data and the socket directories. Set them before the first import of `game_master`. Every client of a session must agree on both, or it does not see the session. Sessions pass them on to their daemons and bots.

Tag the sessions a program starts with `labels`, so it finds its own sessions again after a restart. Give them `idle_timeout_s`, so an abandoned game saves itself and exits.

## Add a bot

1. Create `src/chess/ai_<name>/__main__.py`. The game master finds a bot by this path.
2. Subclass `coms.bot.Bot` and override `choose_move`. Return a UCI move from `request.legal_moves`, or `None` to resign.
3. Call `<YourBot>.main()` under `if __name__ == "__main__":`.
4. Play it: `dev/chess.sh start --white <name> --black naive`.

`src/chess/ai_naive` is the smallest template. `src/chess/ai_simple` shows a search on the `game` library.

A bot that needs its own dependencies gets `envs/chess-<name>.yml`. The game master then starts that bot through `mamba run` in the env of the same name. Run `dev/chess.sh env` to create it.
