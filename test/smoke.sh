#!/usr/bin/env bash
# Live smoke suite. Runs against the running stack; checks adapt to what's up.
set -uo pipefail
GROUP="${1:-dev}"
cd "$(dirname "$0")/.."
# shellcheck source=test/lib.sh
source test/lib.sh

echo "== smoke (group=$GROUP) =="

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
  check "forgejo /api/healthz" dc exec -T forgejo curl -fsS http://localhost:3000/api/healthz
else
  skip "forgejo not running"
fi

# --- Mattermost ---
if running mattermost; then
  check "mattermost /api/v4/system/ping" dc exec -T mattermost curl -fsS http://localhost:8065/api/v4/system/ping
else
  skip "mattermost not running"
fi

# --- Plane proxy ---
if running plane-proxy; then
  check "plane-proxy responds" dc exec -T plane-proxy sh -c 'wget -qO- http://localhost:80/ >/dev/null'
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
  check "postgrest serves a reporting view" \
    dc exec -T postgrest sh -c 'wget -qO- http://localhost:3000/repositories?limit=1 >/dev/null'
else
  skip "postgrest not running"
fi

# --- N2: no public host ports for DB/PostgREST/Adminer ---
bad="$(dc ps --format '{{.Service}} {{.Ports}}' 2>/dev/null | grep -E 'postgres|postgrest|adminer' | grep -E '0\.0\.0\.0:|\[::\]:' || true)"
if [ -z "$bad" ]; then pass "N2: no published host ports on postgres/postgrest/adminer"; else fail "N2 violated" "$bad"; fi

summary
