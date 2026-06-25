# VPS Dev Tools (Core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up an AWS Lightsail 16 GB host running Forgejo, Mattermost, and Plane in Docker with a shared Postgres and a curated PostgREST `reporting` API.

**Architecture:** One Lightsail instance provisioned by an AWS CLI script (no OpenTofu). Docker Compose runs every app; Caddy is the only public ingress with auto-TLS. A single Postgres holds one database per app plus a `reporting` database that pulls app tables via `postgres_fdw` and exposes curated read-only views through PostgREST. Plane is built from our GitHub fork and pulled from GHCR. Per-app contexts live under `apps/`; all host provisioning under `infra/`.

**Tech Stack:** AWS Lightsail, AWS CLI, Bash/cloud-init, Docker + Docker Compose, Caddy, PostgreSQL 16 + postgres_fdw, PostgREST, Adminer, Forgejo, Mattermost, Plane (Django + Next.js + Valkey + RabbitMQ + MinIO).

## Global Constraints

- Host: AWS Lightsail **16 GB plan**, bundle `xlarge_2_0`, blueprint Ubuntu 24.04, region `us-east-1`.
- Network model **N2**: only ports 22 (owner IP), 80, 443 are public. Postgres / PostgREST / Adminer publish **no host port** — reached via `ssh -L`.
- All secrets in `deploy/dev/.env` on the host, `chmod 600`, gitignored. **Never** commit `.env`, `*.tfvars`, `*.tfstate`. Never hardcode a secret in a Dockerfile/compose/committed config.
- Image tags are **pinned** — no `:latest` in compose.
- Plane is **built off-host** → pushed to **GHCR** → host only `docker pull`s. Never build Plane on the host.
- Domain `code42.dev`: `git.` → Forgejo, `chat.` → Mattermost, `plane.` → Plane proxy.
- Data lives under `/data` (attached Lightsail block disk). No backups exist — guard destructive commands.
- Compose file path: `deploy/dev/docker-compose.yml`. Lint every change with `docker compose -f deploy/dev/docker-compose.yml config`.

---

### Task 1: Repo skeleton, .env.example, compose base (Caddy + Postgres + networks/volumes)

**Files:**
- Create: `deploy/dev/docker-compose.yml`
- Create: `deploy/dev/.env.example`
- Create: `apps/README.md`
- Verify: `.gitignore` (already present) covers `deploy/dev/.env`

**Interfaces:**
- Produces: docker network `edge` (Caddy ↔ web apps) and `internal` (apps ↔ Postgres); named volumes rooted at `/data`; the `postgres` and `caddy` services other tasks attach to.

- [ ] **Step 1: Confirm `.gitignore` ignores the real env file**

Run: `grep -nE '(^|/)\.env' .gitignore`
Expected: a line matching `**/.env` (already added; it covers `deploy/dev/.env`). If absent, add it.

- [ ] **Step 2: Create `deploy/dev/.env.example`** (documents every variable; real `.env` is filled on the host)

```dotenv
# ---- shared Postgres (superuser; used only by init + FDW) ----
POSTGRES_SUPER_USER=postgres
POSTGRES_SUPER_PASSWORD=change-me-super
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# ---- per-app DB credentials (created by postgres/init) ----
FORGEJO_DB=forgejo
FORGEJO_DB_USER=forgejo
FORGEJO_DB_PASSWORD=change-me-forgejo

MATTERMOST_DB=mattermost
MATTERMOST_DB_USER=mattermost
MATTERMOST_DB_PASSWORD=change-me-mattermost

PLANE_DB=plane
PLANE_DB_USER=plane
PLANE_DB_PASSWORD=change-me-plane

# ---- reporting / BI ----
REPORTING_DB=reporting
FDW_READER_PASSWORD=change-me-fdw          # role used by FDW to read app DBs
BI_AUTHENTICATOR_PASSWORD=change-me-authn   # PostgREST login role
PGRST_JWT_SECRET=change-me-32char-min-secret

# ---- domains ----
ACME_EMAIL=admin@analyticsbi.cloud
FORGEJO_DOMAIN=git.code42.dev
MATTERMOST_DOMAIN=chat.code42.dev
PLANE_DOMAIN=plane.code42.dev

# ---- GHCR (Plane images) ----
GHCR_USER=code42
GHCR_TOKEN=change-me-ghcr-pat-read-packages
PLANE_IMAGE_TAG=code42-0.1.0

# ---- Plane backend (confirmed against fork apps/api/.env.example in Task 6) ----
PLANE_SECRET_KEY=change-me-plane-secret
PLANE_REDIS_PASSWORD=change-me-valkey
RABBITMQ_DEFAULT_USER=plane
RABBITMQ_DEFAULT_PASS=change-me-rabbit
RABBITMQ_DEFAULT_VHOST=plane
MINIO_ROOT_USER=plane
MINIO_ROOT_PASSWORD=change-me-minio
PLANE_BUCKET_NAME=uploads
```

- [ ] **Step 3: Create `deploy/dev/docker-compose.yml` base** (only Caddy + Postgres for now; later tasks append services)

```yaml
name: devtools

networks:
  edge:
  internal:

volumes:
  caddy_data: { driver: local, driver_opts: { type: none, o: bind, device: /data/caddy/data } }
  caddy_config: { driver: local, driver_opts: { type: none, o: bind, device: /data/caddy/config } }
  postgres_data: { driver: local, driver_opts: { type: none, o: bind, device: /data/postgres } }

services:
  caddy:
    build: ../../apps/caddy
    image: devtools/caddy:0.1.0
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    env_file: [.env]
    volumes:
      - ../../apps/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks: [edge]

  postgres:
    build: ../../apps/postgres
    image: devtools/postgres:0.1.0
    restart: unless-stopped
    env_file: [.env]
    environment:
      POSTGRES_USER: ${POSTGRES_SUPER_USER}
      POSTGRES_PASSWORD: ${POSTGRES_SUPER_PASSWORD}
      POSTGRES_DB: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ../../apps/postgres/init:/docker-entrypoint-initdb.d:ro
    networks: [internal]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
```

- [ ] **Step 4: Create `apps/README.md`** (one-screen runbook)

```markdown
# apps/ — runtime stack

One context per app. Bring up: `docker compose -f deploy/dev/docker-compose.yml up -d`.
Lint: `docker compose -f deploy/dev/docker-compose.yml config`.
Secrets: copy `.env.example` → `.env` on the host, fill, `chmod 600 .env`.
Reach Postgres/PostgREST/Adminer (N2): `ssh -L 5432:127.0.0.1:5432 <host>`.
```

- [ ] **Step 5: Lint (config will fail until build contexts exist — expect that)**

Run: `docker compose -f deploy/dev/docker-compose.yml config -q 2>&1 | head`
Expected: complains that `../../apps/caddy` / `../../apps/postgres` build contexts are missing (created in Tasks 2–3). The YAML itself must parse — no "yaml:" errors.

- [ ] **Step 6: Commit**

```bash
git add deploy/dev/.env.example deploy/dev/docker-compose.yml apps/README.md
git commit -m "feat(apps): compose base with Caddy + Postgres, env template"
```

---

### Task 2: Lightsail provisioning scripts

**Files:**
- Create: `infra/scripts/create-lightsail.sh`
- Create: `infra/scripts/user-data.sh`
- Create: `infra/scripts/destroy-lightsail.sh`
- Create: `infra/firewall.json`
- Create: `infra/README.md`

**Interfaces:**
- Produces: a running Ubuntu 24.04 Lightsail instance named `devtools`, a static IP, an attached 320 GB-class block disk mounted at `/data`, firewall allowing 22 (owner IP)/80/443, Docker + Compose installed, repo cloned to `/opt/devtools`.

- [ ] **Step 1: Create `infra/firewall.json`** (port rules; `OWNER_IP` substituted by the script)

```json
[
  { "fromPort": 22,  "toPort": 22,  "protocol": "tcp", "cidrs": ["OWNER_IP/32"] },
  { "fromPort": 80,  "toPort": 80,  "protocol": "tcp", "cidrs": ["0.0.0.0/0"] },
  { "fromPort": 443, "toPort": 443, "protocol": "tcp", "cidrs": ["0.0.0.0/0"] }
]
```

- [ ] **Step 2: Create `infra/scripts/user-data.sh`** (cloud-init, runs once on first boot)

```bash
#!/usr/bin/env bash
# Lightsail first-boot bootstrap. Idempotent where practical.
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

REPO_URL="https://github.com/code42/devtools.git"   # adjust to the real repo URL
APP_DIR="/opt/devtools"
DATA_DISK="/dev/xvdf"   # Lightsail attaches the first block disk here; verify with lsblk

echo "== install docker =="
apt-get update -y
apt-get install -y ca-certificates curl git gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "== 4GB swap =="
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

echo "== mount block disk at /data =="
if [ -b "$DATA_DISK" ]; then
  if ! blkid "$DATA_DISK"; then mkfs.ext4 -F "$DATA_DISK"; fi
  mkdir -p /data
  grep -q "$DATA_DISK" /etc/fstab || echo "$DATA_DISK /data ext4 defaults,nofail 0 2" >> /etc/fstab
  mount -a
fi
mkdir -p /data/{caddy/data,caddy/config,postgres}

echo "== clone repo =="
if [ ! -d "$APP_DIR/.git" ]; then git clone "$REPO_URL" "$APP_DIR"; else git -C "$APP_DIR" pull --ff-only; fi

echo "== DONE. Now: scp deploy/dev/.env to /deploy/dev/.env (chmod 600), docker login ghcr.io, compose up =="
```

- [ ] **Step 3: Create `infra/scripts/create-lightsail.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-1}"
AZ="${AZ:-us-east-1a}"
NAME="${NAME:-devtools}"
BUNDLE="${BUNDLE:-xlarge_2_0}"          # 16GB / 4 vCPU
BLUEPRINT="${BLUEPRINT:-ubuntu_24_04}"  # confirm: aws lightsail get-blueprints
DISK_NAME="${DISK_NAME:-devtools-data}"
DISK_SIZE_GB="${DISK_SIZE_GB:-80}"
KEY_PAIR="${KEY_PAIR:-devtools-key}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OWNER_IP="$(curl -fsS https://checkip.amazonaws.com)"
echo "Owner IP for SSH allowlist: $OWNER_IP"

aws lightsail create-key-pair --key-pair-name "$KEY_PAIR" --region "$REGION" \
  --query 'privateKeyBase64' --output text > "$HERE/${KEY_PAIR}.pem" 2>/dev/null || \
  echo "key pair $KEY_PAIR already exists; reusing"
[ -f "$HERE/${KEY_PAIR}.pem" ] && chmod 600 "$HERE/${KEY_PAIR}.pem" || true

aws lightsail create-instances --region "$REGION" \
  --instance-names "$NAME" \
  --availability-zone "$AZ" \
  --blueprint-id "$BLUEPRINT" \
  --bundle-id "$BUNDLE" \
  --key-pair-name "$KEY_PAIR" \
  --user-data "file://$HERE/user-data.sh"

echo "waiting for instance to run..."
until [ "$(aws lightsail get-instance-state --instance-name "$NAME" --region "$REGION" \
  --query 'state.name' --output text)" = "running" ]; do sleep 5; done

aws lightsail allocate-static-ip --static-ip-name "${NAME}-ip" --region "$REGION" || true
aws lightsail attach-static-ip --static-ip-name "${NAME}-ip" --instance-name "$NAME" --region "$REGION"

aws lightsail create-disk --disk-name "$DISK_NAME" --availability-zone "$AZ" \
  --size-in-gb "$DISK_SIZE_GB" --region "$REGION" || true
until [ "$(aws lightsail get-disk --disk-name "$DISK_NAME" --region "$REGION" \
  --query 'disk.state' --output text)" = "available" ]; do sleep 5; done
aws lightsail attach-disk --disk-name "$DISK_NAME" --disk-path /dev/xvdf \
  --instance-name "$NAME" --region "$REGION"

# firewall: substitute owner IP, apply
sed "s#OWNER_IP#${OWNER_IP}#" "$HERE/../firewall.json" > /tmp/fw.json
aws lightsail put-instance-public-ports --instance-name "$NAME" --region "$REGION" \
  --port-infos "file:///tmp/fw.json"

IP="$(aws lightsail get-static-ip --static-ip-name "${NAME}-ip" --region "$REGION" \
  --query 'staticIp.ipAddress' --output text)"
echo "== Lightsail ready =="
echo "Static IP: $IP"
echo "Point DNS A-records git/chat/plane.code42.dev -> $IP"
echo "SSH: ssh -i $HERE/${KEY_PAIR}.pem ubuntu@$IP"
```

- [ ] **Step 4: Create `infra/scripts/destroy-lightsail.sh`** (guarded — irreversible)

```bash
#!/usr/bin/env bash
set -euo pipefail
REGION="${REGION:-us-east-1}"
NAME="${NAME:-devtools}"
DISK_NAME="${DISK_NAME:-devtools-data}"

echo "This DELETES the Lightsail instance '$NAME' and static IP."
echo "The data disk '$DISK_NAME' is NOT deleted (survives). NO BACKUPS EXIST."
read -r -p "Type the instance name to confirm: " CONFIRM
[ "$CONFIRM" = "$NAME" ] || { echo "aborted"; exit 1; }

aws lightsail detach-disk --disk-name "$DISK_NAME" --region "$REGION" || true
aws lightsail delete-instance --instance-name "$NAME" --region "$REGION"
aws lightsail release-static-ip --static-ip-name "${NAME}-ip" --region "$REGION" || true
echo "Instance gone. Disk '$DISK_NAME' kept. Delete it manually if you really mean to."
```

- [ ] **Step 5: Create `infra/README.md`**

```markdown
# infra/ — Lightsail provisioning (no OpenTofu)

Prereqs: AWS CLI v2 configured (`aws configure`), an account with Lightsail access.

1. `bash infra/scripts/create-lightsail.sh`   # creates instance, static IP, disk, firewall
2. Point DNS A-records `git.`/`chat.`/`plane.code42.dev` at the printed static IP.
3. `scp -i infra/scripts/devtools-key.pem deploy/dev/.env ubuntu@<ip>:/opt/devtools/deploy/dev/.env`
4. SSH in: `cd /opt/devtools && chmod 600 deploy/dev/.env && docker login ghcr.io`
5. `docker compose -f deploy/dev/docker-compose.yml up -d`

Teardown (DANGER, no backups): `bash infra/scripts/destroy-lightsail.sh`.
Block disk `devtools-data` survives instance deletion.
```

- [ ] **Step 6: Syntax-check all scripts**

Run: `for f in infra/scripts/*.sh; do bash -n "$f" && echo "ok $f"; done`
Expected: `ok` for all three. If `shellcheck` is installed: `shellcheck infra/scripts/*.sh` (warnings acceptable, no errors).

- [ ] **Step 7: Commit**

```bash
git add infra/
git commit -m "feat(infra): Lightsail create/destroy scripts, firewall, user-data"
```

---

### Task 3: Postgres image (postgres_fdw) + init SQL (databases, roles)

**Files:**
- Create: `apps/postgres/Dockerfile`
- Create: `apps/postgres/init/00-databases.sh`
- Create: `apps/postgres/init/10-reporting.sql`

**Interfaces:**
- Consumes: env from Task 1 (`*_DB`, `*_DB_USER`, `*_DB_PASSWORD`, `REPORTING_DB`, `FDW_READER_PASSWORD`, `BI_AUTHENTICATOR_PASSWORD`).
- Produces: databases `forgejo`, `mattermost`, `plane`, `reporting`; per-app owner roles; role `fdw_reader` (reads app DBs), `authenticator` + `bi_reader` (PostgREST). `postgres_fdw` extension available in `reporting`.

- [ ] **Step 1: Create `apps/postgres/Dockerfile`**

```dockerfile
FROM postgres:16-bookworm
# postgres_fdw ships in postgresql-contrib, included in this image's contrib package
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-contrib \
 && rm -rf /var/lib/apt/lists/*
# init scripts in /docker-entrypoint-initdb.d run on first init only (empty data dir)
```

- [ ] **Step 2: Create `apps/postgres/init/00-databases.sh`** (creates a DB + owner per app)

```bash
#!/usr/bin/env bash
set -euo pipefail

psql() { command psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres "$@"; }

create_db() {  # name user password
  local db="$1" user="$2" pass="$3"
  psql <<-SQL
    DO \$\$ BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${user}') THEN
        CREATE ROLE ${user} LOGIN PASSWORD '${pass}';
      END IF;
    END \$\$;
    SELECT 'CREATE DATABASE ${db} OWNER ${user}'
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db}')\gexec
SQL
}

create_db "$FORGEJO_DB"    "$FORGEJO_DB_USER"    "$FORGEJO_DB_PASSWORD"
create_db "$MATTERMOST_DB" "$MATTERMOST_DB_USER" "$MATTERMOST_DB_PASSWORD"
create_db "$PLANE_DB"      "$PLANE_DB_USER"      "$PLANE_DB_PASSWORD"
create_db "$REPORTING_DB"  "$POSTGRES_USER"      "$POSTGRES_PASSWORD"

# read-only role used by FDW user mappings to read app DBs
psql <<-SQL
  DO \$\$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fdw_reader') THEN
      CREATE ROLE fdw_reader LOGIN PASSWORD '${FDW_READER_PASSWORD}';
    END IF;
  END \$\$;
SQL
for db in "$FORGEJO_DB" "$MATTERMOST_DB" "$PLANE_DB"; do
  command psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" \
    -c "GRANT CONNECT ON DATABASE ${db} TO fdw_reader;" \
    -c "GRANT USAGE ON SCHEMA public TO fdw_reader;" \
    -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO fdw_reader;" \
    -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO fdw_reader;"
done
```

- [ ] **Step 3: Create `apps/postgres/init/10-reporting.sql`** (FDW scaffolding + PostgREST roles; foreign tables/views are added in Task 7 once app schemas exist)

```sql
\connect reporting

CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE SCHEMA IF NOT EXISTS reporting;

-- PostgREST login role + read-only role it switches to
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bi_reader') THEN
    CREATE ROLE bi_reader NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN PASSWORD :'authn_pass' NOINHERIT;
  END IF;
END $$;
GRANT bi_reader TO authenticator;
GRANT USAGE ON SCHEMA reporting TO bi_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA reporting GRANT SELECT ON TABLES TO bi_reader;
```

> Note: `:'authn_pass'` is passed at apply time. In Task 7 we re-run reporting SQL
> with `-v authn_pass="$BI_AUTHENTICATOR_PASSWORD"`. For the first init, set it via a
> wrapper: see Step 4.

- [ ] **Step 4: Make the reporting password injectable** — rename to a templated runner. Replace `10-reporting.sql` invocation by a shell wrapper `apps/postgres/init/11-reporting.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
command psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d reporting \
  -v authn_pass="$BI_AUTHENTICATOR_PASSWORD" \
  -f /docker-entrypoint-initdb.d/10-reporting.sql
```

(The `.sql` file stays; `*.sh` and `*.sql` both run in filename order — `10-reporting.sql` would run unparameterized, so rename it to `10-reporting.tmpl.sql` so only the wrapper executes it.)

Run: `git mv` is not needed (new files); ensure the SQL file is named `apps/postgres/init/10-reporting.tmpl.sql` and the wrapper points at it.

- [ ] **Step 5: Build the image**

Run: `docker build -t devtools/postgres:0.1.0 apps/postgres`
Expected: build succeeds.

- [ ] **Step 6: Boot Postgres alone and verify databases + roles**

```bash
docker compose -f deploy/dev/docker-compose.yml up -d postgres
sleep 8
docker compose -f deploy/dev/docker-compose.yml exec postgres \
  psql -U postgres -c "\l" -c "\du"
```
Expected: databases `forgejo`, `mattermost`, `plane`, `reporting` present; roles `forgejo`, `mattermost`, `plane`, `fdw_reader`, `bi_reader`, `authenticator` present.

- [ ] **Step 7: Verify postgres_fdw in reporting**

Run: `docker compose -f deploy/dev/docker-compose.yml exec postgres psql -U postgres -d reporting -c "SELECT extname FROM pg_extension WHERE extname='postgres_fdw';"`
Expected: one row `postgres_fdw`.

- [ ] **Step 8: Commit**

```bash
git add apps/postgres
git commit -m "feat(postgres): fdw image, per-app DBs, reporting roles"
```

---

### Task 4: Caddy reverse proxy + TLS

**Files:**
- Create: `apps/caddy/Dockerfile`
- Create: `apps/caddy/Caddyfile`

**Interfaces:**
- Consumes: env `FORGEJO_DOMAIN`, `MATTERMOST_DOMAIN`, `PLANE_DOMAIN`, `ACME_EMAIL`.
- Produces: TLS-terminating routes to `forgejo:3000`, `mattermost:8065`, `plane-proxy:80` on the `edge` network.

- [ ] **Step 1: Create `apps/caddy/Dockerfile`**

```dockerfile
FROM caddy:2-alpine
# plain Caddy is enough; Caddyfile is bind-mounted by compose
```

- [ ] **Step 2: Create `apps/caddy/Caddyfile`** (env placeholders are read from compose `env_file`)

```caddyfile
{
	email {$ACME_EMAIL}
}

{$FORGEJO_DOMAIN} {
	reverse_proxy forgejo:3000
}

{$MATTERMOST_DOMAIN} {
	reverse_proxy mattermost:8065
}

{$PLANE_DOMAIN} {
	reverse_proxy plane-proxy:80
}
```

- [ ] **Step 3: Add caddy to `edge`+`internal`** — Caddy must reach app containers. Edit `deploy/dev/docker-compose.yml` caddy service `networks:` to `[edge, internal]` (apps sit on `internal`; web ones also join `edge` only if needed — simpler: put all web apps on `internal` and Caddy on `internal`). Update caddy:

```yaml
    networks: [internal]
```

(Drop the separate `edge` usage for web apps; only Caddy needs host ports. All inter-container traffic is on `internal`.)

- [ ] **Step 4: Validate Caddyfile syntax**

Run: `docker run --rm -v "$PWD/apps/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile`
Expected: "Valid configuration" (env placeholders may warn as empty — acceptable offline).

- [ ] **Step 5: Commit**

```bash
git add apps/caddy deploy/dev/docker-compose.yml
git commit -m "feat(caddy): TLS reverse proxy for git/chat/plane"
```

---

### Task 5: Forgejo

**Files:**
- Create: `apps/forgejo/Dockerfile`
- Create: `apps/forgejo/README.md`
- Modify: `deploy/dev/docker-compose.yml` (add `forgejo` service + volume)

**Interfaces:**
- Consumes: Postgres `forgejo` DB; env `FORGEJO_DB*`, `FORGEJO_DOMAIN`.
- Produces: Forgejo on `forgejo:3000` (internal), data volume `/data/forgejo`. Native API base `https://git.code42.dev/api/v1`.

- [ ] **Step 1: Create `apps/forgejo/Dockerfile`** (overlay on official; thin for now)

```dockerfile
FROM codeberg.org/forgejo/forgejo:9
# Overlay point: custom templates/assets/config go here later, e.g.
# COPY custom/ /var/lib/gitea/custom/
```

- [ ] **Step 2: Add the volume** to `deploy/dev/docker-compose.yml` `volumes:`

```yaml
  forgejo_data: { driver: local, driver_opts: { type: none, o: bind, device: /data/forgejo } }
```

- [ ] **Step 3: Add the `forgejo` service**

```yaml
  forgejo:
    build: ../../apps/forgejo
    image: devtools/forgejo:0.1.0
    restart: unless-stopped
    depends_on:
      postgres: { condition: service_healthy }
    env_file: [.env]
    environment:
      FORGEJO__database__DB_TYPE: postgres
      FORGEJO__database__HOST: ${POSTGRES_HOST}:${POSTGRES_PORT}
      FORGEJO__database__NAME: ${FORGEJO_DB}
      FORGEJO__database__USER: ${FORGEJO_DB_USER}
      FORGEJO__database__PASSWD: ${FORGEJO_DB_PASSWORD}
      FORGEJO__server__DOMAIN: ${FORGEJO_DOMAIN}
      FORGEJO__server__ROOT_URL: https://${FORGEJO_DOMAIN}/
      FORGEJO__server__SSH_DOMAIN: ${FORGEJO_DOMAIN}
    volumes:
      - forgejo_data:/data
    networks: [internal]
```

- [ ] **Step 4: Create `apps/forgejo/README.md`**

```markdown
# forgejo — git hosting
Image overlays codeberg.org/forgejo/forgejo. DB: shared Postgres `forgejo`.
Native API: https://git.code42.dev/api/v1 (used for programmatic access, goal A).
First run creates the admin user via the web installer (disabled-install can be set later).
```

- [ ] **Step 5: Lint + boot + smoke**

```bash
docker compose -f deploy/dev/docker-compose.yml config -q
mkdir -p /data/forgejo   # on host; locally use a tmp bind for testing
docker compose -f deploy/dev/docker-compose.yml up -d postgres forgejo
sleep 10
docker compose -f deploy/dev/docker-compose.yml exec forgejo curl -fsS http://localhost:3000/api/healthz
```
Expected: config OK; healthz returns `{"status":"pass"...}` (or HTTP 200).

- [ ] **Step 6: Commit**

```bash
git add apps/forgejo deploy/dev/docker-compose.yml
git commit -m "feat(forgejo): git hosting on shared Postgres"
```

---

### Task 6: Mattermost

**Files:**
- Create: `apps/mattermost/Dockerfile`
- Create: `apps/mattermost/README.md`
- Modify: `deploy/dev/docker-compose.yml` (add `mattermost` service + volumes)

**Interfaces:**
- Consumes: Postgres `mattermost` DB; env `MATTERMOST_DB*`, `MATTERMOST_DOMAIN`.
- Produces: Mattermost on `mattermost:8065` (internal), data under `/data/mattermost`. Native API base `https://chat.code42.dev/api/v4`.

- [ ] **Step 1: Create `apps/mattermost/Dockerfile`**

```dockerfile
FROM mattermost/mattermost-team-edition:10.5
# Overlay point: branding/plugins/config overrides later.
```

- [ ] **Step 2: Add volumes** to `deploy/dev/docker-compose.yml`

```yaml
  mattermost_data:   { driver: local, driver_opts: { type: none, o: bind, device: /data/mattermost/data } }
  mattermost_config: { driver: local, driver_opts: { type: none, o: bind, device: /data/mattermost/config } }
```

- [ ] **Step 3: Add the `mattermost` service**

```yaml
  mattermost:
    build: ../../apps/mattermost
    image: devtools/mattermost:0.1.0
    restart: unless-stopped
    depends_on:
      postgres: { condition: service_healthy }
    env_file: [.env]
    environment:
      MM_SQLSETTINGS_DRIVERNAME: postgres
      MM_SQLSETTINGS_DATASOURCE: "postgres://${MATTERMOST_DB_USER}:${MATTERMOST_DB_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${MATTERMOST_DB}?sslmode=disable&connect_timeout=10"
      MM_SERVICESETTINGS_SITEURL: https://${MATTERMOST_DOMAIN}
    volumes:
      - mattermost_data:/mattermost/data
      - mattermost_config:/mattermost/config
    networks: [internal]
```

- [ ] **Step 4: Create `apps/mattermost/README.md`**

```markdown
# mattermost — chat
Image overlays mattermost-team-edition. DB: shared Postgres `mattermost`.
Native API: https://chat.code42.dev/api/v4 (goal A).
SiteURL is fixed via env; first admin created on first web visit.
```

- [ ] **Step 5: Lint + boot + smoke**

```bash
docker compose -f deploy/dev/docker-compose.yml config -q
docker compose -f deploy/dev/docker-compose.yml up -d postgres mattermost
sleep 15
docker compose -f deploy/dev/docker-compose.yml exec mattermost curl -fsS http://localhost:8065/api/v4/system/ping
```
Expected: `{"status":"OK"...}`.

- [ ] **Step 6: Commit**

```bash
git add apps/mattermost deploy/dev/docker-compose.yml
git commit -m "feat(mattermost): chat on shared Postgres"
```

---

### Task 7: Plane fork — submodule, images (GHCR), compose services

**Files:**
- Create: `apps/plane/upstream/` (git submodule → our fork)
- Create: `apps/plane/CHANGES.md`
- Create: `apps/plane/README.md`
- Create: `apps/plane/.env.plane.example` (backend env, derived from the fork)
- Modify: `deploy/dev/docker-compose.yml` (add Plane services + volumes)

**Interfaces:**
- Consumes: Postgres `plane` DB; env `PLANE_*`, `RABBITMQ_*`, `MINIO_*`, `GHCR_*`, `PLANE_IMAGE_TAG`, `PLANE_DOMAIN`.
- Produces: Plane reachable via `plane-proxy:80` (Caddy routes `plane.code42.dev` here). Backend on `plane-api`. Data under `/data/plane/minio`, `/data/plane/redis`, `/data/plane/rabbitmq`.

- [ ] **Step 1: Fork upstream and add the submodule**

```bash
# (manual, once) Fork github.com/makeplane/plane -> github.com/code42/plane
git submodule add https://github.com/code42/plane.git apps/plane/upstream
git -C apps/plane/upstream remote add upstream https://github.com/makeplane/plane.git
git -C apps/plane/upstream fetch --all
git -C apps/plane/upstream checkout -b code42   # long-lived work branch
```

- [ ] **Step 2: Inspect the fork's real backend env keys** (ground truth, do not guess)

```bash
sed -n '1,200p' apps/plane/upstream/apps/api/.env.example 2>/dev/null \
  || find apps/plane/upstream -maxdepth 3 -name '*.env*' -o -name 'plane.env*' | head
```
Expected: the canonical backend variables. Copy the ones Plane requires into
`apps/plane/.env.plane.example`, mapping DB/Redis/RabbitMQ/MinIO to our shared/owned
services. At minimum Plane needs (confirm names against the file above):
`SECRET_KEY`, `DATABASE_URL` (or `PGHOST`/`PGUSER`/`PGPASSWORD`/`PGDATABASE`/`PGPORT`),
`REDIS_URL`, `AMQP_URL` (or `RABBITMQ_*`), `USE_MINIO`, `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY`, `AWS_S3_BUCKET_NAME`, `AWS_S3_ENDPOINT_URL`, `WEB_URL`,
`CORS_ALLOWED_ORIGINS`.

- [ ] **Step 3: Create `apps/plane/.env.plane.example`** (template wiring Plane to our backing services)

```dotenv
SECRET_KEY=${PLANE_SECRET_KEY}
# point Plane at the SHARED Postgres `plane` DB (upstream plane-db is dropped)
DATABASE_URL=postgres://${PLANE_DB_USER}:${PLANE_DB_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${PLANE_DB}
REDIS_URL=redis://:${PLANE_REDIS_PASSWORD}@plane-redis:6379/
AMQP_URL=amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@plane-mq:5672/${RABBITMQ_DEFAULT_VHOST}
USE_MINIO=1
AWS_ACCESS_KEY_ID=${MINIO_ROOT_USER}
AWS_SECRET_ACCESS_KEY=${MINIO_ROOT_PASSWORD}
AWS_S3_BUCKET_NAME=${PLANE_BUCKET_NAME}
AWS_S3_ENDPOINT_URL=http://plane-minio:9000
WEB_URL=https://${PLANE_DOMAIN}
CORS_ALLOWED_ORIGINS=https://${PLANE_DOMAIN}
```

- [ ] **Step 4: Build and push Plane images to GHCR (off-host)**

```bash
export TAG="${PLANE_IMAGE_TAG:-code42-0.1.0}"
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
U="apps/plane/upstream"
docker build -t ghcr.io/$GHCR_USER/plane-api:$TAG     -f $U/apps/api/Dockerfile.api     $U
docker build -t ghcr.io/$GHCR_USER/plane-web:$TAG     -f $U/apps/web/Dockerfile.web     $U
docker build -t ghcr.io/$GHCR_USER/plane-admin:$TAG   -f $U/apps/admin/Dockerfile.admin $U
docker build -t ghcr.io/$GHCR_USER/plane-space:$TAG   -f $U/apps/space/Dockerfile.space $U
docker build -t ghcr.io/$GHCR_USER/plane-live:$TAG    -f $U/apps/live/Dockerfile.live   $U
docker build -t ghcr.io/$GHCR_USER/plane-proxy:$TAG   -f $U/apps/proxy/Dockerfile.ce    $U
for s in api web admin space live proxy; do docker push ghcr.io/$GHCR_USER/plane-$s:$TAG; done
```
Expected: six images pushed. (Confirm each Dockerfile path against Step 2's listing;
adjust if the fork's layout differs.)

- [ ] **Step 5: Add Plane volumes** to `deploy/dev/docker-compose.yml`

```yaml
  plane_minio:    { driver: local, driver_opts: { type: none, o: bind, device: /data/plane/minio } }
  plane_redis:    { driver: local, driver_opts: { type: none, o: bind, device: /data/plane/redis } }
  plane_rabbitmq: { driver: local, driver_opts: { type: none, o: bind, device: /data/plane/rabbitmq } }
```

- [ ] **Step 6: Add Plane services** to `deploy/dev/docker-compose.yml` (backing services + backend + frontends + proxy)

```yaml
  plane-redis:
    image: valkey/valkey:7.2-alpine
    restart: unless-stopped
    command: ["valkey-server", "--requirepass", "${PLANE_REDIS_PASSWORD}"]
    volumes: [plane_redis:/data]
    networks: [internal]

  plane-mq:
    image: rabbitmq:3.13-management-alpine
    restart: unless-stopped
    env_file: [.env]
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_DEFAULT_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_DEFAULT_PASS}
      RABBITMQ_DEFAULT_VHOST: ${RABBITMQ_DEFAULT_VHOST}
    volumes: [plane_rabbitmq:/var/lib/rabbitmq]
    networks: [internal]

  plane-minio:
    image: minio/minio:RELEASE.2025-01-20T14-49-07Z
    restart: unless-stopped
    command: server /export --console-address ":9090"
    env_file: [.env]
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes: [plane_minio:/export]
    networks: [internal]

  plane-migrator:
    image: ghcr.io/${GHCR_USER}/plane-api:${PLANE_IMAGE_TAG}
    restart: "no"
    depends_on:
      postgres: { condition: service_healthy }
    env_file: [.env, ../../apps/plane/.env.plane]
    command: ["./bin/docker-entrypoint-migrator.sh"]
    networks: [internal]

  plane-api:
    image: ghcr.io/${GHCR_USER}/plane-api:${PLANE_IMAGE_TAG}
    restart: unless-stopped
    depends_on:
      plane-migrator: { condition: service_completed_successfully }
      plane-redis: { condition: service_started }
      plane-mq: { condition: service_started }
    env_file: [.env, ../../apps/plane/.env.plane]
    command: ["./bin/docker-entrypoint-api.sh"]
    networks: [internal]

  plane-worker:
    image: ghcr.io/${GHCR_USER}/plane-api:${PLANE_IMAGE_TAG}
    restart: unless-stopped
    depends_on:
      plane-api: { condition: service_started }
    env_file: [.env, ../../apps/plane/.env.plane]
    command: ["./bin/docker-entrypoint-worker.sh"]
    networks: [internal]

  plane-beat:
    image: ghcr.io/${GHCR_USER}/plane-api:${PLANE_IMAGE_TAG}
    restart: unless-stopped
    depends_on:
      plane-api: { condition: service_started }
    env_file: [.env, ../../apps/plane/.env.plane]
    command: ["./bin/docker-entrypoint-beat.sh"]
    networks: [internal]

  plane-web:
    image: ghcr.io/${GHCR_USER}/plane-web:${PLANE_IMAGE_TAG}
    restart: unless-stopped
    depends_on: [plane-api]
    networks: [internal]

  plane-admin:
    image: ghcr.io/${GHCR_USER}/plane-admin:${PLANE_IMAGE_TAG}
    restart: unless-stopped
    depends_on: [plane-api]
    networks: [internal]

  plane-space:
    image: ghcr.io/${GHCR_USER}/plane-space:${PLANE_IMAGE_TAG}
    restart: unless-stopped
    depends_on: [plane-api]
    networks: [internal]

  plane-live:
    image: ghcr.io/${GHCR_USER}/plane-live:${PLANE_IMAGE_TAG}
    restart: unless-stopped
    depends_on: [plane-api]
    networks: [internal]

  plane-proxy:
    image: ghcr.io/${GHCR_USER}/plane-proxy:${PLANE_IMAGE_TAG}
    restart: unless-stopped
    depends_on: [plane-web, plane-admin, plane-space, plane-api, plane-live]
    env_file: [.env]
    environment:
      FILE_SIZE_LIMIT: "5242880"
      BUCKET_NAME: ${PLANE_BUCKET_NAME}
    networks: [internal]
```

> The `plane-proxy` upstream image expects to route to the sub-apps by their compose
> service names. If the fork's proxy template uses different upstream names, align the
> service names here with that template (check `apps/proxy` in the fork). Log any such
> change in `CHANGES.md`.

- [ ] **Step 7: Seed `CHANGES.md` and `README.md`**

`apps/plane/CHANGES.md`:
```markdown
# Plane fork — divergences from upstream
Branch `code42` off upstream. Log every change: file, what, why, upstreamable?

| Date | File(s) | Change | Why | Upstreamable |
|------|---------|--------|-----|--------------|
| 2026-06-25 | docker-compose (ours) | dropped upstream `plane-db`, point at shared Postgres `plane` | one Postgres for the whole stack + reporting | no (deploy-specific) |
```

`apps/plane/README.md`:
```markdown
# plane — project management (OUR FORK)
Source: submodule apps/plane/upstream (fork of makeplane/plane, branch `code42`).
Build OFF-HOST -> push GHCR -> host pulls. Never build on the 16GB host.
Rebase: git -C apps/plane/upstream fetch upstream && git rebase upstream/<tag>,
resolve against CHANGES.md, rebuild, bump PLANE_IMAGE_TAG, redeploy.
Native API: https://plane.code42.dev/api (goal A). Routed via plane-proxy.
```

- [ ] **Step 8: Lint, pull, boot, smoke**

```bash
docker compose -f deploy/dev/docker-compose.yml config -q
docker login ghcr.io -u "$GHCR_USER" -p "$GHCR_TOKEN"
docker compose -f deploy/dev/docker-compose.yml up -d \
  postgres plane-redis plane-mq plane-minio plane-migrator \
  plane-api plane-worker plane-beat plane-web plane-admin plane-space plane-live plane-proxy
sleep 30
docker compose -f deploy/dev/docker-compose.yml exec plane-proxy curl -fsS http://localhost:80/ -o /dev/null -w '%{http_code}\n'
docker compose -f deploy/dev/docker-compose.yml logs --tail=20 plane-migrator
```
Expected: migrator exits 0 (migrations applied); proxy returns 200/302. Plane `plane`
DB now has tables (`docker compose exec postgres psql -U plane -d plane -c "\dt" | head`).

- [ ] **Step 9: Commit**

```bash
git add apps/plane deploy/dev/docker-compose.yml .gitmodules
git commit -m "feat(plane): fork submodule + GHCR images + full service stack"
```

---

### Task 8: Reporting layer (FDW foreign tables + views) + PostgREST + Adminer

**Files:**
- Create: `apps/postgres/init/20-fdw-foreign-tables.sql` (applied post-boot, after app schemas exist)
- Create: `apps/postgrest/postgrest.conf`
- Create: `apps/postgrest/README.md`
- Modify: `deploy/dev/docker-compose.yml` (add `postgrest` + `adminer`)

**Interfaces:**
- Consumes: app tables in `forgejo`/`mattermost`/`plane` DBs; role `fdw_reader`, `bi_reader`, `authenticator`.
- Produces: foreign schemas + curated `reporting.*` views; PostgREST on `postgrest:3000` (no host port); Adminer on `adminer:8080` (no host port). Both reached via `ssh -L`.

> The app tables only exist after Tasks 5–7 have booted each app at least once
> (migrations run). This task therefore runs its SQL **against the live DB**, not as
> a first-init script.

- [ ] **Step 1: Create `apps/postgres/init/20-fdw-foreign-tables.sql`** (FDW servers + import a curated set of schemas)

```sql
\connect reporting

-- one foreign server + user mapping per app DB (same Postgres instance, so host=localhost)
DO $$
DECLARE app text;
BEGIN
  FOREACH app IN ARRAY ARRAY['forgejo','mattermost','plane'] LOOP
    IF NOT EXISTS (SELECT FROM pg_foreign_server WHERE srvname = app || '_srv') THEN
      EXECUTE format(
        'CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L, port %L)',
        app || '_srv', 'localhost', app, '5432');
      EXECUTE format(
        'CREATE USER MAPPING FOR CURRENT_USER SERVER %I OPTIONS (user %L, password %L)',
        app || '_srv', 'fdw_reader', :'fdw_pass');
      EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I', app || '_src');
      EXECUTE format(
        'IMPORT FOREIGN SCHEMA public FROM SERVER %I INTO %I',
        app || '_srv', app || '_src');
    END IF;
  END LOOP;
END $$;
```

- [ ] **Step 2: Create the first curated views** (extend over time as BI needs grow)

Append to the same file:
```sql
-- Example curated, stable views. Adjust columns to the actual app schemas.
CREATE OR REPLACE VIEW reporting.repositories AS
  SELECT id, owner_id, lower_name AS name, is_private, created_unix
  FROM forgejo_src.repository;

CREATE OR REPLACE VIEW reporting.chat_channels AS
  SELECT id, name, displayname, type, createat
  FROM mattermost_src.channels;

CREATE OR REPLACE VIEW reporting.plane_issues AS
  SELECT id, name, priority, created_at, completed_at, project_id
  FROM plane_src.issues;

GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO bi_reader;
```

- [ ] **Step 3: Apply the FDW + views against the running DB**

```bash
docker compose -f deploy/dev/docker-compose.yml exec -T postgres \
  psql -U postgres -d reporting -v fdw_pass="$FDW_READER_PASSWORD" \
  -f /docker-entrypoint-initdb.d/20-fdw-foreign-tables.sql
```
(For a running container the init dir is mounted read-only; if the file isn't present
because Postgres already initialized, `docker cp` it in or pipe via stdin:
`cat apps/postgres/init/20-fdw-foreign-tables.sql | docker compose ... exec -T postgres psql ...`.)
Expected: no errors; `\dv reporting.*` lists the three views.

- [ ] **Step 4: Verify a cross-system read**

Run: `docker compose -f deploy/dev/docker-compose.yml exec postgres psql -U postgres -d reporting -c "SELECT count(*) FROM reporting.repositories;"`
Expected: a count (0+) — proves FDW reads the Forgejo DB through `reporting`.

- [ ] **Step 5: Create `apps/postgrest/postgrest.conf`**

```ini
db-uri = "postgres://authenticator:BI_AUTHENTICATOR_PASSWORD@postgres:5432/reporting"
db-schemas = "reporting"
db-anon-role = "bi_reader"
jwt-secret = "PGRST_JWT_SECRET_PLACEHOLDER"
server-port = 3000
```
> The conf is templated; real values are injected via env in compose (next step) using
> PostgREST's env-var override (`PGRST_DB_URI`, `PGRST_DB_SCHEMAS`, `PGRST_DB_ANON_ROLE`,
> `PGRST_JWT_SECRET`), so the file above is documentation; compose env is the source of truth.

- [ ] **Step 6: Add `postgrest` + `adminer` services** to `deploy/dev/docker-compose.yml`

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
    networks: [internal]    # NO ports: — reached via ssh -L

  adminer:
    image: adminer:4
    restart: unless-stopped
    depends_on:
      postgres: { condition: service_healthy }
    networks: [internal]    # NO ports: — reached via ssh -L
```

- [ ] **Step 7: Boot + smoke via the internal network**

```bash
docker compose -f deploy/dev/docker-compose.yml up -d postgrest adminer
sleep 5
# PostgREST should serve the view through the bi_reader role:
docker compose -f deploy/dev/docker-compose.yml exec postgrest \
  sh -c 'wget -qO- http://localhost:3000/repositories?limit=1'
```
Expected: JSON array (possibly empty `[]`) — proves PostgREST → reporting view works.

- [ ] **Step 8: Confirm N2 (no host ports for DB/PostgREST/Adminer)**

Run: `docker compose -f deploy/dev/docker-compose.yml ps --format '{{.Service}} {{.Ports}}' | grep -E 'postgres|postgrest|adminer'`
Expected: no `0.0.0.0:`/host-published port on any of the three.

- [ ] **Step 9: Commit**

```bash
git add apps/postgres/init/20-fdw-foreign-tables.sql apps/postgrest deploy/dev/docker-compose.yml
git commit -m "feat(reporting): FDW foreign tables, curated views, PostgREST + Adminer (N2)"
```

---

### Task 9: End-to-end bring-up, DNS, TLS verification, runbook

**Files:**
- Create: `docs/RUNBOOK.md`

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: a verified live stack and a one-page operational runbook.

- [ ] **Step 1: Provision the host** (if not already)

```bash
bash infra/scripts/create-lightsail.sh
```
Expected: prints the static IP and SSH command.

- [ ] **Step 2: DNS A-records** — create `git.`, `chat.`, `plane.code42.dev` → static IP. Verify:

Run: `for h in git chat plane; do dig +short $h.code42.dev; done`
Expected: each resolves to the static IP.

- [ ] **Step 3: Ship secrets and bring up the full stack on the host**

```bash
scp -i infra/scripts/devtools-key.pem deploy/dev/.env ubuntu@<ip>:/opt/devtools/deploy/dev/.env
ssh -i infra/scripts/devtools-key.pem ubuntu@<ip> '
  cd /opt/devtools && chmod 600 deploy/dev/.env &&
  docker login ghcr.io -u "$(grep ^GHCR_USER deploy/dev/.env|cut -d= -f2)" -p "$(grep ^GHCR_TOKEN deploy/dev/.env|cut -d= -f2)" &&
  docker compose -f deploy/dev/docker-compose.yml up -d'
```
Expected: all services `Up`; `plane-migrator` `Exited (0)`.

- [ ] **Step 4: Verify TLS + each app from the public internet**

```bash
for h in git chat plane; do
  echo "== $h =="; curl -fsS -o /dev/null -w '%{http_code} %{ssl_verify_result}\n' https://$h.code42.dev/
done
```
Expected: HTTP 200/302 and `ssl_verify_result` 0 (valid Let's Encrypt cert) for all three.

- [ ] **Step 5: Verify the BI path over an SSH tunnel**

```bash
ssh -i infra/scripts/devtools-key.pem -L 3001:127.0.0.1:3000 -L 5432:127.0.0.1:5432 ubuntu@<ip> -N &
# PostgREST: note port mapping requires a temporary ports: or socat; simplest is exec test from Task 8.
psql "postgres://authenticator:<pw>@127.0.0.1:5432/reporting" -c "SELECT count(*) FROM reporting.plane_issues;"
```
Expected: a row count — proves end-to-end reporting works against live Plane data.
(Note: because N2 publishes no host port for Postgres, the tunnel targets the container
via the host's docker network; if Postgres has no host port, run the check with
`docker compose exec` instead, as in Task 8 Step 4.)

- [ ] **Step 6: Write `docs/RUNBOOK.md`**

```markdown
# RUNBOOK

## Bring up / down
docker compose -f deploy/dev/docker-compose.yml up -d
docker compose -f deploy/dev/docker-compose.yml down        # NEVER add -v (data loss, no backups)

## Logs
docker compose -f deploy/dev/docker-compose.yml logs -f <service>

## Reach BI (N2)
ssh -L 5432:127.0.0.1:5432 ubuntu@<ip>   # then psql to reporting via docker exec

## Plane fork update
git -C apps/plane/upstream fetch upstream && git rebase upstream/<tag>
# resolve vs CHANGES.md, rebuild+push GHCR, bump PLANE_IMAGE_TAG in .env, up -d

## Add a reporting view
Edit apps/postgres/init/20-fdw-foreign-tables.sql, re-apply (Task 8 Step 3).

## DANGER (irreversible, no backups)
docker compose down -v · docker volume prune · destroy-lightsail.sh · deleting disk devtools-data
```

- [ ] **Step 7: Commit**

```bash
git add docs/RUNBOOK.md
git commit -m "docs: end-to-end runbook; verified live stack"
```

---

## Self-Review Notes

- **Spec coverage:** §2 decisions → Tasks 1–9; §4 services table → Tasks 3–8; §5 layout → Tasks 1,2,5,6,7; §6 BI flow → Task 8; §7 provisioning → Tasks 2,9; §8 security/N2 → Tasks 2 (firewall), 8 (no host ports verified); §9 verification → Tasks 5–9 smoke steps. Phase-2 apps (§10) intentionally excluded.
- **Known execution-time unknowns (not placeholders):** Plane's exact Dockerfile paths and backend env var names are resolved by inspecting the fork in Task 7 Step 2 before use — upstream owns those values; the plan names the commands to obtain them and the fallbacks.
- **Pinned versions** chosen are current-stable; bump only deliberately and pin (no `:latest`).
