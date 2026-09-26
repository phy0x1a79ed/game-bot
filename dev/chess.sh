#!/usr/bin/env bash
# Chess arena entry point.
#   chess.sh env              create or update the conda envs from envs/
#   chess.sh test [pytest args]
#   chess.sh ui [--port N]    serve the browser viewer on 127.0.0.1
#   chess.sh <command> ...    session CLI; see `chess.sh --help`
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPATH="$ROOT/src/chess"

sync_env() {
    local file="$1" name
    name="$(basename "$file" .yml)"
    if mamba env list | awk '{print $1}' | grep -qx "$name"; then
        mamba env update -y -n "$name" -f "$file" --prune
    else
        mamba env create -y -f "$file"
    fi
}

case "${1:-}" in
    env)
        for file in "$ROOT"/envs/chess.yml "$ROOT"/envs/chess-*.yml; do
            [[ -e "$file" ]] && sync_env "$file"
        done
        ;;
    test)
        shift
        cd "$ROOT"
        exec mamba run --no-capture-output -n chess python -m pytest src/chess/tests "$@"
        ;;
    ui)
        shift
        exec mamba run --no-capture-output -n chess python -m viewer "$@"
        ;;
    *)
        exec mamba run --no-capture-output -n chess python -m game_master.cli "$@"
        ;;
esac
