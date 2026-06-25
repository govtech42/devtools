#!/usr/bin/env bash
# Apply reporting.sql.tmpl with the authenticator password injected from env.
set -euo pipefail
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d reporting \
  -v authn_pass="$BI_AUTHENTICATOR_PASSWORD" \
  -f /docker-entrypoint-initdb.d/reporting.sql.tmpl
echo "10-reporting: extension, schema, bi_reader, authenticator ready"
