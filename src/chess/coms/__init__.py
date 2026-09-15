"""Arena transport: WebSocket over Unix sockets, both message contracts, and the bot base class.

Depends on the standard library and `websockets` only. See `PROTOCOL.md`.
"""

from coms.protocol import PROTOCOL_VERSION, ProtocolError, RpcError

__all__ = ["PROTOCOL_VERSION", "ProtocolError", "RpcError"]
