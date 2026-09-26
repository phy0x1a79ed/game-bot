"""The CLI end to end: detached daemons, real bots, and cleanup."""

import json
import os
import shutil
import subprocess
import sys
import time

from game_master import paths, saves


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
    assert saves.read_record(sid)["sid"] == sid
    assert sid in [s["name"] for s in saves.record_summaries()]
    assert cli("status", sid, check=False).returncode == 3


def _wait_awaiting(sid, ply):
    deadline = time.monotonic() + 20
    while not ((state := cli_json("state", sid))["awaiting"] and state["ply"] == ply):
        assert time.monotonic() < deadline
        time.sleep(0.1)
    return state


def test_external_seat_from_the_cli():
    sid = cli("start", "--white", "@human", "--black", "naive", "--pace", "0.2").stdout.strip()
    try:
        _wait_awaiting(sid, 0)
        assert cli("step", sid, check=False).returncode == 1
        assert cli("pace", sid, "0").stdout.strip() == "0s"
        assert cli("move", sid, "e2e4").stdout.strip() == "e4"
        _wait_awaiting(sid, 2)
        rejected = cli("move", sid, "e2e4", check=False)
        assert rejected.returncode == 1 and "illegal" in rejected.stderr
        assert cli("resign", sid, "--color", "white").stdout.strip() == "0-1 (resignation)"
    finally:
        cli("kill", sid)


def test_start_with_unknown_bot_leaves_no_session():
    records_before = set(paths.SESSION_RECORDS.iterdir()) if paths.SESSION_RECORDS.is_dir() else set()
    proc = cli("start", "--white", "nobody", "--black", "naive", check=False)
    assert proc.returncode == 1
    assert "invalid_params" in proc.stderr
    assert not _session_dirs()
    after = set(paths.SESSION_RECORDS.iterdir()) if paths.SESSION_RECORDS.is_dir() else set()
    assert after == records_before


def test_match_prints_every_game_and_the_score():
    result = cli_json("match", "naive", "simple", "--games", "2", "--seed", "3")
    assert [(g["white"], g["black"]) for g in result["games"]] == [("naive", "simple"),
                                                                    ("simple", "naive")]
    assert all(g["result"] in ("1-0", "0-1", "1/2-1/2") for g in result["games"])
    assert set(result["score"]) == {"naive", "simple"} and sum(result["score"].values()) == 2
    assert result["sid"] not in [s["sid"] for s in cli_json("ls")["sessions"]]


def test_new_bot_plays_and_a_crash_names_its_log():
    name = f"t_new_{os.getpid()}"
    folder = paths.SRC / f"ai_{name}"
    try:
        assert cli("new-bot", name).stdout.startswith("created ")
        assert cli("new-bot", name, check=False).returncode == 2
        assert cli("new-bot", "Bad-Name", check=False).returncode == 2
        assert len(cli_json("match", name, "naive", "--games", "1")["games"]) == 1

        main = folder / "__main__.py"
        main.write_text(main.read_text().replace("state = GameState", "raise ValueError('oops')\n"
                                                 "        state = GameState"))
        out = cli("match", name, "naive", "--games", "1").stdout
        assert f"{name} lost by resignation" in out and f"bot0-{name}.log" in out
    finally:
        shutil.rmtree(folder, ignore_errors=True)
