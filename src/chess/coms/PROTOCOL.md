# Arena protocol

## Purpose & Contents

This file is the source of truth for the three message contracts of the chess arena:

- **Contract A** covers the game master and a bot.
- **Contract B** covers a client, such as the CLI, and a game master session.
- **Contract C** covers the browser page and the viewer, `dev/chess.sh ui`.

`protocol.py` implements exactly the messages of A and B. `game_master/verbs.py` and `viewer/server.py` implement C. Change this file and its implementation together. A field that exists in one but not the other breaks a peer silently, because every side ignores unknown fields.

## Common rules for A and B

- The transport is WebSocket over a Unix domain socket. The host part of the handshake URI is nominal.
- Every frame is one UTF-8 JSON text frame. Binary frames are errors.
- Both sides ignore unknown fields.
- Moves are UCI strings, for example `e2e4` or `e7e8q`. Positions are FEN strings.
- A socket path must be 103 bytes or shorter, the macOS limit.

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

## Contract B: client and game master session

### Transport

- Each session listens on `/tmp/chess-arena-<uid>/<sid>/gm.sock`. The directory has mode 0700.
- The client connects with the URI `ws://localhost/control`.
- Each call opens a connection, sends one request, reads one response, and closes. `watch` is the exception: the connection stays open for event frames.

### Frames

- Request: `{"id", "method", "params"}`.
- Success: `{"id", "ok": true, "result"}`.
- Failure: `{"id", "ok": false, "error": {"code", "message"}}`.

### Session lifecycle

A session holds one game or one series. Its first request must be an init method, `start_game` or `load`. A session accepts exactly one init. Before init, every other method except `status`, `list_saves`, and `shutdown` fails with `no_game`. A second init fails with `already_initialized`. A new game always needs a new session.

### Methods

| method | params | result |
|---|---|---|
| `start_game` (init) | `white`, `black`, `games`=1, `alternate`=true, `fen`, `move_timeout_s`=5, `seat_timeout_s`, `max_attempts`=5, `max_plies`=500, `seed` | `{sid}`. Spawns the bots and begins play in the background. `min_ply_s`=0 is the pace. Also takes the lifetime params. |
| `load` (init) | `name`, `play`=false | `{sid}`. Restores a save with its bots, settings and labels. Phase stays `stopped` unless `play` is true. The save file is never modified. Also takes the lifetime params. |
| `status` | none | `sid`, `pid`, `uptime_s`, `phase`, `watchers`, `game_id`, `game_index`, `games`, `score`, `min_ply_s`, `labels`, `bots` (name, color, pid, alive, external). |
| `state` | none | `game_id`, `fen`, `turn`, `ply`, `legal_moves`, `last_move`, `outcome`, `awaiting`. |
| `history` | `game_id` (optional), `fens`=false | `game_id`, `players`, `initial_fen`, `moves` (`ply`, `side`, `uci`, `san`, `think_s`, and `fen` after the move when `fens`), `rejected` (`ply`, `side`, `move`, `reason`), `outcome`. |
| `stop` | none | `{phase}`. Halts play after the move in flight. |
| `resume` | none | `{phase}`. Continues a `stopped` session. |
| `save` | `name`, `overwrite`=false | `{path}`. Writes `data/chess/saves/<name>.json` and `<name>.pgn`. |
| `list_saves` | none | `{saves}`, the save names. |
| `submit_move` | `color`, `game_id`, `ply`, `move` | `{accepted: true, san}`, or `{accepted: false, reason, legal_moves}`. Plays an external seat's move. |
| `resign` | `color` | `{result, reason}`. Resigns the current game for an external seat, on either turn and in any phase. |
| `set_pace` | `min_ply_s` | `{min_ply_s}`. Changes the pace at once, including a hold in progress. |
| `step` | none | `{phase, ply}`. Plays exactly one ply from `stopped`, without the pace hold. Fails with `busy` when an external seat is to move. |
| `watch` | `since_seq` (optional) | `{seq, events, snapshot}`, then event frames. See *Watch stream*. |
| `shutdown` | none | `{}`. Ends play, sends `bye` to the bots, removes the session directory, and exits the process. |

`phase` is one of `idle` (before init), `running`, `stopped`, or `finished`.

A save name matches `[A-Za-z0-9_.-]+`. Names that start with `autosave-` are reserved for the daemon.

`awaiting` is the open move request, or null: `slot`, `color`, `seat`, `external`, `game_id`, `ply`, `since` (epoch seconds).

### External seats

A player name that matches `@[a-z0-9_]+` is an external seat. No process is spawned for it. A person or an agent plays it with `submit_move`, which names the open request by `game_id` and `ply`.

- `seat_timeout_s` is the time limit per slot, `[slot0, slot1]`. Slot 0 is `white` in the first game. Keys are slots because `alternate` swaps colors. It defaults to `move_timeout_s` for a bot and null (no limit) for an external seat. A bot slot must have a limit.
- An invalid submitted move is recorded in `rejected` and never counts toward `max_attempts`.
- `stop` ends an external seat's open request at once. `resume` opens it again. For a bot seat `stop` still waits for the move in flight.

### Session lifetime

Both init methods take these optional params. Without them a session runs until `shutdown`.

- `labels`: up to 16 keys matching `[a-z][a-z0-9_]*`, each mapped to a string. `status` echoes them and saves keep them. `load` merges its labels over the saved ones. A client uses labels to find its own sessions again.
- `idle_timeout_s`: the session saves itself as `autosave-<sid>` and shuts down after this long without a control call or a watcher. Only a session that waits counts as idle: a stopped one, or one with an external seat. A running bot series is never idle.
- `finished_linger_s`: a finished session shuts down after this long without a control call or a watcher.

The daemon enforces both timeouts, so they hold when no client is connected.

### Pace

`min_ply_s` holds a bot's landed move until that many seconds have passed since the previous ply. The bot's think time counts toward the hold, and the hold never shortens or extends a move deadline. Moves from external seats are not held. `stop` and `resign` end a hold at once.

### Watch stream

`watch` subscribes to the session's events. The response is followed by one frame per event, `{"event", "seq", "data"}`, until either side closes. `seq` increases by one per event within a daemon's life.

The response carries `seq`, the number of the last event already covered, plus exactly one of:

- `events`: the missed events after `since_seq`, when all of them are still buffered.
- `snapshot`: `{status, state, history}` at `seq`, when `since_seq` is absent or its events are gone.

A watcher that falls too far behind gets one `resync` frame and the server closes the connection. Watch again without `since_seq`.

| event | data |
|---|---|
| `phase` | `phase`, `note` |
| `game_start` | `game_id`, `index`, `players`, `white_slot`, `initial_fen` |
| `turn` | The `awaiting` fields, plus `fen`, `legal_moves`, `deadline_s`. Sent for bots and external seats. |
| `move` | `game_id`, `ply`, `side`, `uci`, `san`, `fen`, `think_s` |
| `rejected` | `game_id`, `ply`, `side`, `move`, `reason` |
| `game_over` | `game_id`, `result`, `reason`, `plies`, `score` |
| `pace` | `min_ply_s` |
| `resync` | none |

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
| `not_your_turn` | `submit_move` names a color with no open request, or a bot's color. |
| `stale` | `submit_move` names a `game_id` or `ply` that is not the position in play. |

## Contract C: browser and viewer

### Transport

- The viewer serves the page and one WebSocket on one TCP port, `127.0.0.1:8765` by default.
- A GET for any path other than `/ws` returns a file of `src/chess/web/dist/`. An unknown path returns `index.html`.
- The page connects to `ws` relative to its own URL. The viewer refuses the upgrade with 403 when the `Origin` host differs from `Host`, so another site's page cannot drive the arena.
- One connection carries every call and every event. The page sends each request without waiting for the previous reply.

### Frames

- Request: `{"id", "verb", "args"}`.
- Success: `{"id", "ok": true, "result"}`.
- Failure: `{"id", "ok": false, "error": {"code", "message"}}`.
- Event: `{"event": {"session_id", "kind", "seq", "data"}}`. An event has no `id`.

### Verbs

Every verb that names a session takes `session_id`. Most verbs map one to one onto a Contract B method, and `game_master/verbs.py` implements them without a transport.

| verb | args | result |
|---|---|---|
| `bots` | none | `{bots}`, the names of `src/chess/ai_*` bots. |
| `start` | The `start_game` params and lifetime params, plus `owner`="viewer". Or `load` (a save name) and `play`. | `{session_id, mode}`. `mode` is `pvb` when a seat is external, else `bvb`. See *Defaults*. |
| `kill` | `session_id` | `{killed: true, session_id}` |
| `rematch` | `session_id` | `{session_id, mode, previous}`. Kills the session and starts a new one with the same players, settings and owner, without the seed. |
| `status` | `session_id` (optional) | `{sessions}`, the Contract B status of one or of every live session. |
| `observe` | `session_id` | `{status, state}` |
| `history` | `session_id`, `game_id`, `fens` | The Contract B `history` result. |
| `snapshot` | `session_id` | `{seq, snapshot}`, as a `watch` without `since_seq`. |
| `saves` | none | `{saves, records}`: a summary of each save and of each session record. |
| `replay` | Exactly one of `name` and `session_id`, plus `game_id` | `{game_ids, score, labels}` plus the `history` of the chosen game with `fens`. Needs no live session. |
| `move` | `session_id`, `move`, `ply` | The `submit_move` result for the external seat to move. A `ply` that is not the open request's fails with `stale`. |
| `resign` | `session_id`, `color` | `{result, reason}`. `color` defaults to the only external seat. |
| `pause`, `resume`, `step` | `session_id` | The results of `stop`, `resume` and `step`. |
| `set_pace` | `session_id`, `min_ply_s` | `{min_ply_s}` |
| `save` | `session_id`, `name`, `overwrite` | `{path}` |
| `follow` | `session_id` | `{seq, snapshot}`. Starts the session's events for this connection. |
| `unfollow` | `session_id` | `{following: false}` |

### Defaults

The viewer starts sessions that clean up after themselves:

- `idle_timeout_s` defaults to 1800 and `finished_linger_s` to 900.
- A bot-only series defaults to `min_ply_s`=0.5, so a person can follow it.
- `owner` becomes the `owner` label, and the `mode` label records `mode`.
- A loaded save plays on unless its series is finished or `play` is false.

### Follows

`follow` subscribes the connection to one session's events. Each event arrives as `{"event": {...}}` with the Contract B event name as `kind`, and its `seq` and `data`. After a `resync` event, `follow` again for a fresh snapshot.

The viewer holds one Contract B `watch` per session that at least one connection follows. It closes that watch when the last follower unfollows or disconnects. A session that no browser shows therefore has `watchers` 0, so its idle and linger timeouts fire.

**CAUTION:** A browser tab left open on a session keeps that session alive.

Three `kind`s go to every connection, whether or not it follows the session. Their `seq` is null.

| kind | data | when |
|---|---|---|
| `session_started` | `mode` | A `start` or `rematch` through this viewer made a session. |
| `session_ended` | none | A `kill` through this viewer, or the end of a followed session's watch. |
| `saved` | `name` | A `save` through this viewer. |

A session started or ended elsewhere, such as by the CLI, sends no lobby event. The page polls `status` for those.

The viewer queues at most 5000 frames per connection. A connection that falls further behind is closed with code 1008.

### Error codes

Contract C passes on the Contract B codes of the method behind a verb, and adds these:

| code | when |
|---|---|
| `not_running` | No live session has this `session_id`. |
| `not_found` | `start` names an unknown save, `rematch` a session without start settings, or `replay` an unknown save, record or game. |
| `not_your_turn` | `move` finds no external seat to move. |
| `start_failed` | The session did not start, for a reason without its own code. |
