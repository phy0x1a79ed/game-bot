#!/usr/bin/env bash
# Chess arena entry point.
#   chess.sh env              build .venv, or the conda envs from envs/ when mamba is on PATH
#   chess.sh test [pytest args]
#   chess.sh ui [--port N]    serve the browser viewer on 127.0.0.1
#   chess.sh web-build        rebuild the committed page bundle (needs node)
#   chess.sh <command> ...    session CLI; see `chess.sh --help`
# Commands run in .venv when it exists, else in the conda env `chess`.
# Set PYTHON to pick the interpreter that `env` builds .venv from.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT/.venv"
export PYTHONPATH="$ROOT/src/chess"

die() {
    echo "chess.sh: $*" >&2
    exit 1
}

sync_env() {
    local file="$1" name
    name="$(basename "$file" .yml)"
    if mamba env list | awk '{print $1}' | grep -qx "$name"; then
        mamba env update -y -n "$name" -f "$file" --prune
    else
        mamba env create -y -f "$file"
    fi
}

find_python3() {
    local candidate
    for candidate in ${PYTHON:-} python3.13 python3.12 python3.11 python3; do
        if command -v "$candidate" >/dev/null &&
            "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
            echo "$candidate"
            return
        fi
    done
    die "need Python 3.11 or newer; found $(python3 --version 2>&1 || echo none). Set PYTHON to one."
}

build_venv() {
    local python
    python="$(find_python3)"
    echo "building .venv with $("$python" --version)"
    "$python" -m venv "$VENV"
    "$VENV/bin/python" -m pip install --quiet --upgrade pip
    "$VENV/bin/python" -m pip install --quiet -e "$ROOT[dev]"
    echo "ready: dev/chess.sh test"
}

run_python() {
    if [[ -x "$VENV/bin/python" ]]; then
        exec "$VENV/bin/python" "$@"
    elif command -v mamba >/dev/null; then
        exec mamba run --no-capture-output -n chess python "$@"
    fi
    die "no Python env yet; run: dev/chess.sh env"
}

case "${1:-}" in
    env)
        if command -v mamba >/dev/null && [[ ! -d "$VENV" ]]; then
            for file in "$ROOT"/envs/chess.yml "$ROOT"/envs/chess-*.yml; do
                [[ -e "$file" ]] && sync_env "$file"
            done
        else
            build_venv
        fi
        ;;
    test)
        shift
        cd "$ROOT"
        run_python -m pytest src/chess/tests "$@"
        ;;
    web-build)
        cd "$ROOT/src/chess/web"
        npm ci --no-audit --no-fund
        exec npm run build
        ;;
    ui)
        shift
        run_python -m viewer "$@"
        ;;
    *)
        run_python -m game_master.cli "$@"
        ;;
esac
