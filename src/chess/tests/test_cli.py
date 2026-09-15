"""The CLI end to end: detached daemons, real bots, and cleanup."""

import json
import os
import subprocess
import sys
import time

from game_master import paths


def cli(*args, check=True):
    env = dict(os.environ, PYTHONPATH=str(paths.SRC))
    proc = subprocess.run([sys.executable, "-m", "game_master.cli", *args], env=env,
                          capture_output=True, text=True, timeout=90)
    if check:
        assert proc.returncode == 0, f"{args}: {proc.returncode}\n{proc.stdout}\n{proc.stderr}"
    return proc


def cli_json(*args):
    return json.loads(cli(*args, "--json").stdout)


def _alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def _session_dirs():
    if not paths.RUNTIME.is_dir():
        return []
    return [p for p in paths.RUNTIME.iterdir() if paths.SID_RE.match(p.name)]


def _wait_for_game(sid):
    deadline = time.monotonic() + 20
    while (status := cli_json("status", sid))["game_id"] is None:
        assert time.monotonic() < deadline
        time.sleep(0.1)
    return status


def test_start_save_load_kill_leaves_nothing_behind():
    sid = cli("start", "--white", "naive", "--black", "simple", "--games", "4", "--seed", "5")\
        .stdout.strip()
    assert paths.SID_RE.match(sid)
    status = _wait_for_game(sid)
    assert [b["name"] for b in status["bots"]] == ["naive", "simple"]
    pids = [status["pid"]] + [b["pid"] for b in status["bots"]]

    assert cli("status", check=False).returncode == 0  # one live session: sid is optional
    cli("save", sid, "t-cli")
    loaded = cli("load", "t-cli").stdout.strip()
    assert paths.SID_RE.match(loaded) and loaded != sid
    loaded_status = cli_json("status", loaded)
    assert (loaded_status["phase"], loaded_status["loaded_from"]) == ("stopped", "t-cli")
    pids += [loaded_status["pid"]] + [b["pid"] for b in loaded_status["bots"]]
    assert {s["sid"] for s in cli_json("ls")["sessions"]} == {sid, loaded}
    assert cli("status", check=False).returncode == 2  # two live sessions: sid is required

    for s in (sid, loaded):
        assert cli("kill", s).stdout.strip() == f"killed {s}"
    deadline = time.monotonic() + 10
    while any(_alive(p) for p in pids) and time.monotonic() < deadline:
        time.sleep(0.1)
    assert not [p for p in pids if _alive(p)]
    assert not _session_dirs()
    assert cli_json("ls") == {"sessions": []}
    assert (paths.records_dir(sid) / "gm.log").is_file()
    assert cli("status", sid, check=False).returncode == 3


def test_start_with_unknown_bot_leaves_no_session():
    records_before = set(paths.SESSION_RECORDS.iterdir()) if paths.SESSION_RECORDS.is_dir() else set()
    proc = cli("start", "--white", "nobody", "--black", "naive", check=False)
    assert proc.returncode == 1
    assert "invalid_params" in proc.stderr
    assert not _session_dirs()
    after = set(paths.SESSION_RECORDS.iterdir()) if paths.SESSION_RECORDS.is_dir() else set()
    assert after == records_before
