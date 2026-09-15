"""Message types of both arena contracts. `PROTOCOL.md` is the prose source of truth.

Contract A (game master <-> bot) frames carry a `type` field and map to the
dataclasses below. Contract B (CLI <-> game master) frames are `Request` and
`Response`, without a `type` field.
"""

from __future__ import annotations

import json
import types
import typing
from dataclasses import MISSING, asdict, dataclass, field, fields
from typing import Any, ClassVar

PROTOCOL_VERSION = 1

GAME_OVER_REASONS = frozenset(
    {
        "checkmate",
        "stalemate",
        "insufficient_material",
        "seventyfive_moves",
        "fivefold_repetition",
        "max_plies",
        "resignation",
        "illegal_move",
        "timeout",
        "disconnect",
        "protocol_error",
        "stopped",
    }
)
REJECT_REASONS = frozenset({"illegal", "malformed"})
ERROR_CODES = frozenset(
    {
        "busy",
        "not_found",
        "invalid_params",
        "exists",
        "no_game",
        "already_initialized",
        "bot_failed",
        "unknown_method",
        "internal",
    }
)


class ProtocolError(ValueError):
    pass


class Message:
    type: ClassVar[str]


_REGISTRY: dict[str, type[Message]] = {}


def _message(type_name: str):
    def wrap(cls):
        cls = dataclass(frozen=True)(cls)
        cls.type = type_name
        _REGISTRY[type_name] = cls
        return cls

    return wrap


# --- game master -> bot ---


@_message("hello")
class Hello(Message):
    session: str
    color: str
    protocol: int = PROTOCOL_VERSION


@_message("game_start")
class GameStart(Message):
    game_id: str
    color: str
    opponent: str
    initial_fen: str
    move_timeout_s: float
    max_attempts: int


@_message("move_request")
class MoveRequest(Message):
    game_id: str
    ply: int
    fen: str
    moves: list[str]
    legal_moves: list[str]
    deadline_s: float


@_message("move_rejected")
class MoveRejected(Message):
    game_id: str
    ply: int
    move: Any
    reason: str
    legal_moves: list[str]
    attempts_left: int
    remaining_s: float


@_message("game_over")
class GameOver(Message):
    game_id: str
    result: str
    reason: str


@_message("bye")
class Bye(Message):
    pass


# --- bot -> game master ---


@_message("ready")
class Ready(Message):
    name: str
    version: str = "0"
    protocol: int = PROTOCOL_VERSION


@_message("move")
class Move(Message):
    game_id: str
    ply: int
    move: Any  # a UCI string when well formed; the game master checks it


@_message("resign")
class Resign(Message):
    game_id: str
    ply: int


TO_BOT = (Hello, GameStart, MoveRequest, MoveRejected, GameOver, Bye)
FROM_BOT = (Ready, Move, Resign)


def _check_type(value: Any, hint: Any) -> bool:
    if hint is Any:
        return True
    origin = typing.get_origin(hint)
    if origin in (typing.Union, types.UnionType):
        return any(_check_type(value, arm) for arm in typing.get_args(hint))
    if hint is type(None):
        return value is None
    if origin is list:
        (item,) = typing.get_args(hint)
        return isinstance(value, list) and all(_check_type(v, item) for v in value)
    if origin is dict:
        return isinstance(value, dict)
    if hint is float:
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if hint is int:
        return isinstance(value, int) and not isinstance(value, bool)
    return isinstance(value, hint)


def _build(cls: type, data: dict[str, Any]) -> Any:
    hints = typing.get_type_hints(cls)
    kwargs = {}
    for f in fields(cls):
        if f.name in data:
            value = data[f.name]
            if not _check_type(value, hints[f.name]):
                raise ProtocolError(f"{cls.__name__}.{f.name}: bad value {value!r}")
            kwargs[f.name] = value
        elif f.default is MISSING and f.default_factory is MISSING:
            raise ProtocolError(f"{cls.__name__}: missing field {f.name!r}")
    return cls(**kwargs)


def encode(msg: Message) -> str:
    return json.dumps({"type": msg.type, **asdict(msg)})


def decode(text: str | bytes, expect: tuple[type[Message], ...] | None = None) -> Message:
    """Parse one Contract A frame. Unknown fields are ignored."""
    if isinstance(text, bytes):
        raise ProtocolError("binary frames are not allowed")
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ProtocolError(f"malformed JSON: {exc}") from exc
    if not isinstance(data, dict) or not isinstance(data.get("type"), str):
        raise ProtocolError("frame is not an object with a string 'type'")
    cls = _REGISTRY.get(data["type"])
    if cls is None or (expect is not None and cls not in expect):
        raise ProtocolError(f"unexpected message type {data['type']!r}")
    return _build(cls, data)


# --- Contract B: control API ---

CONTROL_METHODS = frozenset(
    {
        "status",
        "state",
        "history",
        "start_game",
        "stop",
        "resume",
        "save",
        "load",
        "list_saves",
        "shutdown",
    }
)
INIT_METHODS = frozenset({"start_game", "load"})


@dataclass(frozen=True)
class Request:
    id: str
    method: str
    params: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class Response:
    id: str
    ok: bool
    result: Any = None
    error: dict[str, Any] | None = None


class RpcError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message


def encode_request(req: Request) -> str:
    return json.dumps(asdict(req))


def decode_request(text: str | bytes) -> Request:
    data = _load_object(text)
    req = _build(Request, data)
    return req


def encode_response(resp: Response) -> str:
    data: dict[str, Any] = {"id": resp.id, "ok": resp.ok}
    if resp.ok:
        data["result"] = resp.result
    else:
        data["error"] = resp.error
    return json.dumps(data)


def decode_response(text: str | bytes) -> Response:
    data = _load_object(text)
    resp = _build(Response, data)
    if not resp.ok:
        err = resp.error
        if not (isinstance(err, dict) and isinstance(err.get("code"), str)):
            raise ProtocolError("error response without error.code")
    return resp


def _load_object(text: str | bytes) -> dict[str, Any]:
    if isinstance(text, bytes):
        raise ProtocolError("binary frames are not allowed")
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ProtocolError(f"malformed JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ProtocolError("frame is not a JSON object")
    return data
