"""Factorio Effector — the per-game "claw".

A pure requesting client: connects to the Nexus, registers the `world` command
group, holds the dispatch channel, and forwards each `world.*` invoke to the
appliance's control surface. It issues no `docker run` and holds no engine PID;
process ownership lives entirely in the appliance supervisor.
"""
