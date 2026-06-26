# VPS Dev Tools — Design Spec

**Date:** 2026-06-25
**Status:** Approved (design phase) — multi-host group model. **Dev group** (Lightsail 16 GB) built first; **Support group** (Lightsail 8 GB) next; **Monitoring group** on radar.
**Owner:** code42

## 1. Goal

One repository that deploys **multiple application groups, each to its own AWS
Lightsail host**, all in Docker with persistent volumes, provisioned by a
**reproducible AWS CLI script** (no OpenTofu). Within a host, a shared
**PostgreSQL** backs that group's apps and feeds a curated **reporting** layer
exposed via **PostgREST** for BI/analytics.

**Deployment groups** (see §11):

- **Dev** (this spec, built first) — **Forgejo** (git), **Mattermost** (chat),
  **Plane** (project mgmt) on a Lightsail **16 GB** host.
- **Support** (next) — **Planka** (kanban), **Chatwoot** (helpdesk) on a Lightsail
  **8 GB** host. Gets its own spec + plan.
- **Admin** (backlog) — **Twenty CRM** (shared Postgres `twenty` + own Redis). Own
  spec. Host TBD.
- **Monitoring** (radar) — starting with **Beszel** (lightweight server monitoring;
  *to confirm*). Host TBD.

Two data-access goals (per group):

- **(A) Programmatic access** to app data → each app's **native REST API** over HTTPS.
- **(B) BI / analytics** over cross-system data → curated read-only views in a
  `reporting` database, exposed via PostgREST and a SQL read-only user (Metabase/Superset
  added later, not now).

**Plane is the app we will modify** — it is built from our own fork and gets a
self-contained, fork-friendly layout (see §6).

## 2. Locked Decisions

| Item | Decision |
|---|---|
| Scope of this spec | the **Dev group** host (other groups in §11, own specs) |
| Host | **AWS Lightsail** instance, **16 GB plan** (bundle `xlarge_2_0`, 4 vCPU / 16 GB / 320 GB SSD, ~US$84/mo), `us-east-1` |
| OS | Ubuntu 24.04 LTS blueprint |
| Provisioning | **AWS CLI script** in `infra/scripts/` (no OpenTofu) |
| Apps | Forgejo, Mattermost, Plane |
| Build strategy | Forgejo + Mattermost = overlay on official image (`FROM <official>`); **Plane = our fork, built from source** |
| Plane registry | **GHCR** (GitHub Container Registry) — Lightsail has no IAM instance role, so ECR is dropped; auth via token in `.env` |
| Database | 1 Postgres instance; separate databases `forgejo`, `mattermost`, `plane`; plus `reporting` DB using **`postgres_fdw`** |
| BI surface | **PostgREST** over `reporting` schema (read-only views) + read-only SQL role ready for Metabase later |
| Auth | A1 — each app has its own login; **no SSO** |
| Network | N2 — apps public via TLS; **Postgres / PostgREST / Studio closed** (reachable only via SSH tunnel) |
| Domain | `code42.dev` → `git.`, `chat.`, `plane.` subdomains |
| Reverse proxy / TLS | Caddy with automatic Let's Encrypt |
| Static IP | Lightsail **static IP** (free while attached), DNS A-records point here |
| Data durability | Separate **Lightsail block disk** mounted at `/data`; survives instance recreation |
| Backups | **None** (accepted risk — see §3) |
| Secrets | `.env` on host, `chmod 600`, gitignored, never committed |

## 3. Accepted Risks

1. **Memory budget.** Plane's current self-host stack is large (see §4): `api`,
   `worker`, `beat-worker`, `migrator`, `web`, `admin`, `space`, `live`, `proxy`,
   plus `plane-redis` (Valkey), `plane-mq` (RabbitMQ), `plane-minio` — `plane-db`
   is dropped in favor of the shared Postgres. Estimated idle for the **3 core
   apps** ~5.5–7 GB. On the **16 GB plan** this leaves ~9–10 GB headroom —
   comfortable. (Support apps run on a separate 8 GB host — §11.) Still provision
   **4 GB swap** as a safety net.
2. **Lightsail has no IAM instance role.** ECR pulls would need static AWS keys on
   the box. Mitigation: Plane image lives in **GHCR**; host authenticates with a
   GitHub token from `.env`. Build off-host (local or GitHub Actions) — never build
   Plane on the host (OOM risk).
3. **No backups.** Loss of the block disk = total data loss; no recovery from
   corruption. Mitigation: data lives on a **separate Lightsail block disk** that
   survives instance deletion/recreation (detach → reattach). Accepted.
4. **`.env` on host** holds Postgres root password, GHCR token, MinIO keys, app
   secrets. Acceptable for a personal dev box; enforced `chmod 600` + `.gitignore`.

## 4. Architecture

```
                  Internet
                     │  443/80
              ┌──────▼──────┐   DNS code42.dev:
              │    Caddy    │   git.  chat.  plane.  → Lightsail static IP
              │ (auto-TLS)  │
              └──┬───┬───┬──┘
       ┌─────────┘   │   └─────────┐
   ┌───▼───┐    ┌────▼────┐   ┌────▼────────────────┐
   │Forgejo│    │Mattermost│   │ Plane (web/space/   │
   └───┬───┘    └────┬─────┘   │ api/worker/beat/    │
       │             │         │ redis/minio)  [FORK]│
       │  native HTTP APIs (A) └────┬────────────────┘
   ┌───▼─────────────▼──────────────▼───┐
   │           Postgres (1 instance)     │
   │  db:forgejo  db:mattermost  db:plane│
   │  db:reporting ◄─postgres_fdw─┐      │
   │     └─ schema reporting (views)     │
   └───────────────┬─────────────────────┘
                   │ (docker network only / SSH tunnel — N2)
            ┌──────▼──────┐
            │  PostgREST  │  + Studio/Adminer
            │ (bi_reader) │  → access via ssh -L
            └─────────────┘
```

**Publicly exposed:** Caddy (80/443) and SSH (22) only — via the **Lightsail
firewall**, SSH restricted to the owner's IP.
**Closed:** Postgres, PostgREST, Studio — no published host ports; reached via `ssh -L`.
**Data:** all named volumes live under `/data` on the attached block disk.

### Docker Compose services

| Service | Image source | Purpose | Postgres DB | Published port |
|---|---|---|---|---|
| `caddy` | official + Caddyfile | reverse proxy, TLS | — | 80, 443 |
| `postgres` | custom (postgres + postgres_fdw) | shared DB | all | none (internal) |
| `forgejo` | official overlay | git hosting | `forgejo` | none (via Caddy) |
| `mattermost` | official overlay | chat | `mattermost` | none (via Caddy) |
| `plane-api` `plane-worker` `plane-beat` `plane-migrator` | **GHCR** (fork build, `apps/api/Dockerfile.api`) | Plane backend (Django) | `plane` | none |
| `plane-web` `plane-admin` `plane-space` `plane-live` | **GHCR** (fork build) | Plane frontends | — | none (via Caddy) |
| `plane-proxy` | **GHCR** (fork build) | Plane internal ingress | — | none (behind Caddy) |
| `plane-redis` | official (Valkey) | Plane cache | — | none |
| `plane-mq` | official (RabbitMQ) | Plane task queue | — | none |
| `plane-minio` | official (MinIO) | Plane object storage | — | none |
| `postgrest` | official | BI REST API over `reporting` | `reporting` | none (tunnel) |
| `adminer` | official | SQL explorer (light; Studio dropped) | `reporting` | none (tunnel) |

> **Plane has its own `plane-proxy`** (nginx) fronting web/admin/space/live/api.
> Caddy routes `plane.code42.dev` → `plane-proxy`; we do not re-expose each Plane
> sub-app. `plane-db` from upstream is removed — Plane points at the shared Postgres
> `plane` database via env. SQL explorer is **Adminer** (light), not Supabase Studio.

## 5. Repository Structure (group-aware)

Three top-level concerns: **`infra/`** = host provisioning; **`apps/`** = shared,
reusable per-app contexts (one per application, DRY); **`deploy/<group>/`** = one
composition per deployment group → one Lightsail host. A group's compose file
references the shared `apps/<app>/` contexts and pins which services run on that
host. Adding a group never duplicates an app context.

```
infra/                          # ALL cloud/host provisioning lives here
  scripts/
    create-lightsail.sh         # AWS CLI, parameterized: --group dev|support|monitoring
    user-data.sh                # cloud-init first boot: docker, swap, mount /data, ghcr login, clone
    destroy-lightsail.sh        # guarded teardown (refuses without explicit confirm)
  firewall.json                 # Lightsail port rules (22 owner-IP, 80, 443)
  README.md                     # provisioning runbook (per group)

apps/                           # shared per-app contexts — one self-contained dir each
  caddy/        Caddyfile, Dockerfile
  postgres/     Dockerfile (+ postgres_fdw), init/ (dbs, roles, fdw, reporting views)
  forgejo/      Dockerfile (overlay), README.md
  mattermost/   Dockerfile (overlay), README.md
  plane/        upstream/ (submodule fork), Dockerfile.*, CHANGES.md, README.md   # §6
  postgrest/    postgrest.conf
  adminer/      (uses official image; notes only)
  planka/       Dockerfile/overlay, README.md           # Support group (later)
  chatwoot/     Dockerfile/overlay, README.md           # Support group (later)
  beszel/       README.md                                # Monitoring group (radar)

deploy/                         # one composition per group → one host
  dev/          docker-compose.yml  .env.example         # Forgejo + Mattermost + Plane (16 GB)
  support/      docker-compose.yml  .env.example         # Planka + Chatwoot (8 GB) — later
  monitoring/   docker-compose.yml  .env.example         # Beszel … (radar)

docs/superpowers/specs/         # specs (one per group)
docs/superpowers/plans/         # plans (one per group)
```

> Each group host is self-contained: its own Caddy + Postgres + reporting. The
> `apps/` contexts are the shared library; `deploy/<group>/docker-compose.yml` is the
> composition. Build contexts in a group's compose point at `../../apps/<app>`.
> Rationale: provisioning, the reusable app library, and per-host composition each
> change for different reasons and at different cadences.

## 6. Plane Fork — Characterized & Ready

Plane is the app we will change, so its context is set up for sustained divergence
from upstream, not one-off patching.

- **Source of truth:** a **fork** of `makeplane/plane` on the owner's GitHub,
  vendored here as a **git submodule** at `apps/plane/upstream/`.
- **Branch model:** upstream tracked on a `upstream` remote; our work on a long-lived
  `code42` branch. Real commits on the fork (full source control) — **not** patch
  files — so changes are diffable and rebasable against new Plane releases.
- **`apps/plane/CHANGES.md`** logs each divergence: file(s), what changed, why, and
  whether it should be upstreamed or is local-only. This keeps rebases sane.
- **Build/release/run:** `Dockerfile.api` and `Dockerfile.web` build from the
  submodule; images are built **off-host** (local or GitHub Actions), tagged, and
  pushed to **GHCR**. The host only `docker pull`s. Tags are pinned — no `:latest`.
- **Rebase loop:** `git -C apps/plane/upstream fetch upstream && git rebase
  upstream/<release-tag>`, resolve against `CHANGES.md`, rebuild, push, bump tag in
  `.env`/compose, redeploy.
- Forgejo and Mattermost stay as thin overlays (no fork) — their contexts hold only
  a Dockerfile + README, so the diff against official is obvious.

## 7. Provisioning Flow (no OpenTofu)

1. (manual, once) Fork Plane → build its images off-host → push to **GHCR**.
2. `infra/scripts/create-lightsail.sh` (AWS CLI): create the 8 GB Ubuntu instance,
   allocate + attach a **static IP**, create + attach a **block disk**, apply
   `firewall.json`, and pass `user-data.sh`.
3. `user-data.sh` on first boot: install Docker + Compose, create 4 GB swap, format
   + mount the block disk at `/data`, `docker login ghcr.io` (token from `.env`),
   clone this repo, then wait for `.env` to be present.
4. Owner provides `.env` (scp/ssh) with all secrets + GHCR token + SSH details.
5. `docker compose -f apps/docker-compose.yml up -d` → Caddy fetches certs; Postgres
   runs `init/` SQL (databases, roles, `postgres_fdw`, `reporting` views).
6. Owner creates DNS A-records on `code42.dev` (`git.`, `chat.`, `plane.`) → static IP.
7. Smoke test (see §9).

## 8. Security / Access Control

- **Auth:** A1 — independent per-app logins. No SSO.
- **Network:** N2, enforced by the **Lightsail firewall**.
  - Public: 80/443 (Caddy), 22 (SSH, restricted to owner IP).
  - Closed: Postgres, PostgREST, Studio bind to the Docker network only — no host
    port published. Access via `ssh -L <localport>:127.0.0.1:<svcport>`.
- **Secrets:** `.env` on host, `chmod 600`, in `.gitignore`. Postgres root, GHCR
  token, app secret keys, MinIO keys live there.
- **Data durability:** separate block disk at `/data`; survives instance recreation.
  No backups (accepted).
- **BI role:** `bi_reader` is SELECT-only on `reporting` views; cannot reach app
  databases directly.

## 9. Testing / Verification

- `bash -n` (syntax) on the provisioning scripts; `shellcheck` if available.
- `docker compose -f apps/docker-compose.yml config` lints without error.
- Smoke tests after `up`:
  - `curl -fsS https://git.code42.dev` (and `chat.`, `plane.`) return healthy.
  - TLS certs issued (no Caddy cert errors in logs).
  - Via SSH tunnel: `psql` into `reporting`, `SELECT` from each `reporting.*` view.
  - Via SSH tunnel: PostgREST endpoint returns rows for a `reporting` view.
- Verify Postgres has 4 databases + `postgres_fdw` extension + `reporting` schema.
- Verify no host-published ports for Postgres/PostgREST/Studio (`docker compose ps`).
- Verify `/data` is the mounted block disk and all volumes resolve under it.

## 10. Out of Scope (this spec)

This spec covers the **Dev group** only. Other groups in §11 get their own specs.

- Metabase / Superset install (read-only role is left ready).
- SSO / federated identity.
- Automated backups.
- HA / autoscaling (multi-host here is one host per group, not redundancy).
- Plane-fork CI on GitHub Actions (image built manually for now; layout supports adding it later).

## 11. Deployment Groups (multi-host roadmap)

One repo, several groups, **one Lightsail host per group**, each self-contained
(own Caddy + Postgres + reporting). `deploy/<group>/docker-compose.yml` composes the
shared `apps/` contexts for that host.

| Group | Lightsail bundle | Apps | Subdomains | Status |
|---|---|---|---|---|
| **Dev** | `xlarge_2_0` (16 GB) | Forgejo, Mattermost, Plane | `git.` `chat.` `plane.` | built, merged (PR #1) |
| **Support** | `large_2_0` (8 GB) | Planka, Chatwoot | `board.` `support.` | spec done — own plan next |
| **Admin** | TBD | Twenty CRM | `crm.` | radar/backlog — own spec |
| **Monitoring** | small (~2 GB) | Beszel (hub + agents) | `status.` | spec done — own plan |

> "t3.large" in conversation maps to Lightsail bundle **`large_2_0`** (8 GB / 2 vCPU).

**Support group notes (when built):** Planka ~0.3 GB (Node + shared Postgres
`planka`); Chatwoot ~1.5–2 GB (Rails + Sidekiq + own Redis + shared Postgres
`chatwoot`). Fits the 8 GB host with swap. See its spec:
`2026-06-25-vps-devtools-support-design.md`.

**Admin group notes (backlog):** **Twenty CRM** (`twentyhq/twenty`) — NestJS server
+ worker + React front; backing services **shared Postgres `twenty`** (our standard)
+ **own Redis**. Build strategy (overlay vs fork) and host size decided in its own
brainstorm. Subdomain `crm.code42.dev`.

### Cross-host BI — open decision (resolve in the Support spec)

The Dev reporting layer assumes **one local Postgres** (FDW is local). Support data
lives on a **second host's Postgres**, so cross-group joins are not free. Options:

- **(a) Per-group reporting (recommended start):** each host runs its own
  `reporting` + PostgREST over only its local apps. Keeps **N2** intact; no Postgres
  is exposed off-host. BI is per-group; cross-group correlation done later in a BI
  tool that reads both PostgREST APIs.
- **(b) Central reporting:** the Dev (or Monitoring) host's `reporting` reaches the
  Support Postgres over **Lightsail private networking** (same-region private IP / VPC
  peering), with that Postgres opened **only to the peer**. Enables native cross-group
  FDW joins, but widens the network surface — weigh against N2.
- **(c) Central BI on the Monitoring host** once it exists.

Default to **(a)** until a concrete cross-group reporting need appears.
