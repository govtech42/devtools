---
name: onboard-app
description: Use when adding a new self-hosted app (or a new deployment group) to this VPS dev-tools repo — wiring it into a group's docker-compose, shared Postgres, Caddy, smoke, and reporting. Encodes the hard-won gotchas (non-trusted Postgres extensions, CREATEDB, init-once, psql DO-block vars, YAML brace, shallow compose-anchor merge, cross-arch builds, FDW enum handling) so installs don't rediscover them.
---

# Onboarding an app to the stack

Follow `docs/recipes/onboarding-a-new-app.md` (the checklist) and its deep-dives.
This skill is the short, must-not-forget version.

## Steps
1. **Group/host:** add to an existing `deploy/<group>/` or copy one for a new group. Account for idle RAM.
2. **Context `apps/<app>/`:** overlay official image if unmodified; **fork → GHCR** if we change code (submodule `upstream`, `code42` branch, `CHANGES.md`). Pin tags, never `:latest`, never build heavy apps on the host.
3. **Shared Postgres:** add to `APP_DBS` + `<APP>_DB[_USER|_PASSWORD]`.
4. **Compose:** block-style bind volume under `${DATA_ROOT}/<app>`; `x-<app>` anchor for multi-process images; Caddy route in `apps/caddy/Caddyfile.<group>`; no host port (N2).
5. **Smoke:** add checks to the group branch in `test/smoke.sh` (curl sidecar).
6. **Reporting (optional):** `apps/<app>/reporting-<app>.sql`, wire into Makefile.
7. **Verify:** `devtools up --<group> && devtools reporting --<group> && devtools smoke --<group>`.

## Gotchas (these WILL bite — pre-empt them)
- **Non-trusted extensions** (`vector`, `pg_stat_statements`) need superuser → set `<APP>_DB_EXTENSIONS`. Trusted (`uuid-ossp`, `pgcrypto`, `pg_trgm`) the app creates itself.
- App runs `CREATE DATABASE` (Rails/Twenty) → set `<APP>_DB_CREATEDB=1`.
- Postgres **init runs once** (empty data dir) — wipe `${DATA_ROOT}/postgres` to re-init after changing init scripts.
- psql **`:'var'` is not substituted inside `DO $$ … $$`** — use `\gexec` + plain `ALTER ROLE`.
- Compose **YAML flow map `{ … }` breaks on `${VAR}`** (the `}`) — use block style, or quote the value.
- Compose **`<<:` anchor merge is shallow** — a re-declared `environment:` replaces, not merges; repeat the full env.
- A migration/seed `*-init` service must `depends_on` Redis too if the seed clears cache.
- Persisted setup flags (Twenty `/app/docker-data/db_status`) need a writable volume or setup re-runs each boot.
- **amd64-only image on the arm64 dev box:** runs under Rosetta; building an overlay needs `docker buildx --platform linux/amd64 --load`. VPS builds native.
- **FDW reporting:** declare explicit foreign tables (enum→`text`); never `IMPORT FOREIGN SCHEMA` over tables with custom types. Dynamic-schema apps (Twenty) → defer views, use native API.

See `docs/recipes/` for the full explanations and copy-paste snippets.
