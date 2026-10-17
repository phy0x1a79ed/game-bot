#!/usr/bin/env bash
# Run the fxlab CLI in the game-bot env from any cwd. The env's own interpreter, because mamba run drops stdin.
PY=${FXLAB_PYTHON:-$HOME/lib/miniforge3/envs/game-bot/bin/python}
cd "$(dirname "$0")" && exec "$PY" -m fxlab "$@"
