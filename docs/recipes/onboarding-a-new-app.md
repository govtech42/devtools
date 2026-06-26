# Recipe: onboarding a new app to a group

Checklist to add an app (e.g. a new service to Dev/Support/Admin, or a new group).
Each step links to the deep-dive where it bit us.

## 1. Pick the group / host
One Lightsail host per group; each is self-contained (own Caddy + Postgres +
reporting). New app → existing group's `deploy/<group>/docker-compose.yml`, or a new
`deploy/<group>/` (copy an existing one). Account for idle RAM (DECISIONS / spec).

## 2. App context under `apps/<app>/`
- **Official, unmodified** → overlay `Dockerfile` (`FROM <official:pinned>`) or use the
  image directly. **We modify the code** → fork (submodule `apps/<app>/upstream`,
  `code42` branch, `CHANGES.md`), build off-host → GHCR, host pulls. Never build heavy
  apps on the host (OOM).
- Pin image tags. No `:latest` in production env.

## 3. Database (shared Postgres)
Add the app to `APP_DBS` in `deploy/<group>/.env(.example)` and set
`<APP>_DB` / `_DB_USER` / `_DB_PASSWORD`. The init creates the DB+owner and grants
`fdw_reader`. **Two gotchas** ([postgres-shared-db.md](postgres-shared-db.md)):
- App self-creates its DB (Rails/Twenty `CREATE DATABASE`) → set `<APP>_DB_CREATEDB=1`.
- App needs a **non-trusted** extension (`vector`, `pg_stat_statements`) → set
  `<APP>_DB_EXTENSIONS="vector pg_stat_statements"` (pre-created as superuser; trusted
  ones like `uuid-ossp`/`pgcrypto`/`pg_trgm` the app can create itself).

## 4. Compose service
- Add the service + a bind volume under `${DATA_ROOT}/<app>` (NOT a `{ }` flow map —
  the `}` in `${DATA_ROOT}` breaks YAML; use block style).
- Multiple processes of one image (web/worker/init) → an `x-<app>` anchor. Remember
  **`<<:` merge is shallow**: a service that re-declares `environment:` REPLACES the
  anchor's map — repeat the full env if you override.
- A one-off migration/seed service (`*-init`) must `depends_on` everything its task
  touches — including **Redis** if the seed clears cache (Chatwoot bit us here).
- Persisted setup flags need a writable volume (Twenty's `/app/docker-data/db_status`),
  else setup re-runs every boot.

## 5. Caddy route
Add `{$<APP>_DOMAIN} { reverse_proxy <service>:<port> }` to the group's
`apps/caddy/Caddyfile.<group>`. Caddy is the only public ingress (N2). No host port
on the app — Caddy reaches it on the `net` network.

## 6. Smoke
Add the app's checks to the group branch in `test/smoke.sh` (HTTP via the curl
sidecar — many app images lack curl). Keep N2 assertion (no host ports on
postgres/postgrest/adminer/minio).

## 7. Reporting (optional)
Add `apps/<app>/reporting-<app>.sql` (explicit foreign tables, enum→text) and wire it
into the Makefile `reporting` target. Dynamic-schema apps (Twenty) → defer views, use
the app's native API. See [fdw-reporting.md](fdw-reporting.md).

## 8. Cross-arch
amd64-only image + arm64 dev box → it runs under Rosetta, but a local `docker build`
of an overlay needs **buildx** (`docker buildx build --platform linux/amd64 --load`).
The VPS builds natively. See [cross-arch-builds.md](cross-arch-builds.md).

## 9. Verify
`devtools up --<group> && devtools reporting --<group> && devtools smoke --<group>`.
Re-init Postgres (wipe `${DATA_ROOT}/postgres`) when changing init scripts — they run
**once**, only on an empty data dir.
