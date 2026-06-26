# beszel — lightweight monitoring (hub + agents)

Official multi-arch images (`henrygd/beszel`, `henrygd/beszel-agent`), used directly.

- **hub** (`beszel`): web UI + API on **8090**, embedded SQLite/PocketBase store at
  `/beszel_data` (its own DB — **no shared Postgres**, so the Monitoring group has no
  `postgres`/`reporting`; best-service-is-no-service).
- **agent** (`beszel-agent`): reports a host's metrics; the hub polls it on **45876**
  using a key. One agent per monitored host. Behind the `agents` compose profile —
  **off by default**; on the VPS set `BESZEL_KEY` (from the hub UI) and run
  `--profile agents`.
- Health: `GET /api/health`. Native UI behind Caddy at `https://status.code42.dev`.

## Remote agents (other hosts) — deploy-time
The hub reaching agents on the Dev/Support/Admin hosts is **cross-host** (hub →
`agent:45876` over Lightsail private networking, key-authenticated) — deferred, same
posture as cross-host BI. Start with the local agent (this host) only.
