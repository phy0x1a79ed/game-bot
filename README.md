# game-bot

A CLI bridge that lets agentic LLMs drive video games, split into a persistent
game-agnostic coordinator (**Nexus**) and per-game adapters (**Effector**, the
"claw"). The agent-facing CLI is deferred; this repo currently ships the two
backend halves plus a self-contained Factorio server, proven with one capability:
the **`world` command group — `new` / `save` / `load`**.

## Architecture

```
  agent (curl stand-in)
        │  HTTP  /schema  /invoke  /status
        ▼
   ┌─────────┐   WS /effector    ┌──────────────────┐   HTTP   ┌────────────────────────┐
   │  Nexus  │◄─────────────────►│ Factorio Effector│─────────►│  Appliance (container) │
   │ :12141  │  register + hold  │   (pure client)  │  control │  supervisor owns engine│
   └─────────┘                   └──────────────────┘  :12142  │  game :12140/udp       │
                                                                └────────────────────────┘
```

- **Nexus** (`nexus/`) — game-agnostic. An Effector registers a capability
  schema over a held WebSocket; agent-facing HTTP discovers (`/schema`) and
  drives (`/invoke`) it. The Nexus owns no game knowledge — it validates invokes
  only against the registered schema and relays them over the held channel.
- **Effector** (`effectors/factorio/`) — the per-game claw. A pure requesting
  client: registers the `world` schema, forwards each `world.*` invoke to the
  appliance control surface. Holds no engine PID, issues no `docker run`.
- **Appliance** (`effectors/factorio/server/`) — a self-contained container. Its
  supervisor owns the Factorio engine process, drives the console for live saves,
  and re-execs the engine in place for `new`/`load` (the container stays up).

`save` is a live console action (seamless for connected players). `new`/`load`
relaunch the engine — a connected Steam player drops to menu and reconnects,
exactly as clicking New/Load in the desktop UI. Saves are standard `.zip`s,
interchangeable with a desktop/Steam client.

**Saves are sacred.** The engine always runs on a private scratch file
(`_active.zip`), never on a named save directly, so a named save is an immutable
snapshot: nothing writes `<name>.zip` except an explicit `save <name>`. Loading a
save can never advance it; naming a save can never disturb another. `save`
requires a name and refuses to clobber an existing one unless `overwrite:true`.
`new`/`load` discard the live world's unsaved progress (as the desktop UI does) —
snapshot first to keep it.

RCON is deliberately **not** used in this slice; it returns in a later phase for
live in-game control and agent gameplay scripting.

## Running the slice

Prereqs: Docker (Desktop or CE) and a `game-bot` mamba env
(`mamba create -n game-bot python=3.12 fastapi uvicorn httpx websockets`).

```bash
# 1. Appliance (builds the image, pins Factorio 2.0.77 + Space Age)
cd effectors/factorio/server && docker compose up -d --build

# 2. Nexus
cd ../../..                  # repo root
mamba run -n game-bot uvicorn nexus.app:app --host 127.0.0.1 --port 12141

# 3. Effector (separate shell)
mamba run -n game-bot python -m effectors.factorio.effector
```

Drive it (agent stand-in):

```bash
J='-H Content-Type:application/json'   # /invoke is JSON; without this curl form-encodes and FastAPI 422s
curl -s localhost:12141/schema | python3 -m json.tool          # discover
curl -s $J -XPOST localhost:12141/invoke -d '{"action":"world.save","args":{"name":"ckpt"}}'
curl -s $J -XPOST localhost:12141/invoke -d '{"action":"world.save","args":{"name":"ckpt","overwrite":true}}'
curl -s $J -XPOST localhost:12141/invoke -d '{"action":"world.new","args":{"seed":424242}}'
curl -s $J -XPOST localhost:12141/invoke -d '{"action":"world.load","args":{"name":"ckpt"}}'
```

## Joining from a Steam client

The appliance runs the **latest stable** Factorio headless (2.0.77) with Space
Age — version must match your desktop client. In Factorio:
*Multiplayer → Connect to address*, try in order:

1. `localhost:12140` — Docker Desktop publishes the port to the Windows host.
2. `<WSL-eth0-IP>:12140` — e.g. the address from `ip -4 addr show eth0`.

Factorio multiplayer is **UDP-only** on the game port. A `netsh portproxy`
Windows→WSL forward is TCP-only and will **not** carry game traffic; rely on
Docker Desktop's own port publishing (option 1) or a UDP forward / WSL mirrored
networking if option 2 is needed.

## Ports

| Port        | Proto | Who          | Purpose                          |
|-------------|-------|--------------|----------------------------------|
| `12140`     | UDP   | game clients | Factorio game traffic (Steam)    |
| `12141`     | TCP   | agent        | Nexus HTTP (`/schema`,`/invoke`) |
| `12142`     | TCP   | Effector     | appliance control surface        |
