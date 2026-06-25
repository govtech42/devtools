#!/usr/bin/env bash
# Static checks — no running stack required.
set -uo pipefail
GROUP="${1:-dev}"
cd "$(dirname "$0")/.."
# shellcheck source=test/lib.sh
source test/lib.sh

echo "== lint (group=$GROUP) =="

# 1. compose file parses + interpolates
check "compose config parses" dc config -q

# 2. shell scripts: syntax check
for f in infra/scripts/*.sh apps/postgres/init/*.sh test/*.sh; do
  [ -e "$f" ] || continue
  if bash -n "$f"; then pass "bash -n $f"; else fail "bash -n $f"; fi
done

# 3. JSON files valid
for f in infra/firewall.json; do
  [ -e "$f" ] || continue
  if jq empty "$f" >/dev/null 2>&1; then pass "jq $f"; else fail "jq $f"; fi
done

# 4. Caddyfile validates (if caddy context present)
if [ -f apps/caddy/Caddyfile ]; then
  if docker run --rm -e ACME_EMAIL=x -e FORGEJO_DOMAIN=git.example.com \
       -e MATTERMOST_DOMAIN=chat.example.com -e PLANE_DOMAIN=plane.example.com \
       -v "$PWD/apps/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine \
       caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
    pass "caddy validate"
  else
    fail "caddy validate"
  fi
fi

summary
