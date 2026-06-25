#!/usr/bin/env bash
# Create one database + owner role per app, the reporting DB, and the fdw_reader
# role that the reporting DB uses to read app tables. Runs once on first init.
set -euo pipefail

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

create_role_db "$FORGEJO_DB"    "$FORGEJO_DB_USER"    "$FORGEJO_DB_PASSWORD"
create_role_db "$MATTERMOST_DB" "$MATTERMOST_DB_USER" "$MATTERMOST_DB_PASSWORD"
create_role_db "$PLANE_DB"      "$PLANE_DB_USER"      "$PLANE_DB_PASSWORD"

# reporting DB owned by the superuser (it hosts FDW + curated views)
su <<-SQL
	SELECT 'CREATE DATABASE ${REPORTING_DB} OWNER ${POSTGRES_USER}'
	  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${REPORTING_DB}')\gexec
	SQL

# read-only role used by the reporting DB's FDW user mappings
su <<-SQL
	DO \$\$ BEGIN
	  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fdw_reader') THEN
	    CREATE ROLE fdw_reader LOGIN PASSWORD '${FDW_READER_PASSWORD}';
	  END IF;
	END \$\$;
	SQL

# Grant fdw_reader SELECT on each app DB — including FUTURE tables the app creates.
# Apps own their tables, so default privileges must be set FOR the app's role.
grant_reader() {  # db appuser
  local db="$1" appuser="$2"
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<-SQL
	GRANT CONNECT ON DATABASE ${db} TO fdw_reader;
	GRANT USAGE ON SCHEMA public TO fdw_reader;
	GRANT SELECT ON ALL TABLES IN SCHEMA public TO fdw_reader;
	ALTER DEFAULT PRIVILEGES FOR ROLE ${appuser} IN SCHEMA public GRANT SELECT ON TABLES TO fdw_reader;
	SQL
}
grant_reader "$FORGEJO_DB"    "$FORGEJO_DB_USER"
grant_reader "$MATTERMOST_DB" "$MATTERMOST_DB_USER"
grant_reader "$PLANE_DB"      "$PLANE_DB_USER"

echo "00-databases: app DBs, reporting DB, fdw_reader ready"
