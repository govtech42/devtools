# Recipe: shared Postgres (APP_DBS, CREATEDB, extensions, init gotchas)

Our `apps/postgres` image (pgvector/pg16 + contrib) backs every group. One DB per
app, created by `apps/postgres/init/00-databases.sh`, driven by env.

## Add an app DB
```dotenv
APP_DBS=planka chatwoot          # space-separated, per group
CHATWOOT_DB=chatwoot
CHATWOOT_DB_USER=chatwoot
CHATWOOT_DB_PASSWORD=...
```
Init creates the DB+owner and grants `fdw_reader` SELECT on current + future tables.

## Gotcha 1 — app insists on creating its own DB
Rails (`db:chatwoot_prepare`) and Twenty run `CREATE DATABASE`. The app role lacks
CREATEDB → `permission denied to create database`. Fix:
```dotenv
CHATWOOT_DB_CREATEDB=1     # init runs: ALTER ROLE <user> CREATEDB
```
The app then finds its DB already exists and proceeds to migrate.

## Gotcha 2 — non-trusted extensions need a superuser
`CREATE EXTENSION vector` / `pg_stat_statements` fails for a normal role
(`Must be superuser`). Trusted ones (`uuid-ossp`, `pgcrypto`, `pg_trgm`) are fine.
Pre-create the non-trusted ones as superuser:
```dotenv
CHATWOOT_DB_EXTENSIONS=vector pg_stat_statements
TWENTY_DB_EXTENSIONS=vector uuid-ossp
```
Init runs `CREATE EXTENSION IF NOT EXISTS <e>` in the app DB; the app's later
`CREATE EXTENSION IF NOT EXISTS` is then a no-op.

## Gotcha 3 — init runs ONCE
`/docker-entrypoint-initdb.d` scripts run only on an **empty** data dir. After
editing init, wipe and re-init:
```bash
docker compose ... down && rm -rf "$DATA_ROOT/postgres" && mkdir -p "$DATA_ROOT/postgres" && docker compose ... up -d postgres
```
(Wiping the shared Postgres drops every app DB on that host — re-migrate the apps,
i.e. restart them, afterwards.)

## Gotcha 4 — psql `:'var'` is NOT substituted inside `DO $$ ... $$`
psql variable interpolation is skipped inside dollar-quoted strings. Create roles
with `\gexec` and set the password in plain SQL:
```sql
SELECT 'CREATE ROLE authenticator LOGIN NOINHERIT'
  WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticator')\gexec
ALTER ROLE authenticator PASSWORD :'authn_pass';   -- plain SQL: substituted
```
