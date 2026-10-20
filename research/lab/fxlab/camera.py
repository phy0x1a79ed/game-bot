"""Render client for labs: a full-game client that joins a lab to take screenshots. Built in T6 (scope fxlab-cam)."""


def attach(lab):
    raise NotImplementedError("camera.attach arrives with scope fxlab-cam")


def detach(lab, missing_ok=False):
    if not missing_ok:
        raise NotImplementedError("camera.detach arrives with scope fxlab-cam")
