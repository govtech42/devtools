# Architecture

One repo deploys several **groups**, each to its own AWS Lightsail host. A group is
a `deploy/<group>/docker-compose.yml` composing shared `apps/<app>/` contexts.

## Per-host shape

```
Internet ─443/80─▶ Caddy (sole ingress, auto-TLS) ─▶ app services (internal net)
                                                       │ native APIs (goal A)
                          shared Postgres ◀────────────┘
                          ├─ db: <one per app>
                          └─ db: reporting ◀─ postgres_fdw ─ curated read-only views
                                              └─ PostgREST + Adminer (no host port; ssh -L)
```

- **Ingress:** Caddy only (80/443). Decision: Caddy over Traefik (see DECISIONS) —
  small static route set, zero-config TLS, no Docker socket.
- **Data:** shared Postgres, one DB per app (apps are attached resources, not a shared
  schema). The `reporting` DB is the only seam between BI and app internals.
- **Network (N2):** apps bind internally; Postgres/PostgREST/Adminer/MinIO publish no
  host port — reached via `ssh -L`. SSH (22) is owner-IP-only via the Lightsail firewall.
- **State:** all volumes live under `${DATA_ROOT}` (`/data` = attached Lightsail block
  disk on the VPS; survives instance recreation). No backups.

## Build / release / run (twelve-factor)

- **Build:** overlay official images, or fork (Plane, Chatwoot) built **off-host** →
  GHCR. Never build heavy apps on the host (OOM).
- **Release:** pinned image tags + `deploy/<group>/.env`.
- **Run:** `docker compose up -d` only pulls and runs.

## Reporting

`postgres_fdw` imports app tables (explicit foreign tables, enum→`text`) into the
`reporting` DB; curated views are exposed read-only via PostgREST (`bi_reader` role).
Dynamic-schema apps (Twenty) defer views and use their native API. Cross-host BI is
deferred (per-group reporting keeps N2). See `docs/recipes/fdw-reporting.md`.

## Local vs VPS

Same compose everywhere; `DATA_ROOT` differs. Dev box is arm64 (Colima) — amd64-only
images (Mattermost, Chatwoot) run under Rosetta; overlays cross-build with buildx.
The VPS is amd64 and builds natively.

## Groups

Dev (16 GB), Support (8 GB), Admin (8 GB), Monitoring (radar). Adding one never
duplicates an app context — see `docs/recipes/onboarding-a-new-app.md`.
