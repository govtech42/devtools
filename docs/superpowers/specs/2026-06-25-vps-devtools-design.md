# VPS Dev Tools — Design Spec

**Date:** 2026-06-25
**Status:** Approved (design phase)
**Owner:** code42

## 1. Goal

Provision a single AWS EC2 host running a self-hosted developer-tools stack —
**Forgejo** (git), **Mattermost** (chat), and **Plane** (project management) — all
in Docker, with persistent volumes. The host is provisioned with **OpenTofu**. A
shared **PostgreSQL** instance backs all three apps and feeds a curated
**reporting** layer exposed via **PostgREST** for BI/analytics.

Two data-access goals:

- **(A) Programmatic access** to app data → use each app's **native REST API** over HTTPS.
- **(B) BI / analytics** over cross-system data → curated read-only views in a
  `reporting` database, exposed via PostgREST and a SQL read-only user (Metabase/Superset
  added later, not now).

## 2. Locked Decisions

| Item | Decision |
|---|---|
| Host | 1× EC2 **t3.large** (8 GB), `us-east-1`, Docker + Docker Compose |
| OS | Ubuntu 24.04 LTS (or Amazon Linux 2023 — finalize in plan) |
| Apps | Forgejo, Mattermost, Plane |
| Build strategy | Forgejo + Mattermost = overlay on official image (`FROM <official>`); **Plane = fork built from source** |
| Database | 1 Postgres instance; separate databases `forgejo`, `mattermost`, `plane`; plus `reporting` DB using **`postgres_fdw`** |
| BI surface | **PostgREST** over `reporting` schema (read-only views) + read-only SQL role ready for Metabase later |
| Auth | A1 — each app has its own login; **no SSO** |
| Network | N2 — apps public via TLS; **Postgres / PostgREST / Studio closed** (reachable only via SSH tunnel) |
| Domain | `code42.dev` → `git.`, `chat.`, `plane.` subdomains |
| Reverse proxy / TLS | Caddy with automatic Let's Encrypt |
| Plane image registry | **Private ECR**; host pulls (no on-host build of Plane) |
| Backups | **None** (accepted risk — see §8) |
| Secrets | `.env` on host, `chmod 600`, gitignored, never committed |

## 3. Accepted Risks

1. **t3.large is tight.** Estimated idle ~6–7 GB across Postgres + Forgejo +
   Mattermost + Plane (web/space/api/worker/beat/redis/minio) + Caddy + PostgREST
   + Studio. Mitigation: **4 GB swap** on the data volume; keep Studio minimal.
   Upgrade path to t3.xlarge if it thrashes.
2. **Plane build off-host.** Building Plane from source on 8 GB risks OOM. Plane
   image is built once (local or GitHub Actions) and pushed to **private ECR**;
   the host only `pull`s.
3. **No backups.** Loss of EBS/instance = total data loss; no recovery from
   corruption. Mitigation: data EBS volume `delete_on_termination=false` so it
   survives instance recreation. Accepted.
4. **`.env` on host** holds Postgres root password and app secrets. Acceptable
   for a personal dev box; enforced `chmod 600` + `.gitignore`.

## 4. Architecture

```
                  Internet
                     │  443/80
              ┌──────▼──────┐   DNS code42.dev:
              │    Caddy    │   git.  chat.  plane.  → EIP
              │ (auto-TLS)  │
              └──┬───┬───┬──┘
       ┌─────────┘   │   └─────────┐
   ┌───▼───┐    ┌────▼────┐   ┌────▼────────────────┐
   │Forgejo│    │Mattermost│   │ Plane (web/space/   │
   └───┬───┘    └────┬─────┘   │ api/worker/beat/    │
       │             │         │ redis/minio)        │
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

**Publicly exposed:** Caddy (80/443) and SSH (22, locked to owner IP) only.
**Closed:** Postgres, PostgREST, Studio — no published host ports; reached via `ssh -L`.

### Docker Compose services

| Service | Image source | Purpose | Postgres DB | Published port |
|---|---|---|---|---|
| `caddy` | official + Caddyfile | reverse proxy, TLS | — | 80, 443 |
| `postgres` | custom `Dockerfile` (postgres + postgres_fdw) | shared DB | all | none (internal) |
| `forgejo` | official overlay | git hosting | `forgejo` | none (via Caddy) |
| `mattermost` | official overlay | chat | `mattermost` | none (via Caddy) |
| `plane-*` | ECR (fork build) | project mgmt (web, space, api, worker, beat) | `plane` | none (via Caddy) |
| `plane-redis` | official | Plane queue/cache | — | none |
| `plane-minio` | official | Plane object storage | — | none |
| `postgrest` | official | BI REST API over `reporting` | `reporting` | none (tunnel) |
| `studio`/`adminer` | official | SQL explorer | `reporting` | none (tunnel) |

> Studio is heavy (needs `pg-meta`). If memory is tight, substitute a lightweight
> SQL UI (Adminer / pgweb). Decide in the implementation plan.

## 5. Repository Structure

```
infra/                      # OpenTofu (AWS)
  main.tf                   # provider, EC2, EIP, security group, EBS gp3, ECR, key_pair
  variables.tf
  outputs.tf
  user-data.sh              # cloud-init: docker, swap, mount EBS, clone repo, compose up
  terraform.tfvars.example
stack/                      # runs on the host
  docker-compose.yml
  .env.example              # real .env never committed
  caddy/Caddyfile
  postgres/
    Dockerfile              # postgres + postgres_fdw
    init/                   # SQL: create dbs, roles, fdw, reporting schema + views
  forgejo/Dockerfile        # FROM official + overlay
  mattermost/Dockerfile     # FROM official + overlay
  plane/
    Dockerfile.api
    Dockerfile.web
    fork/                   # git submodule of the Plane fork
  postgrest/postgrest.conf
docs/superpowers/specs/     # this spec
```

## 6. Data Flow (BI layer — the key part)

1. Each app writes only to its **own database** (`forgejo`, `mattermost`, `plane`).
2. The `reporting` database uses **`postgres_fdw`**: foreign tables map to the
   three app databases' tables.
3. Curated **views** live in the `reporting` schema (e.g. `reporting.issues`,
   `reporting.commits`, `reporting.messages`, plus cross-system joins).
4. Role **`bi_reader`** has SELECT only on those views. PostgREST connects as an
   `authenticator` role and switches to `bi_reader`. When an app's internal schema
   changes between versions, only the views are adjusted — the public API contract
   does not break.
5. **Programmatic access (goal A)** uses each app's **native HTTP API** over HTTPS.
   PostgREST + `reporting` is strictly for **BI/analytics (goal B)** and is reached
   only via SSH tunnel.

### Why not expose app tables directly via PostgREST

App schemas are owned and migrated by the apps themselves; exposing them raw is
brittle (breaks on upstream version bumps) and insecure (their tables have no RLS
designed for external read). The `reporting` view layer is the stable, controlled
contract.

## 7. Provisioning Flow

1. `tofu apply` → key_pair, security group, EIP, **ECR repo**, data EBS volume
   (`delete_on_termination=false`), EC2 instance with `user-data.sh`.
2. (manual, once) build Plane image from the fork → push to ECR.
3. `user-data.sh` on first boot: install Docker + Compose, create 4 GB swap, mount
   the data EBS at `/data`, clone this repo, then wait for `.env` (owner fills it
   via scp/ssh).
4. `docker compose up -d` → Caddy fetches certs; Postgres runs `init/` SQL (create
   databases, roles, `postgres_fdw`, `reporting` schema + views).
5. Owner creates DNS A records on `code42.dev` (`git.`, `chat.`, `plane.`) → EIP.
6. Smoke test (see §9).

## 8. Security / Access Control

- **Auth:** A1 — independent per-app logins. No SSO.
- **Network:** N2.
  - Public: 80/443 (Caddy), 22 (SSH, security-group restricted to owner IP).
  - Closed: Postgres, PostgREST, Studio bind to the Docker network only — no host
    port published. Access via `ssh -L <localport>:127.0.0.1:<svcport>`.
- **Secrets:** `.env` on host, `chmod 600`, in `.gitignore`. Postgres root, app
  secret keys, MinIO keys live there.
- **Data durability:** data EBS `delete_on_termination=false`. No backups (accepted).
- **BI role:** `bi_reader` is SELECT-only on `reporting` views; cannot reach app
  databases directly.

## 9. Testing / Verification

- `tofu validate` and `tofu plan` clean before apply.
- `docker compose config` lints without error.
- Smoke tests after `up`:
  - `curl -fsS https://git.code42.dev` (and `chat.`, `plane.`) return healthy.
  - TLS certs issued (no Caddy cert errors in logs).
  - Via SSH tunnel: `psql` into `reporting`, `SELECT` from each `reporting.*` view.
  - Via SSH tunnel: PostgREST endpoint returns rows for a `reporting` view.
- Verify Postgres has 4 databases + `postgres_fdw` extension + `reporting` schema.
- Verify no host-published ports for Postgres/PostgREST/Studio (`docker compose ps`).

## 10. Out of Scope (this phase)

- Metabase / Superset install (read-only role is left ready).
- SSO / federated identity.
- Automated backups.
- Multi-host / HA / autoscaling.
- CI pipeline for the Plane fork (image built manually for now).
