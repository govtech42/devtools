# VPS Dev Tools (Support Group) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Support group — Planka (kanban) and Chatwoot (helpdesk, WhatsApp Cloud API) — on a second Lightsail 8 GB host, with shared Postgres, MinIO attachments, and a per-group PostgREST `reporting` layer.

**Architecture:** Reuse the shared `apps/` contexts and `infra/` provisioning from the Dev group. The shared Postgres image and init are parameterized by group (`APP_DBS`) and gain `pgvector` (Chatwoot needs the `vector` extension). A new `deploy/support/` composition runs Caddy + Postgres + Planka + Chatwoot (web/sidekiq/init + own Redis) + MinIO + PostgREST + Adminer. Chatwoot is our fork (built off-host → GHCR); locally it runs the official image to validate wiring before the fork's Kanban work. N2 network model throughout.

**Tech Stack:** AWS Lightsail, Docker Compose, Caddy, PostgreSQL 16 + pgvector + postgres_fdw, Planka, Chatwoot (Rails + Sidekiq), Valkey, MinIO, PostgREST, Adminer, Colima (local).

## Global Constraints

- Host: AWS Lightsail **8 GB `large_2_0`**, Ubuntu 24.04, `us-east-1`.
- Network **N2**: only 22 (owner IP), 80, 443 public. Postgres/PostgREST/Adminer/MinIO publish **no host port** (SSH tunnel).
- Secrets in `deploy/support/.env`, `chmod 600`, gitignored. No `:latest` in production image tags (pin).
- Chatwoot is built off-host → **GHCR**, host pulls. Never build on host. Locally use the official `chatwoot/chatwoot` image to validate wiring.
- Domains: `board.code42.dev` → Planka, `support.code42.dev` → Chatwoot.
- Data under `/data` (VPS) / `<repo>/.data` (local) via `DATA_ROOT`. No backups.
- Compose: `deploy/support/docker-compose.yml`. Lint every change: `docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env config -q`.
- Reuse, don't fork: shared `apps/caddy`, `apps/postgres`, `apps/postgrest`, `apps/adminer`, `infra/scripts/`.

---

### Task 1: Parameterize shared Postgres by group + add pgvector

**Files:**
- Modify: `apps/postgres/Dockerfile`
- Modify: `apps/postgres/init/00-databases.sh`
- Modify: `deploy/dev/docker-compose.yml` (postgres service: add `APP_DBS`)
- Modify: `deploy/dev/.env.example` (document `APP_DBS`)

**Interfaces:**
- Produces: a Postgres image with `pgvector` + `postgres_fdw`; `00-databases.sh` creates one DB+owner per name in `APP_DBS`, reading `<NAME>_DB`/`<NAME>_DB_USER`/`<NAME>_DB_PASSWORD` by convention; reporting + `fdw_reader` grants loop over the same `APP_DBS`.

- [ ] **Step 1: Switch the base image to pgvector (keeps postgres_fdw)**

`apps/postgres/Dockerfile`:
```dockerfile
FROM pgvector/pgvector:pg16
# pgvector image = postgres:16 + the `vector` extension + bundled contrib
# (postgres_fdw). Chatwoot requires `vector`; Forgejo/Mattermost/Plane ignore it.
```

- [ ] **Step 2: Make `00-databases.sh` group-driven** (replace the hardcoded app list)

`apps/postgres/init/00-databases.sh`:
```bash
#!/usr/bin/env bash
# Create one DB + owner per name in APP_DBS (space-separated), the reporting DB,
# and fdw_reader. Per-app creds read by convention: <UPPER>_DB / _DB_USER / _DB_PASSWORD.
set -euo pipefail
APP_DBS="${APP_DBS:-}"

su() { psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres "$@"; }

create_role_db() {  # db user password
  local db="$1" user="$2" pass="$3"
  su <<-SQL
	DO \$\$ BEGIN
	  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${user}') THEN
	    CREATE ROLE ${user} LOGIN PASSWORD '${pass}';
	  END IF;
	END \$\$;
	SELECT 'CREATE DATABASE ${db} OWNER ${user}'
	  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db}')\gexec
	SQL
}

grant_reader() {  # db appuser
  local db="$1" appuser="$2"
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<-SQL
	GRANT CONNECT ON DATABASE ${db} TO fdw_reader;
	GRANT USAGE ON SCHEMA public TO fdw_reader;
	GRANT SELECT ON ALL TABLES IN SCHEMA public TO fdw_reader;
	ALTER DEFAULT PRIVILEGES FOR ROLE ${appuser} IN SCHEMA public GRANT SELECT ON TABLES TO fdw_reader;
	SQL
}

# reporting DB + fdw_reader first
su <<-SQL
	SELECT 'CREATE DATABASE ${REPORTING_DB} OWNER ${POSTGRES_USER}'
	  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${REPORTING_DB}')\gexec
	DO \$\$ BEGIN
	  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fdw_reader') THEN
	    CREATE ROLE fdw_reader LOGIN PASSWORD '${FDW_READER_PASSWORD}';
	  END IF;
	END \$\$;
	SQL

for name in $APP_DBS; do
  up=$(echo "$name" | tr '[:lower:]' '[:upper:]')
  db_var="${up}_DB"; user_var="${up}_DB_USER"; pass_var="${up}_DB_PASSWORD"
  db="${!db_var}"; user="${!user_var}"; pass="${!pass_var}"
  create_role_db "$db" "$user" "$pass"
  grant_reader "$db" "$user"
done

echo "00-databases: created [$APP_DBS] + reporting + fdw_reader"
```

- [ ] **Step 3: Pass `APP_DBS` in the Dev compose** — in `deploy/dev/docker-compose.yml` postgres `environment:` add:
```yaml
      APP_DBS: "forgejo mattermost plane"
```
And add `APP_DBS=forgejo mattermost plane` to `deploy/dev/.env.example` (documentation).

- [ ] **Step 4: Verify Dev still initializes cleanly** (regression)

```bash
docker compose -f deploy/dev/docker-compose.yml --env-file deploy/dev/.env down
rm -rf .data/postgres && mkdir -p .data/postgres
docker compose -f deploy/dev/docker-compose.yml --env-file deploy/dev/.env up -d --build postgres
sleep 8
docker compose -f deploy/dev/docker-compose.yml --env-file deploy/dev/.env exec -T postgres psql -U postgres -c "\l" | grep -E 'forgejo|mattermost|plane|reporting'
docker compose -f deploy/dev/docker-compose.yml --env-file deploy/dev/.env exec -T postgres psql -U postgres -d reporting -c "CREATE EXTENSION IF NOT EXISTS vector; SELECT extname FROM pg_extension WHERE extname IN ('vector','postgres_fdw');"
```
Expected: 4 Dev DBs present; both `vector` and `postgres_fdw` available.

- [ ] **Step 5: Commit**

```bash
git add apps/postgres deploy/dev/docker-compose.yml deploy/dev/.env.example
git commit -m "refactor(postgres): group-driven APP_DBS + pgvector base (Chatwoot needs vector)"
```

---

### Task 2: deploy/support compose base + env + group-aware smoke

**Files:**
- Create: `deploy/support/docker-compose.yml`
- Create: `deploy/support/.env.example`
- Create: `deploy/support/.env` (local, gitignored)
- Modify: `Makefile` (datadirs covers support dirs)
- Modify: `test/smoke.sh` (dispatch dev vs support checks)

**Interfaces:**
- Produces: a Support composition with Caddy + Postgres (APP_DBS="planka chatwoot"); `make GROUP=support up/smoke` works.

- [ ] **Step 1: `deploy/support/.env.example`**

```dotenv
DATA_ROOT=/data
APP_DBS=planka chatwoot

POSTGRES_SUPER_USER=postgres
POSTGRES_SUPER_PASSWORD=change-me-super
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

PLANKA_DB=planka
PLANKA_DB_USER=planka
PLANKA_DB_PASSWORD=change-me-planka

CHATWOOT_DB=chatwoot
CHATWOOT_DB_USER=chatwoot
CHATWOOT_DB_PASSWORD=change-me-chatwoot

REPORTING_DB=reporting
FDW_READER_PASSWORD=change-me-fdw
BI_AUTHENTICATOR_PASSWORD=change-me-authn
PGRST_JWT_SECRET=change-me-32char-min-secret-string

ACME_EMAIL=admin@analyticsbi.cloud
PLANKA_DOMAIN=board.code42.dev
CHATWOOT_DOMAIN=support.code42.dev

# Planka
PLANKA_SECRET_KEY=change-me-planka-secret
PLANKA_ADMIN_EMAIL=admin@code42.dev
PLANKA_ADMIN_PASSWORD=change-me-admin
PLANKA_ADMIN_NAME=Admin
PLANKA_ADMIN_USERNAME=admin

# Chatwoot
CHATWOOT_IMAGE=chatwoot/chatwoot:v3.16.0        # local: official; VPS: ghcr.io/code42/chatwoot:code42-x.y.z
CHATWOOT_SECRET_KEY_BASE=change-me-64-hex
CHATWOOT_REDIS_PASSWORD=change-me-redis
# WhatsApp Cloud API creds are entered in the Chatwoot UI; webhook lands on CHATWOOT_DOMAIN

# MinIO (Chatwoot attachments)
MINIO_ROOT_USER=chatwoot
MINIO_ROOT_PASSWORD=change-me-minio
CHATWOOT_S3_BUCKET=chatwoot

# GHCR (Chatwoot fork images, VPS)
GHCR_USER=code42
GHCR_TOKEN=change-me-ghcr-pat
```

- [ ] **Step 2: `deploy/support/docker-compose.yml` base** (Caddy + Postgres; reuse shared contexts)

```yaml
name: devtools-support

networks:
  net:

volumes:
  caddy_data:
    driver: local
    driver_opts: { type: none, o: bind, device: "${DATA_ROOT}/caddy/data" }
  caddy_config:
    driver: local
    driver_opts: { type: none, o: bind, device: "${DATA_ROOT}/caddy/config" }
  postgres_data:
    driver: local
    driver_opts: { type: none, o: bind, device: "${DATA_ROOT}/postgres" }

services:
  caddy:
    build: ../../apps/caddy
    image: devtools/caddy:0.1.0
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    env_file: [.env]
    volumes:
      - ../../apps/caddy/Caddyfile.support:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks: [net]

  postgres:
    build: ../../apps/postgres
    image: devtools/postgres:0.1.0
    restart: unless-stopped
    env_file: [.env]
    environment:
      POSTGRES_USER: ${POSTGRES_SUPER_USER}
      POSTGRES_PASSWORD: ${POSTGRES_SUPER_PASSWORD}
      POSTGRES_DB: postgres
      APP_DBS: ${APP_DBS}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ../../apps/postgres/init:/docker-entrypoint-initdb.d:ro
    networks: [net]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_SUPER_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
```

- [ ] **Step 3: Support Caddyfile** — create `apps/caddy/Caddyfile.support`:

```caddyfile
{
	email {$ACME_EMAIL}
}

{$PLANKA_DOMAIN} {
	reverse_proxy planka:1337
}

{$CHATWOOT_DOMAIN} {
	reverse_proxy chatwoot-web:3000
}
```
> Planka listens on 1337; Chatwoot rails on 3000.

- [ ] **Step 4: Makefile `datadirs` covers support paths** — it already creates a fixed set; extend it to also make support-specific dirs idempotently:
```make
	  mkdir -p "$$DATA_ROOT"/planka "$$DATA_ROOT"/chatwoot/storage \
	           "$$DATA_ROOT"/minio "$$DATA_ROOT"/chatwoot/redis ;
```
(append inside the existing `datadirs` recipe's `mkdir -p` list).

- [ ] **Step 5: Make `test/smoke.sh` group-aware** — wrap the existing Dev checks in `if [ "$GROUP" = dev ]`, add a `support` branch. Keep shared helpers (psql_super, http, N2). Add at the top after helpers:
```bash
if [ "$GROUP" = support ]; then
  # Postgres
  if running postgres; then
    check "postgres accepts connections" dc exec -T postgres pg_isready -U postgres
    for db in planka chatwoot reporting; do
      check_eq "database '$db' exists" "1" psql_super postgres "SELECT 1 FROM pg_database WHERE datname='$db'"
    done
    check_eq "pgvector available" "vector" psql_super postgres "SELECT extname FROM pg_extension WHERE extname='vector' UNION SELECT 'vector' WHERE EXISTS (SELECT 1 FROM pg_available_extensions WHERE name='vector') LIMIT 1"
  else skip "postgres not running"; fi
  # Planka
  running planka && check "planka responds" http http://planka:1337/ || skip "planka not running"
  # Chatwoot
  running chatwoot-web && check "chatwoot /api responds" http http://chatwoot-web:3000/api || skip "chatwoot-web not running"
  # MinIO
  running minio && check "minio live" http http://minio:9000/minio/health/live || skip "minio not running"
  # reporting + postgrest + N2 (same as dev tail)
  running postgrest && check "postgrest serves a reporting view" http "http://postgrest:3000/kanban_cards?limit=1" || skip "postgrest not running"
  bad="$(dc ps --format '{{.Service}} {{.Ports}}' 2>/dev/null | grep -E 'postgres|postgrest|adminer|minio' | grep -E '0\.0\.0\.0:|\[::\]:' || true)"
  [ -z "$bad" ] && pass "N2: no published host ports on db/postgrest/adminer/minio" || fail "N2 violated" "$bad"
  summary; exit $?
fi
```
(The `NET` var already derives from `devtools-${GROUP}_net`.)

- [ ] **Step 6: Create local `deploy/support/.env`** from the example with local values (`DATA_ROOT=<repo>/.data-support`, simple passwords, `CHATWOOT_IMAGE=chatwoot/chatwoot:v3.16.0`). Use a **separate** local data root `<repo>/.data-support` so Dev and Support don't collide locally.

> Update `deploy/support/docker-compose.yml`-referenced `DATA_ROOT` in local `.env`
> to an absolute `<repo>/.data-support` path; add `.data-support/` to `.gitignore`.

- [ ] **Step 7: Lint + boot Postgres for support + smoke**

```bash
make lint GROUP=support
docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env up -d --build postgres
sleep 8
make smoke GROUP=support   # expect postgres/planka/chatwoot/reporting DB checks; apps skipped
```
Expected: `planka`, `chatwoot`, `reporting` DBs exist; pgvector available.

- [ ] **Step 8: Commit**

```bash
git add deploy/support apps/caddy/Caddyfile.support Makefile test/smoke.sh .gitignore
git commit -m "feat(support): compose base (Caddy+Postgres), env, group-aware smoke"
```

---

### Task 3: Planka (overlay + branding)

**Files:**
- Create: `apps/planka/Dockerfile`
- Create: `apps/planka/README.md`
- Create: `apps/planka/branding/.gitkeep`
- Modify: `deploy/support/docker-compose.yml` (add `planka` + volume)

**Interfaces:**
- Consumes: Postgres `planka` DB. Produces: Planka on `planka:1337`, data at `/data/planka`.

- [ ] **Step 1: `apps/planka/Dockerfile`**

```dockerfile
FROM ghcr.io/plankanban/planka:2.0.0
# Branding overlay (logos/assets). Public assets live under the app's static dir;
# copy overrides here, e.g.:
# COPY branding/ /app/public/
```

- [ ] **Step 2: `apps/planka/README.md`**

```markdown
# planka — kanban (overlay + branding)
Overlays ghcr.io/plankanban/planka. DB: shared Postgres `planka`. Listens on 1337.
Branding via files in `branding/` copied into the image's static assets.
Native API used for goal-A access; first admin from DEFAULT_ADMIN_* env.
```

- [ ] **Step 3: Add the volume + service** to `deploy/support/docker-compose.yml`

volume:
```yaml
  planka_data:
    driver: local
    driver_opts: { type: none, o: bind, device: "${DATA_ROOT}/planka" }
```
service:
```yaml
  planka:
    build: ../../apps/planka
    image: devtools/planka:0.1.0
    restart: unless-stopped
    depends_on:
      postgres: { condition: service_healthy }
    env_file: [.env]
    environment:
      DATABASE_URL: "postgresql://${PLANKA_DB_USER}:${PLANKA_DB_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${PLANKA_DB}"
      BASE_URL: https://${PLANKA_DOMAIN}
      SECRET_KEY: ${PLANKA_SECRET_KEY}
      DEFAULT_ADMIN_EMAIL: ${PLANKA_ADMIN_EMAIL}
      DEFAULT_ADMIN_PASSWORD: ${PLANKA_ADMIN_PASSWORD}
      DEFAULT_ADMIN_NAME: ${PLANKA_ADMIN_NAME}
      DEFAULT_ADMIN_USERNAME: ${PLANKA_ADMIN_USERNAME}
    volumes:
      - planka_data:/app/private/data
    networks: [net]
```

- [ ] **Step 4: Boot + smoke**

```bash
docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env up -d --build planka
sleep 12
make smoke GROUP=support   # planka check should pass
docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env exec -T postgres psql -U postgres -d planka -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'"
```
Expected: Planka responds on 1337; `planka` DB has tables (Planka migrates on boot).

- [ ] **Step 5: Commit**

```bash
git add apps/planka deploy/support/docker-compose.yml
git commit -m "feat(planka): kanban on shared Postgres (overlay + branding hook)"
```

---

### Task 4: Chatwoot (fork scaffold) + web/sidekiq/init + Redis + MinIO

**Files:**
- Create: `apps/chatwoot/README.md`, `apps/chatwoot/CHANGES.md`, `apps/chatwoot/.env.chatwoot.example`
- Create: `apps/chatwoot/reporting-chatwoot.sql`
- Modify: `deploy/support/docker-compose.yml` (chatwoot-web, chatwoot-sidekiq, chatwoot-init, chatwoot-redis, minio + volumes)

**Interfaces:**
- Consumes: Postgres `chatwoot` DB (pgvector), MinIO bucket `chatwoot`. Produces: Chatwoot web on `chatwoot-web:3000`; data on `/data/chatwoot`, `/data/minio`.

- [ ] **Step 1: Fork docs** — `apps/chatwoot/README.md`:

```markdown
# chatwoot — helpdesk (OUR FORK)
Fork chatwoot/chatwoot -> github.com/code42/chatwoot, submodule apps/chatwoot/upstream
(branch code42). We add Kanban + product features (log in CHANGES.md).
Build OFF-HOST -> GHCR -> host pulls. Locally, CHATWOOT_IMAGE defaults to the
official image to validate wiring before the fork work.
DB: shared Postgres `chatwoot` (needs pgvector). Redis: own (Sidekiq).
Storage: MinIO (bucket chatwoot) via Active Storage S3.
WhatsApp: Cloud API (official) — add the channel in the UI; webhook -> support.code42.dev.
Migrations: chatwoot-init runs `bundle exec rails db:chatwoot_prepare` once.
```

`apps/chatwoot/CHANGES.md`:
```markdown
# Chatwoot fork — divergences from upstream
Branch `code42` off upstream. Log each change: file, what, why, upstreamable?

| Date | File(s) | Change | Why | Upstreamable |
|------|---------|--------|-----|--------------|
| 2026-06-25 | deploy compose (ours) | external Postgres `chatwoot` + MinIO storage | shared Postgres + S3 attachments | no (deploy) |
```

- [ ] **Step 2: `apps/chatwoot/.env.chatwoot.example`** (reference; supplied via compose env)

```dotenv
SECRET_KEY_BASE=${CHATWOOT_SECRET_KEY_BASE}
FRONTEND_URL=https://${CHATWOOT_DOMAIN}
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker
POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_USERNAME=${CHATWOOT_DB_USER}
POSTGRES_PASSWORD=${CHATWOOT_DB_PASSWORD}
POSTGRES_DATABASE=${CHATWOOT_DB}
REDIS_URL=redis://:${CHATWOOT_REDIS_PASSWORD}@chatwoot-redis:6379
ACTIVE_STORAGE_SERVICE=s3_compatible
STORAGE_BUCKET_NAME=${CHATWOOT_S3_BUCKET}
STORAGE_ACCESS_KEY_ID=${MINIO_ROOT_USER}
STORAGE_SECRET_ACCESS_KEY=${MINIO_ROOT_PASSWORD}
STORAGE_REGION=us-east-1
STORAGE_ENDPOINT=http://minio:9000
STORAGE_FORCE_PATH_STYLE=true
```
> Confirm the exact storage var names against the fork's `.env.example` (Chatwoot
> has used both `S3_*` and `STORAGE_*` across versions). Adjust in Step 3 env if needed.

- [ ] **Step 3: Compose volumes + Chatwoot/MinIO services** in `deploy/support/docker-compose.yml`

Add a backend anchor near the top (after `name:`):
```yaml
x-chatwoot: &chatwoot
  image: ${CHATWOOT_IMAGE}
  restart: unless-stopped
  env_file: [.env]
  environment:
    SECRET_KEY_BASE: ${CHATWOOT_SECRET_KEY_BASE}
    FRONTEND_URL: "https://${CHATWOOT_DOMAIN}"
    RAILS_ENV: production
    NODE_ENV: production
    INSTALLATION_ENV: docker
    POSTGRES_HOST: ${POSTGRES_HOST}
    POSTGRES_PORT: ${POSTGRES_PORT}
    POSTGRES_USERNAME: ${CHATWOOT_DB_USER}
    POSTGRES_PASSWORD: ${CHATWOOT_DB_PASSWORD}
    POSTGRES_DATABASE: ${CHATWOOT_DB}
    REDIS_URL: "redis://:${CHATWOOT_REDIS_PASSWORD}@chatwoot-redis:6379"
    ACTIVE_STORAGE_SERVICE: s3_compatible
    STORAGE_BUCKET_NAME: ${CHATWOOT_S3_BUCKET}
    STORAGE_ACCESS_KEY_ID: ${MINIO_ROOT_USER}
    STORAGE_SECRET_ACCESS_KEY: ${MINIO_ROOT_PASSWORD}
    STORAGE_REGION: us-east-1
    STORAGE_ENDPOINT: "http://minio:9000"
    STORAGE_FORCE_PATH_STYLE: "true"
  networks: [net]
```
volumes:
```yaml
  chatwoot_storage:
    driver: local
    driver_opts: { type: none, o: bind, device: "${DATA_ROOT}/chatwoot/storage" }
  chatwoot_redis:
    driver: local
    driver_opts: { type: none, o: bind, device: "${DATA_ROOT}/chatwoot/redis" }
  minio_data:
    driver: local
    driver_opts: { type: none, o: bind, device: "${DATA_ROOT}/minio" }
```
services:
```yaml
  chatwoot-redis:
    image: valkey/valkey:7.2-alpine
    restart: unless-stopped
    command: ["valkey-server", "--requirepass", "${CHATWOOT_REDIS_PASSWORD}"]
    volumes: [chatwoot_redis:/data]
    networks: [net]

  minio:
    image: minio/minio:RELEASE.2025-01-20T14-49-07Z
    restart: unless-stopped
    command: server /data --console-address ":9090"
    env_file: [.env]
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes: [minio_data:/data]
    networks: [net]          # N2: no host port

  minio-init:
    image: minio/mc:latest
    depends_on: [minio]
    env_file: [.env]
    entrypoint: >
      /bin/sh -c "
      until mc alias set m http://minio:9000 $$MINIO_ROOT_USER $$MINIO_ROOT_PASSWORD; do sleep 2; done;
      mc mb -p m/$$CHATWOOT_S3_BUCKET || true; echo bucket-ready"
    restart: "no"
    networks: [net]

  chatwoot-init:
    <<: *chatwoot
    restart: "no"
    depends_on:
      postgres: { condition: service_healthy }
    command: ["bundle", "exec", "rails", "db:chatwoot_prepare"]

  chatwoot-web:
    <<: *chatwoot
    depends_on:
      chatwoot-init: { condition: service_completed_successfully }
      chatwoot-redis: { condition: service_started }
      minio-init: { condition: service_completed_successfully }
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]

  chatwoot-sidekiq:
    <<: *chatwoot
    depends_on:
      chatwoot-web: { condition: service_started }
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
```

- [ ] **Step 4: Boot the Chatwoot stack locally (official image) + smoke**

```bash
# Chatwoot image is amd64; on the arm64 dev box it runs under Rosetta (platform pinned by image).
docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env up -d \
  postgres chatwoot-redis minio minio-init chatwoot-init
docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env logs --tail=20 chatwoot-init   # migrations OK, exits 0
docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env up -d chatwoot-web chatwoot-sidekiq
# Chatwoot boots slowly; retry-poll:
for i in $(seq 1 40); do docker run --rm --network devtools-support_net curlimages/curl:8.10.1 -fsS --max-time 5 http://chatwoot-web:3000/api >/dev/null 2>&1 && { echo up; break; }; sleep 5; done
make smoke GROUP=support
```
Expected: `chatwoot-init` exits 0 (schema loaded into `chatwoot` DB); `chatwoot-web` `/api` responds; bucket `chatwoot` exists; smoke green.

- [ ] **Step 5: `apps/chatwoot/reporting-chatwoot.sql`** (FDW + views; columns confirmed from the live `chatwoot` schema in Task 6)

```sql
\connect reporting
SELECT format('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L, port %L)',
              'chatwoot_srv','localhost','chatwoot','5432')
  WHERE NOT EXISTS (SELECT FROM pg_foreign_server WHERE srvname='chatwoot_srv')\gexec
SELECT format('CREATE USER MAPPING FOR CURRENT_USER SERVER %I OPTIONS (user %L, password %L)',
              'chatwoot_srv','fdw_reader',:'fdw_pass')
  WHERE NOT EXISTS (SELECT FROM pg_user_mappings WHERE srvname='chatwoot_srv' AND usename=current_user)\gexec
CREATE SCHEMA IF NOT EXISTS chatwoot_src;
CREATE FOREIGN TABLE IF NOT EXISTS chatwoot_src.conversations (
  id bigint, account_id bigint, inbox_id bigint, status integer, created_at timestamptz
) SERVER chatwoot_srv OPTIONS (schema_name 'public', table_name 'conversations');
CREATE OR REPLACE VIEW reporting.support_conversations AS
  SELECT id, account_id, inbox_id, status, created_at FROM chatwoot_src.conversations;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO bi_reader;
```
> Confirm `conversations` columns against the live schema before applying; adjust the
> foreign-table column list to match (enum/integer status varies by version).

- [ ] **Step 6: Commit**

```bash
git add apps/chatwoot deploy/support/docker-compose.yml
git commit -m "feat(chatwoot): helpdesk stack (web/sidekiq/init + Redis + MinIO), fork scaffold"
```

---

### Task 5: Reporting (Planka + Chatwoot) + PostgREST + Adminer

**Files:**
- Create: `apps/planka/reporting-planka.sql`
- Modify: `deploy/support/docker-compose.yml` (postgrest + adminer)
- Modify: `Makefile` (`reporting` works for support; applies both SQL files)

**Interfaces:**
- Produces: `reporting.kanban_cards` (Planka), `reporting.support_conversations` (Chatwoot); PostgREST + Adminer (N2).

- [ ] **Step 1: `apps/planka/reporting-planka.sql`** (confirm Planka card table/columns from live schema)

```sql
\connect reporting
SELECT format('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L, port %L)',
              'planka_srv','localhost','planka','5432')
  WHERE NOT EXISTS (SELECT FROM pg_foreign_server WHERE srvname='planka_srv')\gexec
SELECT format('CREATE USER MAPPING FOR CURRENT_USER SERVER %I OPTIONS (user %L, password %L)',
              'planka_srv','fdw_reader',:'fdw_pass')
  WHERE NOT EXISTS (SELECT FROM pg_user_mappings WHERE srvname='planka_srv' AND usename=current_user)\gexec
CREATE SCHEMA IF NOT EXISTS planka_src;
CREATE FOREIGN TABLE IF NOT EXISTS planka_src.card (
  id bigint, board_id bigint, list_id bigint, name text, created_at timestamptz
) SERVER planka_srv OPTIONS (schema_name 'public', table_name 'card');
CREATE OR REPLACE VIEW reporting.kanban_cards AS
  SELECT id, board_id, list_id, name, created_at FROM planka_src.card;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO bi_reader;
```

- [ ] **Step 2: Add postgrest + adminer** to `deploy/support/docker-compose.yml` (identical pattern to Dev)

```yaml
  postgrest:
    image: postgrest/postgrest:v12.2.3
    restart: unless-stopped
    depends_on:
      postgres: { condition: service_healthy }
    env_file: [.env]
    environment:
      PGRST_DB_URI: "postgres://authenticator:${BI_AUTHENTICATOR_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${REPORTING_DB}"
      PGRST_DB_SCHEMAS: "reporting"
      PGRST_DB_ANON_ROLE: "bi_reader"
      PGRST_JWT_SECRET: ${PGRST_JWT_SECRET}
    networks: [net]

  adminer:
    image: adminer:4
    restart: unless-stopped
    depends_on:
      postgres: { condition: service_healthy }
    networks: [net]
```

- [ ] **Step 3: Make `reporting` apply both support SQL files** — extend the Makefile `reporting` target so for `GROUP=support` it pipes `apps/planka/reporting-planka.sql` then `apps/chatwoot/reporting-chatwoot.sql`:
```make
reporting:
	@set -a; . $(DIR)/.env; set +a; \
	  if [ "$(GROUP)" = support ]; then \
	    for f in apps/planka/reporting-planka.sql apps/chatwoot/reporting-chatwoot.sql; do \
	      cat $$f | $(COMPOSE) exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres -d reporting -v fdw_pass="$$FDW_READER_PASSWORD"; done; \
	  else \
	    cat apps/postgres/reporting.sql | $(COMPOSE) exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres -d reporting -v fdw_pass="$$FDW_READER_PASSWORD"; \
	  fi
	@echo "reporting layer applied (GROUP=$(GROUP))"
```

- [ ] **Step 4: Confirm live columns, then apply + verify**

```bash
# inspect real columns first, adjust the two .sql foreign-table column lists if needed
docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env exec -T postgres \
  psql -U postgres -d planka -tAc "SELECT string_agg(column_name,',') FROM information_schema.columns WHERE table_name='card' AND table_schema='public'"
docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env exec -T postgres \
  psql -U postgres -d chatwoot -tAc "SELECT string_agg(column_name,',') FROM information_schema.columns WHERE table_name='conversations' AND table_schema='public'"
make reporting GROUP=support
docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env up -d postgrest adminer
sleep 5
make smoke GROUP=support
```
Expected: views `reporting.kanban_cards`, `reporting.support_conversations` readable; PostgREST serves `kanban_cards`; N2 clean.

- [ ] **Step 5: Commit**

```bash
git add apps/planka/reporting-planka.sql apps/chatwoot/reporting-chatwoot.sql deploy/support/docker-compose.yml Makefile
git commit -m "feat(support reporting): Planka + Chatwoot FDW views, PostgREST + Adminer (N2)"
```

---

### Task 6: Chatwoot fork (submodule) + GHCR build path + E2E + RUNBOOK

**Files:**
- Create: `apps/chatwoot/upstream/` (submodule), `apps/chatwoot/Dockerfile`
- Modify: `docs/RUNBOOK.md` (support group section)

**Interfaces:**
- Produces: the fork submodule + the documented off-host GHCR build; a verified Support stack.

- [ ] **Step 1: Add the fork submodule** (after the fork repo exists)

```bash
git submodule add https://github.com/code42/chatwoot.git apps/chatwoot/upstream
git -C apps/chatwoot/upstream remote add upstream https://github.com/chatwoot/chatwoot.git
git -C apps/chatwoot/upstream fetch --all
git -C apps/chatwoot/upstream checkout -b code42
```

- [ ] **Step 2: `apps/chatwoot/Dockerfile`** (build from the fork; base off upstream's own Dockerfile)

```dockerfile
# Build from the fork's source. Chatwoot ships a Dockerfile at the repo root;
# we build that, then our changes ride in the same image.
# Built OFF-HOST and pushed to GHCR; the host only pulls.
FROM chatwoot/chatwoot:v3.16.0
# Our fork's compiled changes are baked by building the fork image in CI;
# this file documents the pinned base for the overlay path. For the real fork
# build, run `docker buildx build` against apps/chatwoot/upstream (see README).
```

- [ ] **Step 3: Off-host GHCR build** (documented; run when the fork has changes)

```bash
export TAG=code42-0.1.0 U=apps/chatwoot/upstream
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
docker buildx build --platform linux/amd64 --push \
  -t ghcr.io/$GHCR_USER/chatwoot:$TAG -f $U/docker/Dockerfile $U
# then set CHATWOOT_IMAGE=ghcr.io/code42/chatwoot:code42-0.1.0 in the host .env
```

- [ ] **Step 4: Full clean E2E (local, official image)**

```bash
docker compose -f deploy/support/docker-compose.yml --env-file deploy/support/.env down
rm -rf .data-support && mkdir -p .data-support
make up GROUP=support
# wait for planka + chatwoot, then:
make reporting GROUP=support
make smoke GROUP=support
```
Expected: all Support smoke checks green (Postgres+pgvector, Planka, Chatwoot `/api`, MinIO, reporting views, PostgREST, N2).

- [ ] **Step 5: Update `docs/RUNBOOK.md`** — add a Support section:

```markdown
## Support group
make up GROUP=support && make reporting GROUP=support && make smoke GROUP=support
VPS: NAME=devtools-support BUNDLE=large_2_0 DISK_NAME=support-data bash infra/scripts/create-lightsail.sh
DNS: board./support.code42.dev -> support static IP
Chatwoot fork image: build off-host -> GHCR; set CHATWOOT_IMAGE on the host.
WhatsApp: add the Cloud API channel in Chatwoot UI; webhook -> https://support.code42.dev
```

- [ ] **Step 6: Commit**

```bash
git add apps/chatwoot docs/RUNBOOK.md .gitmodules
git commit -m "feat(chatwoot): fork submodule + GHCR build path; support E2E + RUNBOOK"
```

---

## Self-Review Notes

- **Spec coverage:** §2 host/build/WhatsApp/MinIO/BI → Tasks 1–6; §4 services table → Tasks 2–5; §5 repo additions → Tasks 2–6; §6 fork → Tasks 4,6; §7 wiring → Tasks 3,4; §8 reporting → Task 5; §9 security/N2 → smoke (Tasks 2,4,5); §10 testing → every task's smoke + Task 6 E2E. Out-of-scope (§11) excluded.
- **Known execution-time confirmations (not placeholders):** exact Chatwoot storage env names and the live column lists for `card`/`conversations` are confirmed against the running schema (Task 4 Step 2 note, Task 5 Step 4) before the SQL is applied — the plan names the inspection commands.
- **Pinned versions** (planka 2.0.0, chatwoot v3.16.0, valkey 7.2, minio, postgrest v12.2.3, adminer 4, pgvector pg16) — bump deliberately; no `:latest` in production image envs.
- **Reuse:** shared `apps/caddy|postgres|postgrest|adminer` + `infra/scripts` reused; Postgres init refactored once (Task 1) to serve all groups.
