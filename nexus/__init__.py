"""Nexus — the persistent, game-agnostic coordinator.

An Effector registers a capability schema over a held WebSocket; agent-facing
HTTP (`/schema`, `/invoke`, `/status`) discovers and drives it. The Nexus owns
no game knowledge: it validates invokes only against the registered schema and
relays them over the held channel.
"""
