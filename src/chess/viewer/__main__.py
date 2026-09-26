"""Serve the browser viewer: `python -m viewer [--port N]`."""

import argparse
import asyncio
import logging

from viewer import server


async def main() -> None:
    parser = argparse.ArgumentParser(prog="chess.sh ui", description="Serve the browser viewer.")
    parser.add_argument("--host", default="127.0.0.1",
                        help="address to bind (default 127.0.0.1; anything else exposes the arena)")
    parser.add_argument("--port", type=int, default=8765, help="TCP port (default 8765)")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s viewer %(levelname)s %(message)s")
    logging.getLogger("websockets").setLevel(logging.WARNING)
    ws_server, _ = await server.start(args.host, args.port)
    print(f"Chess viewer on http://{args.host}:{args.port}/ (Ctrl-C to stop)", flush=True)
    async with ws_server:
        await ws_server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
