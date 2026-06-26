# VPS Dev Tools — Admin Group Design Spec

**Date:** 2026-06-25
**Status:** Implemented (local, Colima) — Admin group
**Owner:** code42
**Parent:** `2026-06-25-vps-devtools-design.md` (§11 group model)

## Goal

Add the **Admin** group — **Twenty CRM** — on its own Lightsail host, on the
standard shared Postgres. Mirrors Dev/Support patterns (reuse `apps/` + `infra/`,
group-parametrized Postgres, per-group reporting infra, N2, Colima local).

## Locked decisions (by precedent)

| Item | Decision |
|---|---|
| Host | Lightsail **8 GB `large_2_0`**, us-east-1, self-contained |
| App | **Twenty CRM** — official multi-arch image (`twentycrm/twenty`), overlay-later (no fork now) |
| DB | shared Postgres `twenty` via `APP_DBS=twenty`; Twenty self-creates (`TWENTY_DB_CREATEDB=1`) + needs `vector`/`uuid-ossp` (`TWENTY_DB_EXTENSIONS`) |
| Redis | own `twenty-redis` (Valkey, `--maxmemory-policy noeviction`) |
| Storage | local disk volume (`STORAGE_TYPE=local`) |
| Domain | `crm.code42.dev` |
| Auth / Network | A1 / N2 |
| Reporting | per-group infra (Postgres FDW + PostgREST + Adminer) present; **curated Twenty views deferred** — Twenty's data model is dynamic (metadata-driven, per-workspace schemas). Programmatic access (goal A) via Twenty's native GraphQL/REST API |

## Services (`deploy/admin/docker-compose.yml`)

caddy · postgres (`APP_DBS=twenty`) · twenty-redis · twenty-server (migrates on
boot) · twenty-worker (`yarn worker:prod`, `DISABLE_DB_MIGRATIONS=true`) · postgrest
· adminer. Twenty server+worker share an `x-twenty` env anchor (worker repeats env
+ the migration flag — YAML merge is shallow).

## Gotchas captured (so future installs don't repeat them)

1. **Twenty calls `CREATE DATABASE`** on setup → its role needs **CREATEDB**
   (`TWENTY_DB_CREATEDB=1`); it tolerates "already exists" and proceeds to migrate.
2. **`vector` is not a trusted extension** → must be **pre-created by a superuser**
   in the app DB (`TWENTY_DB_EXTENSIONS="vector uuid-ossp"`); `uuid-ossp` is trusted
   and Twenty creates it itself.
3. **Twenty writes `/app/docker-data/db_status`** to mark setup done → mount a
   writable volume there, else setup re-runs on every restart.

These are encoded in the reusable `apps/postgres/init/00-databases.sh` conventions
(`<APP>_DB_CREATEDB`, `<APP>_DB_EXTENSIONS`) and the compose volume.

## Verification (done locally)

`make up GROUP=admin` + `make smoke GROUP=admin` → 11/0: postgres `twenty`/`reporting`
DBs, `vector`+`uuid-ossp` in `twenty`, role CREATEDB, twenty-server `/healthz`
(24 core/metadata tables migrated, GraphQL+REST mapped), twenty-worker running,
PostgREST reachable, N2 (no host ports).

## Out of scope

Curated Twenty BI views (dynamic schema); fork/branding overlay; cross-host BI;
Monitoring group.
