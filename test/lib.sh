#!/usr/bin/env bash
# Shared test helpers. Source this; set GROUP before sourcing (default dev).
set -uo pipefail

GROUP="${GROUP:-dev}"
DIR="deploy/${GROUP}"
COMPOSE=(docker compose -f "${DIR}/docker-compose.yml" --env-file "${DIR}/.env")

PASS=0; FAIL=0; SKIP=0

pass() { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  \033[33mSKIP\033[0m %s\n' "$1"; }

dc() { "${COMPOSE[@]}" "$@"; }

# is a compose service currently running?
running() { dc ps --status running --services 2>/dev/null | grep -qx "$1"; }

# run psql as superuser inside the postgres container; args after db
psql_super() { local db="$1"; shift; dc exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres -d "$db" -tAc "$@"; }

# assert a command succeeds
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc" "cmd: $*"; fi; }

# assert command stdout equals expected
check_eq() { local desc="$1" expected="$2"; shift 2; local got; got="$("$@" 2>/dev/null)"; \
  if [ "$got" = "$expected" ]; then pass "$desc"; else fail "$desc" "expected '$expected' got '$got'"; fi; }

summary() {
  printf '\n  %s passed, %s failed, %s skipped\n' "$PASS" "$FAIL" "$SKIP"
  [ "$FAIL" -eq 0 ]
}
