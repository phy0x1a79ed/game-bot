# Arena protocol

## Purpose & Contents

This file is the source of truth for the two message contracts of the chess arena:

- **Contract A** covers the game master and a bot.
- **Contract B** covers the CLI and a game master session.

`protocol.py` implements exactly these messages. Change this file and `protocol.py` together. A field that exists in one but not the other breaks bots silently, because both sides ignore unknown fields.

## Common rules

- The transport is WebSocket over a Unix domain socket. The host part of the handshake URI is nominal.
- Every frame is one UTF-8 JSON text frame. Binary frames are errors.
- Both sides ignore unknown fields.
- Moves are UCI strings, for example `e2e4` or `e7e8q`. Positions are FEN strings.
- A socket path must be 107 bytes or shorter.

**CAUTION:** Unix sockets do not work on Windows-mounted paths such as `/mnt/c` under WSL. Keep socket directories under `/tmp`.

## Contract A: game master and bot

Protocol version 1.

### Transport

- The bot is the server. It listens on the path given by `--socket`.
- The game master is the client. It connects with the URI `ws://localhost/bot`.
- The game master drives every exchange. A bot only answers.
- A bot serves one game master connection. It exits after `bye` or a disconnect.
- A bot exits when no game master connects within 30 s.
- `ply` counts the moves played in the current game, starting at 0. It is not derived from the FEN move counters.

### Game master to bot

| type | fields | meaning |
|---|---|---|
| `hello` | `protocol`, `session`, `color` | The first frame after the connection opens. |
| `game_start` | `game_id`, `color`, `opponent`, `initial_fen`, `move_timeout_s`, `max_attempts` | A new game begins. A series sends one per game, and colors can change between games. |
| `move_request` | `game_id`, `ply`, `fen`, `moves`, `legal_moves`, `deadline_s` | The bot is to move. `moves` is the full history from `initial_fen`. The frame carries the whole state, so a stateless bot works. |
| `move_rejected` | `game_id`, `ply`, `move`, `reason`, `legal_moves`, `attempts_left`, `remaining_s` | The last move was invalid. `reason` is `illegal` or `malformed`. The request stays open. |
| `game_over` | `game_id`, `result`, `reason` | The game ended. `result` is `1-0`, `0-1`, or `1/2-1/2`. |
| `bye` | none | The session ends. The game master closes the connection. |

`game_over.reason` is one of:

- `checkmate`, `stalemate`, `insufficient_material`, `seventyfive_moves`, `fivefold_repetition`: automatic endings from the rules.
- `max_plies`: the game reached the ply cap. The result is a draw.
- `resignation`, `illegal_move`, `timeout`, `disconnect`, `protocol_error`: forfeits. The other side wins.
- `stopped`: the session shut down mid-game. The result is a draw.

### Bot to game master

| type | fields | meaning |
|---|---|---|
| `ready` | `protocol`, `name`, `version` | The reply to `hello`. |
| `move` | `game_id`, `ply`, `move` | The reply to `move_request` or `move_rejected`. |
| `resign` | `game_id`, `ply` | The bot gives up the game. |

### Rules

1. The bot must reply `ready` within 10 s of the connection opening. The game master retries the connection until the bot's socket exists, within the same 10 s.
2. `deadline_s` runs from the moment the game master sends `move_request`. Retries after `move_rejected` share that deadline. A bot without a valid move in time forfeits with `timeout`.
3. An illegal or malformed `move` gets `move_rejected` with the legal moves. After `max_attempts` invalid moves the bot forfeits with `illegal_move`.
4. The game master ignores a `move` or `resign` whose `game_id` or `ply` is stale. The deadline keeps running.
5. Malformed JSON or an unexpected message type forfeits with `protocol_error`. A dropped connection forfeits with `disconnect`.
6. Nobody claims draws. Threefold repetition and the fifty-move rule do not end a game. Only the automatic endings and the `max_plies` cap do.

### Example exchange

1. GM: `{"type":"hello","protocol":1,"session":"k3x9a","color":"white"}`
2. Bot: `{"type":"ready","protocol":1,"name":"naive","version":"1"}`
3. GM: `{"type":"game_start","game_id":"k3x9a-1","color":"white","opponent":"simple","initial_fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","move_timeout_s":5,"max_attempts":5}`
4. GM: `{"type":"move_request","game_id":"k3x9a-1","ply":0,"fen":"…","moves":[],"legal_moves":["g1h3","…"],"deadline_s":5}`
5. Bot: `{"type":"move","game_id":"k3x9a-1","ply":0,"move":"e2e5"}`
6. GM: `{"type":"move_rejected","game_id":"k3x9a-1","ply":0,"move":"e2e5","reason":"illegal","legal_moves":["g1h3","…"],"attempts_left":4,"remaining_s":4.9}`
7. Bot: `{"type":"move","game_id":"k3x9a-1","ply":0,"move":"e2e4"}`

## Contract B: CLI and game master session

### Transport

- Each session listens on `/tmp/chess-arena-<uid>/<sid>/gm.sock`. The directory has mode 0700.
- The client connects with the URI `ws://localhost/control`.
- Each call opens a connection, sends one request, reads one response, and closes.

### Frames

- Request: `{"id", "method", "params"}`.
- Success: `{"id", "ok": true, "result"}`.
- Failure: `{"id", "ok": false, "error": {"code", "message"}}`.

### Session lifecycle

A session holds one game or one series. Its first request must be an init method, `start_game` or `load`. A session accepts exactly one init. Before init, every other method except `status`, `list_saves`, and `shutdown` fails with `no_game`. A second init fails with `already_initialized`. A new game always needs a new session.

### Methods

| method | params | result |
|---|---|---|
| `start_game` (init) | `white`, `black`, `games`=1, `alternate`=true, `fen`, `move_timeout_s`=5, `max_attempts`=5, `max_plies`=500, `seed` | `{sid}`. Spawns the bots and begins play in the background. |
| `load` (init) | `name`, `play`=false | `{sid}`. Restores a save with its bots and settings. Phase stays `stopped` unless `play` is true. The save file is never modified. |
| `status` | none | `sid`, `pid`, `uptime_s`, `phase`, `game_id`, `game_index`, `games`, `score`, `players`, `bots` (name, color, pid, alive). |
| `state` | none | `game_id`, `fen`, `turn`, `ply`, `legal_moves`, `last_move`, `outcome`. |
| `history` | `game_id` (optional) | `game_id`, `players`, `initial_fen`, `moves` (`ply`, `side`, `uci`, `san`, `think_s`), `rejected` (`ply`, `side`, `move`, `reason`), `outcome`. |
| `stop` | none | `{phase}`. Halts play after the move in flight. |
| `resume` | none | `{phase}`. Continues a `stopped` session. |
| `save` | `name`, `overwrite`=false | `{path}`. Writes `data/chess/saves/<name>.json` and `<name>.pgn`. |
| `list_saves` | none | `{saves}`, the save names. |
| `shutdown` | none | `{}`. Ends play, sends `bye` to the bots, removes the session directory, and exits the process. |

`phase` is one of `idle` (before init), `running`, `stopped`, or `finished`.

A save name matches `[A-Za-z0-9_.-]+`.

### Error codes

| code | when |
|---|---|
| `busy` | The request conflicts with the current phase, for example `resume` while running. |
| `not_found` | The save or `game_id` does not exist. |
| `invalid_params` | A parameter is missing, has the wrong type, or the frame is malformed. |
| `exists` | `save` would overwrite a file and `overwrite` is false. |
| `no_game` | The session has not been initialized. |
| `already_initialized` | A second init method was sent. |
| `bot_failed` | A bot did not start or did not send `ready`. |
| `unknown_method` | The method name is not in the table above. |
| `internal` | The game master raised an unexpected error. |
