"""Nexus FastAPI app.

Surface:
  WS   /effector        Effector connects, registers, and holds the channel.
  GET  /status          Nexus + effector liveness.
  GET  /schema          Discovery: the registered schema verbatim, or no-effector.
  POST /invoke          {action, args} -> relayed to the effector -> reply.

The Nexus is strictly game-agnostic: the effector's schema is the only source
of truth for what actions exist. Single operator, single effector (last-connect
-wins) for this slice.
"""

import asyncio
import uuid

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from pydantic import BaseModel

app = FastAPI(title="Nexus", version="0.1.0")

INVOKE_TIMEOUT = 300.0


class EffectorConn:
    """A connected effector and its in-flight invoke futures."""

    def __init__(self, ws: WebSocket, game: str, version: str, schema: dict):
        self.ws = ws
        self.game = game
        self.version = version
        self.schema = schema
        self.pending: dict[str, asyncio.Future] = {}

    def actions(self) -> set[str]:
        out = set()
        for grp in self.schema.get("command_groups", []):
            gname = grp.get("name")
            for cmd in grp.get("commands", []):
                out.add(f"{gname}.{cmd.get('name')}")
        return out


# Single-effector registry for this slice.
STATE: dict[str, EffectorConn | None] = {"effector": None}


class InvokeReq(BaseModel):
    action: str
    args: dict = {}


@app.get("/status")
async def status():
    eff = STATE["effector"]
    return {
        "nexus": "up",
        "effector": None if eff is None else {
            "game": eff.game,
            "version": eff.version,
            "connected": True,
            "actions": sorted(eff.actions()),
        },
    }


@app.get("/schema")
async def schema():
    eff = STATE["effector"]
    if eff is None:
        return JSONResponse(
            {"effector": None, "detail": "no effector registered"},
            status_code=200,
        )
    return {"game": eff.game, "version": eff.version, "schema": eff.schema}


@app.post("/invoke")
async def invoke(req: InvokeReq):
    eff = STATE["effector"]
    if eff is None:
        return JSONResponse(
            {"ok": False, "error": "no effector registered"}, status_code=503
        )
    if req.action not in eff.actions():
        return JSONResponse(
            {"ok": False, "error": f"unknown action {req.action!r}"}, status_code=400
        )

    rid = uuid.uuid4().hex
    fut: asyncio.Future = asyncio.get_event_loop().create_future()
    eff.pending[rid] = fut
    try:
        await eff.ws.send_json(
            {"type": "invoke", "id": rid, "action": req.action, "args": req.args}
        )
    except Exception as e:
        eff.pending.pop(rid, None)
        return JSONResponse(
            {"ok": False, "error": f"dispatch failed: {e}"}, status_code=502
        )

    try:
        reply = await asyncio.wait_for(fut, timeout=INVOKE_TIMEOUT)
    except asyncio.TimeoutError:
        eff.pending.pop(rid, None)
        return JSONResponse({"ok": False, "error": "effector timeout"}, status_code=504)
    return reply


@app.websocket("/effector")
async def effector_ws(ws: WebSocket):
    await ws.accept()
    try:
        reg = await ws.receive_json()
    except Exception:
        await ws.close()
        return
    if reg.get("type") != "register" or "schema" not in reg:
        await ws.send_json({"type": "registered", "ok": False, "error": "bad registration"})
        await ws.close()
        return

    eff = EffectorConn(ws, reg.get("game", "unknown"), reg.get("version", "unknown"), reg["schema"])
    STATE["effector"] = eff  # last-connect-wins
    await ws.send_json({"type": "registered", "ok": True})

    try:
        while True:
            msg = await ws.receive_json()
            if msg.get("type") == "result":
                fut = eff.pending.pop(msg.get("id"), None)
                if fut is not None and not fut.done():
                    fut.set_result({
                        "ok": msg.get("ok", True),
                        "result": msg.get("result"),
                        "error": msg.get("error"),
                    })
    except WebSocketDisconnect:
        pass
    finally:
        if STATE["effector"] is eff:
            STATE["effector"] = None
        for fut in eff.pending.values():
            if not fut.done():
                fut.set_result({"ok": False, "error": "effector disconnected"})
