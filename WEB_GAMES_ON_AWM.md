# Web-Game Bots on awm — Spec & Background (handoff to awm)

*Worked-out architecture, decisions, contracts, and scope roadmap for building a persistent web-game-playing bot service as awm feature services. Planned in `projects/game-bot/web`; implementation continues in awm scopes. Companion plan file: `/home/tony/.claude/plans/i-want-to-create-cheeky-origami.md`.*

## Goal

A persistent service that plays **web games** unattended: one LLM-driven bot per game, woken on a schedule or by an event, that logs in and plays. Substrate is a real browser (later: android emulator, direct API). Bots reuse Claude/opencode via awm's agent infra. Game egress goes through a VPN; the control plane stays local.

## The key realization

The Nexus/Effector/Appliance pattern proven in the Factorio slice (`projects/game-bot/factorio`) **is** the awm gateway-plus-services pattern. So rather than grow a bespoke hub, build everything as **awm feature services registered on the awm gateway**:

| Concept | awm realization |
|---|---|
| **Nexus** | the awm **gateway** (discovery, catalog = dynamic discoverable API, RPC, pub/sub, supervision, `status`/`register`) |
| **Agent service** | models on `awm/services/agents/` + `awm.agentcore` (subprocess `claude --print` / `opencode serve`, normalized event stream, **no tmux**) |
| **Effector** (per game) | a feature service: game-level semantics, binds a realm session, emits game events |
| **Realm** (per substrate) | a feature service: `realm-browser` (then `realm-android`, `realm-direct`); standard perceive/act API; emits substrate events |
| **Timer** | a small feature service emitting `schedule.tick{game}` on cadence |

## Decisions locked

- **Nexus = awm gateway.** Register game-bot services onto the running gateway; no new hub.
- **Dedicated awm sandbox scope**, not `dev` — own derived port band, side-by-side, so game-bot services don't pollute `dev`'s seeded state. Local-first; mira is the eventual deploy target (and future peer).
- **Agent service reuses `awm.agentcore`** (no tmux); models on `awm/services/agents/`.
- **Per-game effector, shared realm pool.** One effector instance per game; realms shared, one session per game.
- **Dynamic realm binding via the hub** (acquire/release handshake below).
- **Event-based throughout** — awm `emit`/`sub` is the hook fabric: realm → effector → agent, plus timer → agent.

## Service contracts

Every awm service = `awm/services/<name>/` with `run.sh` + `hub_adapter.py` declaring an `API_MANIFEST` (`functions` / `emitters` / `subscriptions`) + `HANDLERS`, booted via `ServiceAdapter`, per-service SQLite. The catalog projects `functions` onto MCP/CLI/HTTP — which is how a bot discovers its game's verbs as native tools. Reference example: `awm/services/discord/` and `awm/services/artifacts/awm/artifacts/hub_adapter.py`.

**Realm family contract** (common shape, each realm declares exact verbs):
- lifecycle: `acquire(game, opts) -> {session_id}` · `release(session_id)` · `reset(session_id)` · `status(session_id?)`
- perceive: `observe(session_id) -> {snapshot, screenshot?}` — a11y/DOM tree (browser), `uiautomator dump` XML (android), response body (direct)
- act: browser → `navigate/click/type/key/wait`; android → `tap/swipe/key/text`; direct → `request`
- emitters: `realm.<type>.<event>` carrying `{session_id, kind, data}` (e.g. `realm.browser.captcha_detected`, `realm.browser.error`)

**Effector contract** (per game):
- functions: game verbs translated into realm calls (`read_board`, `play_move`, `is_over`); thin pass-throughs early
- subscriptions: its realm's emitters, filtered to its `session_id`
- emitters: `game.<name>.turn_ready` / `needs_captcha` / `over`
- bind handshake (dynamic): on first need, RPC `realm-<type>.acquire{game}` → store `session_id` → thread it through later calls → `release` on shutdown. The hub only routes; the realm owns the session pool.

**Agent service contract** (models on `awm/services/agents/`):
- functions: `spawn{game}` · `list` · `stop` · `park/resume`
- subscriptions: `schedule.tick` + `game.*.needs_*` → spawn or wake a bot
- per-bot: scoped MCP config + `allowed_tools` so the bot sees only its effector's functions + shared services (Gmail MCP, escalation). Discovery free from the catalog; blast radius contained.

**Timer contract:** `schedule{game, cron}` · `unschedule{game}` · `list`; emits `schedule.tick{game}` (jittered).

**Gateway `status`/`register`** already exist (`gateway_*`, `services_*`, hub register + WS-lease liveness) — consumed, not reinvented.

## Data-flow paths

- **Scheduled play:** `schedule.tick{game}` → agent spawns bot → bot calls effector verbs (scoped MCP) → effector calls its realm session (hub RPC) → realm drives browser (egress via VPN) → results bubble back → bot loops → exits.
- **Event wake:** `realm.browser.captcha_detected` → effector `game.X.needs_captcha` → agent routes to running bot or spawns one → handle or escalate.
- **Discovery:** bot's MCP reads the catalog scoped to its effector + shared services; verbs appear as tools dynamically.

Two hub-mediated hops on the hot path (bot→effector, effector→realm); events fan out independently.

## Scope roadmap

Each opened properly in awm and given its own implementation plan:

1. **`feat-gamebot`** — composition + dev sandbox home (own gateway port, cross-service wiring, per-game registry/manifests, integration playbooks). First task: sandbox up + a no-op service registered & discoverable.
2. **`svc-realm-browser`** — Chrome (CDP) sessions behind the VPN; realm family contract; substrate events. Reuses the Factorio appliance's stdlib-supervisor instincts + the **UBC openconnect** VPN pattern from `projects/vpn_bounce` (netns share via `network_mode: service:vpn`, kill-switch from the `quit_on_failure` supervisor; needs `--cap-add=NET_ADMIN --device=/dev/net/tun`). Chrome ≥111 DNS-rebind: connect CDP by loopback/IP, not hostname. Headful `google-chrome-stable` + Xvfb + noVNC (watch a bot play); persisted `user-data-dir` = login + park/resume.
3. **`svc-effector` + first game** — per-game effector pattern with the dynamic bind handshake; first real web game end-to-end.
4. **`svc-agent-runner`** — agentcore-backed spawner; scoped MCP + `allowed_tools` per game; event-woken; park/resume; session DB.
5. **`svc-timer`** — cadence service emitting `schedule.tick` with jitter.

Factorio slice in `projects/game-bot` stays as standalone proof-of-concept; names (Nexus/Effector/Realm) carry over.

## Wishlist / future (out of the first slices)

- **Peer gateways** — gateway-to-gateway registration so local services can call services on **mira**. CAVEAT: awm **deliberately retired federation** (`AGENTS.md`: `/peer/*` + `peers` tables deleted, single loopback listener, no auth). Re-introduction is a real, security-sensitive effort (cross-host transport + identity + auth). Its own future scope.
- **`realm-android`** (mira-only; needs `/dev/kvm`, unavailable on WSL2) and **`realm-direct`** (HTTP/API games, no GUI).
- **Captcha escalation** via the **`unimatrix0`** channel — blocking-with-timeout `ask_human(image, prompt)` (MCP tool or small service); checkbox captchas handled in-place by the real browser. Channel setup deferred.
- **Per-game VPN exits** (one openconnect sidecar per game for anti-correlation) vs the shared exit we start with.
- **Email** as a shared service via the existing Gmail MCP; per-game `+alias`.

## Open questions

- Sandbox scope shape: one `feat-gamebot` composition scope first (factor out `svc-*` as they stabilize) vs split `svc-*` from day one.
- Confirm all realm/effector code lives under `awm/services/*` and `projects/game-bot` is retired for web work.

## awm gotchas to remember

- No dev auto-reload — backend edits need `awm dev restart`; a service must restart to re-register a changed manifest (catalog caches the last `ready` frame).
- Only the `dev` scope runs the canonical sandbox at `:7821`; a dedicated game-bot sandbox is a different port (own band) with none of dev's seeded state — intended here.
- Per-service SQLite, manifests are pure JSON (no cross-service imports), service↔service via hub `call`/`emit` only.
