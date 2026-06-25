#!/usr/bin/env bash
# Live smoke suite, group-aware. Runs against the running stack; checks adapt to
# what's up. Usage: bash test/smoke.sh <dev|support|admin>
set -uo pipefail
GROUP="${1:-dev}"
cd "$(dirname "$0")/.."
# shellcheck source=test/lib.sh
source test/lib.sh

echo "== smoke (group=$GROUP) =="

# HTTP checks run from a throwaway curl container on the compose network,
# because app images don't all ship curl/wget.
NET="devtools-${GROUP}_net"
http() { docker run --rm --network "$NET" curlimages/curl:8.10.1 -fsS --max-time 10 "$1" >/dev/null 2>&1; }
http_body() { docker run --rm --network "$NET" curlimages/curl:8.10.1 -fsS --max-time 10 "$1" 2>/dev/null; }

# Shared: postgres core (given app DB list) + reporting roles/extension.
pg_core() {  # "<db1 db2 ...>"
  if running postgres; then
    check "postgres accepts connections" dc exec -T postgres pg_isready -U postgres
    for db in $1 reporting; do
      check_eq "database '$db' exists" "1" psql_super postgres "SELECT 1 FROM pg_database WHERE datname='$db'"
    done
    for role in fdw_reader bi_reader authenticator; do
      check_eq "role '$role' exists" "1" psql_super postgres "SELECT 1 FROM pg_roles WHERE rolname='$role'"
    done
    check_eq "postgres_fdw in reporting" "postgres_fdw" \
      psql_super reporting "SELECT extname FROM pg_extension WHERE extname='postgres_fdw'"
  else skip "postgres not running"; fi
}

# Shared: HTTP retry (slow boots under emulation).
http_retry() {  # url tries
  for _ in $(seq 1 "${2:-20}"); do http "$1" && return 0; sleep 3; done; return 1
}

# Shared: N2 — no published host ports on the listed services.
n2_check() {  # "<svc-regex>"
  local bad
  bad="$(dc ps --format '{{.Service}} {{.Ports}}' 2>/dev/null | grep -E "$1" | grep -E '0\.0\.0\.0:|\[::\]:' || true)"
  [ -z "$bad" ] && pass "N2: no published host ports ($1)" || fail "N2 violated" "$bad"
}

case "$GROUP" in
dev)
  pg_core "forgejo mattermost plane"
  running forgejo && check "forgejo /api/healthz" http http://forgejo:3000/api/healthz || skip "forgejo not running"
  if running mattermost; then
    http_retry http://mattermost:8065/api/v4/system/ping 20 && \
      [ -n "$(http_body http://mattermost:8065/api/v4/system/ping | grep -o '"status":"OK"')" ] \
      && pass "mattermost ping OK" || fail "mattermost ping not OK"
  else skip "mattermost not running"; fi
  running plane-proxy && check "plane-proxy responds" http http://plane-proxy:80/ || skip "plane-proxy not running"
  if running postgres && psql_super reporting "SELECT to_regclass('reporting.repositories')" 2>/dev/null | grep -q repositories; then
    psql_super reporting "SELECT count(*) FROM reporting.repositories" 2>/dev/null | grep -qE '^[0-9]+$' \
      && pass "reporting.repositories readable via FDW" || fail "reporting.repositories read failed"
  else skip "reporting views not present yet"; fi
  running postgrest && check "postgrest serves a reporting view" http "http://postgrest:3000/repositories?limit=1" || skip "postgrest not running"
  n2_check 'postgres|postgrest|adminer'
  ;;
support)
  pg_core "planka chatwoot"
  running planka && check "planka responds" http http://planka:1337/ || skip "planka not running"
  running chatwoot-web && { http_retry http://chatwoot-web:3000/api 30 && pass "chatwoot /api responds" || fail "chatwoot /api not responding"; } || skip "chatwoot-web not running"
  running minio && check "minio live" http http://minio:9000/minio/health/live || skip "minio not running"
  if running postgres && psql_super reporting "SELECT to_regclass('reporting.kanban_cards')" 2>/dev/null | grep -q kanban_cards; then
    psql_super reporting "SELECT count(*) FROM reporting.kanban_cards" 2>/dev/null | grep -qE '^[0-9]+$' \
      && pass "reporting.kanban_cards readable via FDW" || fail "reporting.kanban_cards read failed"
  else skip "reporting views not present yet"; fi
  running postgrest && check "postgrest reachable" http "http://postgrest:3000/" || skip "postgrest not running"
  n2_check 'postgres|postgrest|adminer|minio'
  ;;
admin)
  pg_core "twenty"
  if running twenty-server; then
    http_retry http://twenty-server:3000/healthz 40 && pass "twenty-server /healthz" || fail "twenty-server /healthz not responding"
  else skip "twenty-server not running"; fi
  running twenty-worker && pass "twenty-worker running" || skip "twenty-worker not running"
  # Twenty curated reporting views are deferred (dynamic schema); just assert the
  # reporting infra is reachable.
  running postgrest && check "postgrest reachable" http "http://postgrest:3000/" || skip "postgrest not running"
  n2_check 'postgres|postgrest|adminer'
  ;;
*)
  fail "unknown group: $GROUP"; ;;
esac

summary
