"""In-container RCON pipe: one JSON line in, one JSON line out, over one engine socket.

    -> {"code": "<lua>"}
    <- {"ok": true, "out": "..."}   or   {"ok": false, "error": "..."}

Factorio answers each command with exactly one packet, whatever its size.
"""

import json
import socket
import struct
import sys
import time


def send(sock, pid, kind, body):
    data = body.encode() + b"\0\0"
    sock.sendall(struct.pack("<iii", len(data) + 8, pid, kind) + data)


def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise EOFError("rcon socket closed")
        buf += chunk
    return buf


def recv(sock):
    size = struct.unpack("<i", recv_exact(sock, 4))[0]
    data = recv_exact(sock, size)
    pid, _ = struct.unpack("<ii", data[:8])
    return pid, data[8:-2].decode(errors="replace")


def connect(port, password, deadline):
    while True:
        try:
            sock = socket.create_connection(("127.0.0.1", port), timeout=3600)
            send(sock, 1, 3, password)
            pid, _ = recv(sock)
            if pid == -1:
                raise SystemExit("rcon auth failed")
            return sock
        except (ConnectionError, OSError, EOFError):
            if time.time() > deadline:
                raise
            time.sleep(0.5)


def main():
    port, password = int(sys.argv[1]), sys.argv[2]
    sock = connect(port, password, time.time() + 120)
    print(json.dumps({"ok": True, "out": "ready"}), flush=True)
    pid = 10
    for line in sys.stdin:
        pid += 1
        try:
            send(sock, pid, 2, "/silent-command " + json.loads(line)["code"])
            _, out = recv(sock)
            msg = {"ok": True, "out": out}
        except Exception as exc:  # report and keep serving
            msg = {"ok": False, "error": repr(exc)}
        print(json.dumps(msg), flush=True)


if __name__ == "__main__":
    main()
