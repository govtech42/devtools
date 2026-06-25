#!/usr/bin/env bash
# Create one DB + owner per name in APP_DBS (space-separated), the reporting DB,
# and the fdw_reader role. Per-app creds read by convention from env:
#   <UPPER>_DB / <UPPER>_DB_USER / <UPPER>_DB_PASSWORD
# Runs once on first init. Group-agnostic: each deploy/<group> sets APP_DBS.
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

# reporting DB + fdw_reader role first
su <<-SQL
	SELECT 'CREATE DATABASE ${REPORTING_DB} OWNER ${POSTGRES_USER}'
	  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${REPORTING_DB}')\gexec
	DO \$\$ BEGIN
	  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fdw_reader') THEN
	    CREATE ROLE fdw_reader LOGIN PASSWORD '${FDW_READER_PASSWORD}';
	  END IF;
	END \$\$;
	SQL

# one DB+owner per app named in APP_DBS, creds by convention
for name in $APP_DBS; do
  up=$(echo "$name" | tr '[:lower:]' '[:upper:]')
  db_var="${up}_DB"; user_var="${up}_DB_USER"; pass_var="${up}_DB_PASSWORD"
  db="${!db_var}"; user="${!user_var}"; pass="${!pass_var}"
  create_role_db "$db" "$user" "$pass"
  grant_reader "$db" "$user"
done

echo "00-databases: created [$APP_DBS] + ${REPORTING_DB} + fdw_reader"
