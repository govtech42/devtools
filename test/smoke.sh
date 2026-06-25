#!/usr/bin/env bash
# Live smoke suite. Runs against the running stack; checks adapt to what's up.
set -uo pipefail
GROUP="${1:-dev}"
cd "$(dirname "$0")/.."
# shellcheck source=test/lib.sh
source test/lib.sh

echo "== smoke (group=$GROUP) =="

# HTTP checks run from a throwaway curl container on the compose network,
# because app images (Mattermost, proxies) don't ship curl/wget.
NET="devtools-${GROUP}_net"
http() { docker run --rm --network "$NET" curlimages/curl:8.10.1 -fsS --max-time 10 "$1" >/dev/null 2>&1; }
http_body() { docker run --rm --network "$NET" curlimages/curl:8.10.1 -fsS --max-time 10 "$1" 2>/dev/null; }

# --- Postgres ---
if running postgres; then
  check "postgres accepts connections" dc exec -T postgres pg_isready -U postgres
  for db in forgejo mattermost plane reporting; do
    check_eq "database '$db' exists" "1" \
      psql_super postgres "SELECT 1 FROM pg_database WHERE datname='$db'"
  done
  for role in forgejo mattermost plane fdw_reader bi_reader authenticator; do
    check_eq "role '$role' exists" "1" \
      psql_super postgres "SELECT 1 FROM pg_roles WHERE rolname='$role'"
  done
  check_eq "postgres_fdw in reporting" "postgres_fdw" \
    psql_super reporting "SELECT extname FROM pg_extension WHERE extname='postgres_fdw'"
else
  skip "postgres not running"
fi

# --- Forgejo ---
if running forgejo; then
  check "forgejo /api/healthz" http http://forgejo:3000/api/healthz
else
  skip "forgejo not running"
fi

# --- Mattermost (retry: web server lags migration, esp. under emulation) ---
if running mattermost; then
  ok=""
  for _ in $(seq 1 20); do
    http_body http://mattermost:8065/api/v4/system/ping 2>/dev/null | grep -q '"status":"OK"' && { ok=1; break; }
    sleep 3
  done
  [ -n "$ok" ] && pass "mattermost /api/v4/system/ping OK" || fail "mattermost ping not OK (after retries)"
else
  skip "mattermost not running"
fi

# --- Plane proxy ---
if running plane-proxy; then
  check "plane-proxy responds" http http://plane-proxy:80/
else
  skip "plane-proxy not running"
fi

# --- reporting views via FDW ---
if running postgres && [ "$(psql_super reporting "SELECT count(*) FROM information_schema.views WHERE table_schema='reporting'" 2>/dev/null)" != "0" ] \
   && psql_super reporting "SELECT count(*) FROM information_schema.views WHERE table_schema='reporting'" >/dev/null 2>&1; then
  # FDW read works if a SELECT against a reporting view returns a non-empty (numeric) count
  if psql_super reporting "SELECT count(*) FROM reporting.repositories" 2>/dev/null | grep -qE '^[0-9]+$'; then
    pass "reporting.repositories readable via FDW"
  else
    fail "reporting.repositories read failed (FDW)"
  fi
else
  skip "reporting views not present yet"
fi

# --- PostgREST ---
if running postgrest; then
  check "postgrest serves a reporting view" http "http://postgrest:3000/repositories?limit=1"
else
  skip "postgrest not running"
fi

# --- N2: no public host ports for DB/PostgREST/Adminer ---
bad="$(dc ps --format '{{.Service}} {{.Ports}}' 2>/dev/null | grep -E 'postgres|postgrest|adminer' | grep -E '0\.0\.0\.0:|\[::\]:' || true)"
if [ -z "$bad" ]; then pass "N2: no published host ports on postgres/postgrest/adminer"; else fail "N2 violated" "$bad"; fi

summary
