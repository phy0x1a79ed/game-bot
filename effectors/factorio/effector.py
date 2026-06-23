"""Factorio Effector entrypoint.

Connects to the Nexus, registers the `world` command group, and relays each
`world.*` invoke to the appliance control surface (HTTP). Reconnects to the
Nexus if the channel drops.

Run:
    mamba run -n game-bot python -m effectors.factorio.effector
Env:
    NEXUS_WS         ws://127.0.0.1:12141/effector
    APPLIANCE_URL    http://127.0.0.1:12142
"""

import asyncio
import json
import os

import httpx
import websockets

NEXUS_WS = os.environ.get("NEXUS_WS", "ws://127.0.0.1:12141/effector")
APPLIANCE_URL = os.environ.get("APPLIANCE_URL", "http://127.0.0.1:12142").rstrip("/")
GAME_VERSION = os.environ.get("FACTORIO_VERSION", "2.0.77")

# The Effector decides its own surface — capabilities are game-defined.
WORLD_SCHEMA = {
    "command_groups": [
        {
            "name": "world",
            "description": "World lifecycle: same outcomes as a player's New / Save / Load.",
            "commands": [
                {
                    "name": "new",
                    "description": "Generate a fresh world and start the server on it. "
                                   "Replaces the running world (connected players drop to "
                                   "menu) and discards its unsaved progress; save first to keep it.",
                    "args": {
                        "seed": {"type": "integer", "required": False,
                                 "description": "Map-gen seed; omit for random."},
                    },
                },
                {
                    "name": "save",
                    "description": "Snapshot the running world to an immutable named .zip "
                                   "(no restart, seamless for players). Named saves are never "
                                   "touched by load/new -- they are sacred.",
                    "args": {
                        "name": {"type": "string", "required": True,
                                 "description": "Name to snapshot under."},
                        "overwrite": {"type": "boolean", "required": False,
                                      "description": "Replace an existing save of this name "
                                                     "(default false; refuses to clobber otherwise)."},
                    },
                },
                {
                    "name": "load",
                    "description": "Load a named save and start the server on it. Replaces "
                                   "the running world (connected players drop to menu). The "
                                   "named save is read-only -- loading never alters it.",
                    "args": {
                        "name": {"type": "string", "required": True,
                                 "description": "Name of an existing save to load."},
                    },
                },
            ],
        }
    ]
}

_ENDPOINTS = {"new": "/new", "save": "/save", "load": "/load"}


async def handle_invoke(action: str, args: dict) -> dict:
    """Forward a world.* action to the appliance and return its structured reply."""
    group, _, command = action.partition(".")
    if group != "world":
        return {"ok": False, "error": f"unknown command group {group!r}"}
    endpoint = _ENDPOINTS.get(command)
    if endpoint is None:
        return {"ok": False, "error": f"unknown command {command!r}"}
    try:
        async with httpx.AsyncClient(timeout=300.0) as client:
            resp = await client.post(APPLIANCE_URL + endpoint, json=args or {})
        data = resp.json()
    except Exception as e:
        return {"ok": False, "error": f"appliance request failed: {e}"}
    # Appliance already returns {ok, result|error}; pass it through.
    return data


async def serve_once():
    async with websockets.connect(NEXUS_WS, ping_interval=20) as ws:
        await ws.send(json.dumps({
            "type": "register",
            "game": "factorio",
            "version": GAME_VERSION,
            "schema": WORLD_SCHEMA,
        }))
        ack = json.loads(await ws.recv())
        if not ack.get("ok"):
            raise RuntimeError(f"registration rejected: {ack}")
        print(f"[effector] registered with nexus; relaying to {APPLIANCE_URL}", flush=True)

        async for raw in ws:
            msg = json.loads(raw)
            if msg.get("type") != "invoke":
                continue
            result = await handle_invoke(msg.get("action", ""), msg.get("args") or {})
            await ws.send(json.dumps({
                "type": "result",
                "id": msg.get("id"),
                "ok": result.get("ok", True),
                "result": result.get("result"),
                "error": result.get("error"),
            }))


async def main():
    backoff = 1.0
    while True:
        try:
            await serve_once()
        except Exception as e:
            print(f"[effector] channel lost ({e}); reconnecting in {backoff:.0f}s", flush=True)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 30.0)
        else:
            backoff = 1.0


if __name__ == "__main__":
    asyncio.run(main())
