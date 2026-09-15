import dataclasses
import json

import pytest

from coms import rpc
from coms.protocol import (
    FROM_BOT,
    TO_BOT,
    Bye,
    GameOver,
    GameStart,
    Hello,
    Move,
    MoveRejected,
    MoveRequest,
    ProtocolError,
    Ready,
    Request,
    Resign,
    Response,
    RpcError,
    decode,
    decode_request,
    decode_response,
    encode,
    encode_request,
    encode_response,
)
from helpers import short_dir

SAMPLES = [
    Hello(session="ab12c", color="white"),
    GameStart("g-1", "black", "naive", "8/8/8/4k3/8/8/8/4K3 w - - 0 1", 5.0, 5),
    MoveRequest("g-1", 3, "fen", ["e2e4", "e7e5", "g1f3"], ["b8c6", "g8f6"], 2.5),
    MoveRejected("g-1", 3, 42, "malformed", ["b8c6"], 4, 1.25),
    GameOver("g-1", "1/2-1/2", "stalemate"),
    Bye(),
    Ready(name="simple", version="1"),
    Move("g-1", 3, "b8c6"),
    Resign("g-1", 3),
]


def test_samples_cover_every_message():
    assert {type(m) for m in SAMPLES} == set(TO_BOT + FROM_BOT)


@pytest.mark.parametrize("msg", SAMPLES, ids=lambda m: m.type)
def test_round_trip(msg):
    assert decode(encode(msg)) == msg
    assert json.loads(encode(msg))["type"] == msg.type


@pytest.mark.parametrize("msg", [m for m in SAMPLES if dataclasses.fields(m)], ids=lambda m: m.type)
def test_missing_required_field(msg):
    required = [f.name for f in dataclasses.fields(msg) if f.default is dataclasses.MISSING]
    for name in required:
        data = json.loads(encode(msg))
        del data[name]
        with pytest.raises(ProtocolError, match=name):
            decode(json.dumps(data))


@pytest.mark.parametrize(
    "frame",
    [
        {"type": "move", "game_id": "g", "ply": "3", "move": "e2e4"},
        {"type": "move", "game_id": "g", "ply": True, "move": "e2e4"},
        {"type": "move_request", "game_id": "g", "ply": 0, "fen": "f", "moves": [1],
         "legal_moves": [], "deadline_s": 1},
        {"type": "game_start", "game_id": "g", "color": "white", "opponent": "x",
         "initial_fen": "f", "move_timeout_s": False, "max_attempts": 1},
    ],
)
def test_bad_field_type(frame):
    with pytest.raises(ProtocolError, match="bad value"):
        decode(json.dumps(frame))


def test_unknown_fields_are_ignored():
    assert decode('{"type": "resign", "game_id": "g", "ply": 1, "why": "lost"}') == Resign("g", 1)


@pytest.mark.parametrize("text", ["not json", "[1]", '{"type": 3}', '{"type": "nope"}', b"{}"])
def test_bad_frames(text):
    with pytest.raises(ProtocolError):
        decode(text)


def test_expect_limits_direction():
    with pytest.raises(ProtocolError, match="unexpected"):
        decode(encode(Bye()), expect=FROM_BOT)


def test_control_frames_round_trip():
    req = Request("1", "save", {"name": "x"})
    assert decode_request(encode_request(req)) == req
    ok = Response("1", True, result={"sid": "abcde"})
    assert decode_response(encode_response(ok)) == ok
    err = Response("1", False, error={"code": "exists", "message": "m"})
    assert decode_response(encode_response(err)) == err
    with pytest.raises(ProtocolError):
        decode_response('{"id": "1", "ok": false, "error": {"message": "no code"}}')


async def test_rpc_call_and_errors():
    async def dispatch(method, params):
        if method == "status":
            return {"echo": params}
        if method == "save":
            raise RpcError("exists", "already there")
        raise RuntimeError("boom")

    path = short_dir() / "gm.sock"
    server = await rpc.serve_control(path, dispatch)
    try:
        assert await rpc.call(path, "status", {"a": 1}) == {"echo": {"a": 1}}
        for method, code in [("save", "exists"), ("stop", "internal"), ("fly", "unknown_method")]:
            with pytest.raises(RpcError) as info:
                await rpc.call(path, method)
            assert info.value.code == code
    finally:
        server.close()
        await server.wait_closed()
    with pytest.raises(ConnectionError):
        await rpc.call(path.parent / "missing.sock", "status")
