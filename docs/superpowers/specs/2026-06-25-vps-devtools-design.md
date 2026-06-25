# VPS Dev Tools — Design Spec

**Date:** 2026-06-25
**Status:** Approved (design phase) — revised for AWS Lightsail
**Owner:** code42

## 1. Goal

Stand up a single **AWS Lightsail** host running a self-hosted developer-tools
stack — **Forgejo** (git), **Mattermost** (chat), and **Plane** (project
management) — all in Docker with persistent volumes. The host is provisioned by a
**reproducible AWS CLI script** (no OpenTofu). A shared **PostgreSQL** instance
backs all three apps and feeds a curated **reporting** layer exposed via
**PostgREST** for BI/analytics.

Two data-access goals:

- **(A) Programmatic access** to app data → each app's **native REST API** over HTTPS.
- **(B) BI / analytics** over cross-system data → curated read-only views in a
  `reporting` database, exposed via PostgREST and a SQL read-only user (Metabase/Superset
  added later, not now).

**Plane is the app we will modify** — it is built from our own fork and gets a
self-contained, fork-friendly layout (see §6).

## 2. Locked Decisions

| Item | Decision |
|---|---|
| Host | **AWS Lightsail** instance, **8 GB plan** (2 vCPU / 8 GB / 160 GB SSD / 4 TB transfer), `us-east-1` |
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

1. **8 GB is tight.** Estimated idle ~6–7 GB across Postgres + Forgejo +
   Mattermost + Plane (web/space/api/worker/beat/redis/minio) + Caddy + PostgREST
   + Studio. Mitigation: **4 GB swap** on the block disk; keep the SQL explorer
   minimal. Upgrade path: Lightsail 16 GB plan if it thrashes.
2. **Lightsail has no IAM instance role.** ECR pulls would need static AWS keys on
   the box. Mitigation: Plane image lives in **GHCR**; host authenticates with a
   GitHub token from `.env`. Build off-host (local or GitHub Actions) — never build
   Plane on the 8 GB host (OOM risk).
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
| `plane-*` | **GHCR** (fork build) | project mgmt (web, space, api, worker, beat) | `plane` | none (via Caddy) |
| `plane-redis` | official | Plane queue/cache | — | none |
| `plane-minio` | official | Plane object storage | — | none |
| `postgrest` | official | BI REST API over `reporting` | `reporting` | none (tunnel) |
| `studio`/`adminer` | official | SQL explorer | `reporting` | none (tunnel) |

> Studio is heavy (needs `pg-meta`). If memory is tight, substitute Adminer / pgweb.
> Decide in the implementation plan.

## 5. Repository Structure

Two top-level concerns, kept apart for readability: **`infra/`** = everything to
create/tear down the cloud host; **`apps/`** = the dockerized runtime stack, one
self-contained context per application.

```
infra/                          # ALL cloud/host provisioning lives here
  scripts/
    create-lightsail.sh         # AWS CLI: instance (8GB), static IP, firewall, block disk, user-data
    user-data.sh                # cloud-init first boot: docker, swap, mount /data, ghcr login, clone, compose up
    destroy-lightsail.sh        # guarded teardown (refuses without explicit confirm)
  firewall.json                 # Lightsail port rules (22 owner-IP, 80, 443)
  README.md                     # provisioning runbook (order, prerequisites, DNS)

apps/                           # the application stack — one context per app
  docker-compose.yml            # orchestrates every service, references each context
  .env.example                  # real .env never committed
  caddy/
    Caddyfile                   # routes git./chat./plane. + auto-TLS
  postgres/
    Dockerfile                  # postgres + postgres_fdw
    init/                       # SQL: create dbs, roles, fdw server/foreign tables, reporting views
  forgejo/
    Dockerfile                  # FROM official + overlay
    README.md                   # config notes, native API base
  mattermost/
    Dockerfile                  # FROM official + overlay
    README.md
  plane/                        # FORK CONTEXT — the app we modify (see §6)
    upstream/                   # git submodule → our Plane fork
    Dockerfile.api
    Dockerfile.web
    CHANGES.md                  # every divergence from upstream, why, how to rebase
    README.md                   # branch model, build, push GHCR, host pull
  postgrest/
    postgrest.conf

docs/superpowers/specs/         # this spec
```

> Rationale for `infra/` vs `apps/`: provisioning the cloud box and running the
> workload change for different reasons and at different cadences. Splitting them
> keeps each app a clean, independently-readable context (the maintenance goal),
> while honoring "all infra under `infra/`."

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

## 10. Out of Scope (this phase)

- Metabase / Superset install (read-only role is left ready).
- SSO / federated identity.
- Automated backups.
- Multi-host / HA / autoscaling.
- Plane-fork CI on GitHub Actions (image built manually for now; layout supports adding it later).
