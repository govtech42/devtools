# twenty — CRM (overlay)

Uses the official `twentycrm/twenty` image directly (multi-arch: arm64 + amd64, so
it runs native on the Colima dev box and on the VPS). DB: shared Postgres `twenty`.

- **Services:** `twenty-server` (NestJS + front, port 3000, runs DB migrations on
  boot) + `twenty-worker` (`yarn worker:prod`, `DISABLE_DB_MIGRATIONS=true`) +
  `twenty-redis` (Valkey, `noeviction`). Redis is Twenty-owned.
- **Env:** `PG_DATABASE_URL`, `REDIS_URL`, `SERVER_URL`, `APP_SECRET`,
  `STORAGE_TYPE=local` (attachments on a `/data/twenty` volume).
- **Native API (goal A):** Twenty's GraphQL + REST API at `https://crm.code42.dev`.
- **Health:** `GET /healthz`.
- **Branding/overlay later:** if we customize, add an `apps/twenty/Dockerfile`
  (`FROM twentycrm/twenty:<tag>` + asset COPY) and point the compose `image` at a
  GHCR build — same fork/overlay pattern as the other apps. Not needed now.
- **Reporting:** curated BI views are **deferred** — Twenty's data model is dynamic
  (metadata-driven, per-workspace schemas), so static FDW foreign tables aren't
  meaningful. Use the native API for programmatic access.
