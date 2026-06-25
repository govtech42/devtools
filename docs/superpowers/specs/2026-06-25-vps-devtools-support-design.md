# VPS Dev Tools — Support Group Design Spec

**Date:** 2026-06-25
**Status:** Approved (design phase) — Support group on a second Lightsail host
**Owner:** code42
**Parent:** `docs/superpowers/specs/2026-06-25-vps-devtools-design.md` (§11 group model)

## 1. Goal

Stand up the **Support group** — **Planka** (kanban) and **Chatwoot** (helpdesk) —
on its **own AWS Lightsail host**, mirroring the Dev group's patterns (Docker,
shared Postgres, curated `reporting` layer, N2 network, Caddy TLS). Customer
support runs primarily over **WhatsApp** (Brazil's dominant channel). Chatwoot is
**our fork** (we add Kanban + product features); Planka is an **overlay** (branding
only).

Data-access goals are unchanged from the platform: (A) each app's **native API**
for programmatic access; (B) curated **`reporting`** views via PostgREST for BI —
**per-group** on this host (cross-host BI deferred, see parent §11).

## 2. Locked Decisions

| Item | Decision |
|---|---|
| Host | AWS Lightsail **8 GB `large_2_0`** (2 vCPU / 8 GB / 160 GB SSD), `us-east-1` |
| Self-containment | own Caddy + Postgres + reporting; 4 GB swap; `/data` block disk; no backups |
| Apps | **Planka** (kanban), **Chatwoot** (helpdesk) |
| Build | Planka = overlay official image (**branding only**); **Chatwoot = our fork** (Kanban + features) |
| Chatwoot registry | **GHCR** (fork built off-host, host pulls) — same as Plane |
| WhatsApp | **Cloud API (Meta official)** — Chatwoot native channel; webhook via Caddy; creds in `.env`; **no extra container** |
| Attachments | **MinIO** (own container, bucket `chatwoot`); Chatwoot Active Storage → S3-compatible |
| Database | one shared Postgres; DBs `planka`, `chatwoot`; `reporting` DB via `postgres_fdw` |
| BI surface | **PostgREST** over `reporting` + read-only role; **Adminer**; per-group |
| Auth | A1 — each app its own login; no SSO |
| Network | N2 — apps public via Caddy TLS; Postgres/PostgREST/Adminer no host port (SSH tunnel) |
| Domains | `board.code42.dev` (Planka), `support.code42.dev` (Chatwoot) |

## 3. Accepted Risks

1. **Memory budget (8 GB).** Idle estimate: Planka ~0.3, Chatwoot web ~0.6,
   Sidekiq ~0.4, Chatwoot Redis ~0.05, MinIO ~0.2, Postgres ~0.7,
   Caddy/PostgREST/Adminer ~0.2 → **~2.5 GB**. Comfortable; 4 GB swap as safety net.
2. **No backups.** Block disk at `/data` is the only durability (survives instance
   recreation). MinIO attachments + Postgres volume live there. Accepted.
3. **WhatsApp Cloud API depends on Meta.** Requires a verified Meta Business
   account, an approved phone number, and a public webhook (Caddy provides it).
   Outage/policy on Meta's side affects the channel. Accepted (ToS-safe vs the
   ban risk of unofficial bridges).
4. **Chatwoot fork maintenance.** Adding Kanban + features means owning rebases vs
   upstream — logged in `apps/chatwoot/CHANGES.md` (same discipline as Plane).

## 4. Architecture

```
                 Internet
                    │ 443/80
             ┌──────▼──────┐  DNS: board. → Planka ; support. → Chatwoot
             │    Caddy    │  (auto-TLS)
             └──┬───────┬──┘
        ┌───────┘       └─────────┐
   ┌────▼────┐            ┌────────▼─────────┐
   │  planka │            │   chatwoot-web   │◄── WhatsApp Cloud API webhook
   └────┬────┘            │   (Rails/Puma)   │     (Meta → /webhooks/whatsapp)
        │                 └───┬──────────┬───┘
        │     ┌───────────────┘          │
        │     │ chatwoot-sidekiq   chatwoot-redis (own)
        │     │ (workers)                 │
        │     └──────────┐                │  attachments → MinIO (bucket chatwoot)
   ┌────▼────────────────▼────────────────▼──┐
   │            Postgres (1 instance)         │
   │  db:planka   db:chatwoot                 │
   │  db:reporting ◄─ postgres_fdw ─┐         │
   │     └─ schema reporting (views)          │
   └───────────────┬──────────────────────────┘
                   │ (docker net / ssh -L — N2)
            ┌──────▼──────┐
            │  PostgREST  │ + Adminer
            └─────────────┘
```

**Public:** Caddy (80/443), SSH (22, owner IP) — Lightsail firewall.
**Closed:** Postgres, PostgREST, Adminer, MinIO console — no host port (SSH tunnel).
**WhatsApp:** inbound webhook hits `support.code42.dev` (Caddy → chatwoot-web); no
new public surface beyond the existing Chatwoot site.

### Services (`deploy/support/docker-compose.yml`)

| Service | Image source | Purpose | Postgres DB | Host port |
|---|---|---|---|---|
| `caddy` | shared `apps/caddy` overlay | TLS ingress | — | 80, 443 |
| `postgres` | shared `apps/postgres` (fdw) | shared DB | all | none |
| `planka` | official overlay (branding) | kanban | `planka` | none (via Caddy) |
| `chatwoot-web` | **GHCR** (fork) | helpdesk web (Rails) | `chatwoot` | none (via Caddy) |
| `chatwoot-sidekiq` | **GHCR** (fork) | background jobs | `chatwoot` | none |
| `chatwoot-init` | **GHCR** (fork) | one-off `db:chatwoot_prepare` | `chatwoot` | none |
| `chatwoot-redis` | official (Valkey) | Sidekiq queue/cache | — | none |
| `minio` | official (MinIO) | Chatwoot attachments | — | none (tunnel) |
| `postgrest` | official | BI REST over `reporting` | `reporting` | none (tunnel) |
| `adminer` | official | SQL explorer | `reporting` | none (tunnel) |

> Chatwoot backend (web/sidekiq/init) share one fork image with different commands
> (DRY via a compose anchor, like Plane's backend). Exact env var names confirmed
> against the fork's `.env.example` at implementation.

## 5. Repository Additions

Reuse the shared `apps/` library and `infra/`; add:

```
apps/planka/
  Dockerfile               # FROM official planka + branding assets
  branding/                # logo / custom assets overlaid into the image
  README.md
apps/chatwoot/             # FORK CONTEXT (we modify code)
  upstream/                # submodule → fork of chatwoot/chatwoot, branch code42
  Dockerfile               # build from the fork (or FROM fork base)
  CHANGES.md               # divergence log (Kanban + features)
  README.md                # branch model, build, push GHCR, rebase
  .env.chatwoot.example    # reference of backend env (supplied via compose)
  reporting-chatwoot.sql   # FDW + reporting views (applied after migrate)
apps/planka/reporting-planka.sql   # FDW + reporting view for Planka
deploy/support/
  docker-compose.yml       # composes the above; profile-free (all run on this host)
  .env.example             # DATA_ROOT, per-app creds, MinIO, WhatsApp, GHCR
```

`infra/scripts/create-lightsail.sh` is reused: `NAME=devtools-support
BUNDLE=large_2_0 DISK_NAME=support-data bash infra/scripts/create-lightsail.sh`.

## 6. Chatwoot Fork — Characterized

Same machinery as Plane (parent §6):
- **Source:** fork `chatwoot/chatwoot` → `github.com/code42/chatwoot`, submodule at
  `apps/chatwoot/upstream/`, long-lived `code42` branch, `upstream` remote.
- **Changes:** add **Kanban** (support-pipeline board over conversations) + other
  product features — logged per change in `apps/chatwoot/CHANGES.md`.
- **Build/release/run:** build off-host (local arm64 dev box uses `--platform
  linux/amd64`, or GitHub Actions) → push **GHCR** → host pulls. Never build on host.
- **Rebase loop:** `git -C apps/chatwoot/upstream fetch upstream && rebase
  upstream/<tag>`, resolve vs `CHANGES.md`, rebuild, bump tag, redeploy.

## 7. Backing-Service Wiring (env, confirm names at implementation)

- **Chatwoot:** `SECRET_KEY_BASE`, `FRONTEND_URL=https://support.code42.dev`,
  `POSTGRES_*` → shared `chatwoot` DB, `REDIS_URL` → `chatwoot-redis`,
  `ACTIVE_STORAGE_SERVICE=s3` + `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/
  `S3_BUCKET_NAME=chatwoot`/`AWS_REGION` + MinIO endpoint, plus WhatsApp Cloud API
  credentials (Meta app id/secret, phone number id, access token, webhook verify
  token). WhatsApp channel is finished in the Chatwoot UI; the webhook lands on
  `support.code42.dev`.
- **Planka:** `DATABASE_URL` → shared `planka` DB, `BASE_URL=https://board.code42.dev`,
  `SECRET_KEY`, initial admin creds. Branding via overlaid assets.
- **MinIO:** root creds in `.env`; bucket `chatwoot` created on first boot (init step).

## 8. Reporting (per-group)

`reporting` DB on this host imports `planka` and `chatwoot` tables via
`postgres_fdw` (explicit foreign tables, minimal columns, enum→text — the pattern
proven in the Dev group). Initial curated views:
- `reporting.kanban_cards` (Planka cards/boards/lists)
- `reporting.support_conversations`, `reporting.support_messages` (Chatwoot)

Columns confirmed against live schemas at implementation. `bi_reader` SELECT-only;
PostgREST exposes them; reached via SSH tunnel (N2). Applied post-migration with
`make reporting GROUP=support` + `reporting-chatwoot.sql` / `reporting-planka.sql`.

## 9. Security / Access

- **Auth A1**, **Network N2** (Lightsail firewall: 22 owner-IP, 80, 443).
- MinIO publishes **no host port** (API + console reached via SSH tunnel); Chatwoot
  reaches it on the internal network.
- WhatsApp webhook is authenticated by Meta's verify token; only the existing
  `support.code42.dev` ingress is public.
- Secrets (incl. Meta WhatsApp tokens, MinIO keys) in `deploy/support/.env`,
  `chmod 600`, gitignored.

## 10. Testing / Verification

Local Colima bring-up of the Support group; smoke (extend `test/smoke.sh` with
`GROUP=support`):
- Planka health endpoint; Chatwoot `/api` (and Sidekiq processing a job).
- Shared Postgres: DBs `planka`/`chatwoot`/`reporting`, roles, `postgres_fdw`.
- Reporting views readable via FDW; PostgREST serves a view.
- MinIO reachable from Chatwoot (bucket `chatwoot` exists; an upload round-trips).
- N2: no host ports on Postgres/PostgREST/Adminer/MinIO.
- (VPS) TLS for `board.`/`support.`; WhatsApp webhook handshake succeeds.

## 11. Out of Scope (this spec)

- Cross-host BI correlation (Dev+Support) — deferred (parent §11; per-group default).
- The detailed Chatwoot Kanban feature design — its own follow-up once the base
  fork builds and runs.
- Email/other channels beyond WhatsApp + the default web widget.
- Monitoring group (Beszel) — separate spec when confirmed.
