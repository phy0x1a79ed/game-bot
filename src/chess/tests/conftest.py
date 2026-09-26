import os
import shutil
import tempfile

# Set before any test imports game_master.paths. The root stays short, so
# socket paths under it fit transport.MAX_SOCKET_PATH.
_ROOT = tempfile.mkdtemp(prefix="cat-", dir="/tmp")
os.environ["CHESS_ARENA_RUNTIME"] = os.path.join(_ROOT, "run")
os.environ["CHESS_ARENA_DATA"] = os.path.join(_ROOT, "data")


def pytest_sessionfinish(session, exitstatus):
    shutil.rmtree(_ROOT, ignore_errors=True)
