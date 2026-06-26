# Recipe: reporting views over app DBs (postgres_fdw)

Each host's `reporting` DB pulls app tables via `postgres_fdw` into curated,
read-only views exposed by PostgREST. App tables are upstream-owned — never wire BI
to them directly; the views are the stable seam.

## Pattern (per app)
`apps/<app>/reporting-<app>.sql`, applied by `make reporting GROUP=<group>`:
```sql
\connect reporting
-- server + user mapping (idempotent; :'fdw_pass' in plain SQL, not in a DO block)
SELECT format('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L, port %L)',
              'app_srv','localhost','<appdb>','5432')
  WHERE NOT EXISTS (SELECT FROM pg_foreign_server WHERE srvname='app_srv')\gexec
SELECT format('CREATE USER MAPPING FOR CURRENT_USER SERVER %I OPTIONS (user %L, password %L)',
              'app_srv','fdw_reader',:'fdw_pass')
  WHERE NOT EXISTS (SELECT FROM pg_user_mappings WHERE srvname='app_srv' AND usename=current_user)\gexec
CREATE SCHEMA IF NOT EXISTS app_src;
-- explicit foreign table, minimal columns
CREATE FOREIGN TABLE IF NOT EXISTS app_src.things (id bigint, name text, created_at timestamptz)
  SERVER app_srv OPTIONS (schema_name 'public', table_name 'things');
CREATE OR REPLACE VIEW reporting.things AS SELECT id, name, created_at FROM app_src.things;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO bi_reader;
```

## Gotcha — `IMPORT FOREIGN SCHEMA` breaks on custom types
Mattermost's `channels` has a `channel_type` enum; `IMPORT FOREIGN SCHEMA` tries to
recreate the type locally and fails (`type "public.channel_type" does not exist`).
**Declare explicit foreign tables with a minimal column list and map enums to `text`**
— enums travel as text over the wire. This is also more curated (only the columns BI
needs).

## Gotcha — confirm columns against the LIVE schema
App schemas drift between versions. Before writing the foreign table:
```bash
docker compose ... exec -T postgres psql -U postgres -d <appdb> \
  -tAc "SELECT string_agg(column_name,',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_name='things' AND table_schema='public'"
```

## Dynamic-schema apps (Twenty) → defer views
Twenty stores data in per-workspace dynamic schemas, so static foreign tables aren't
meaningful. Ship the reporting infra (server/PostgREST/Adminer) but **defer curated
views**; use the app's native API (Twenty GraphQL/REST) for programmatic access.
