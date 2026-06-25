-- Plane reporting: apply AFTER the Plane stack has migrated (its tables exist).
-- Run: cat apps/plane/reporting-plane.sql | docker compose ... exec -T postgres \
--        psql -v ON_ERROR_STOP=1 -U postgres -d reporting -v fdw_pass="$FDW_READER_PASSWORD"
\connect reporting

SELECT format('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L, port %L)',
              'plane_srv','localhost','plane','5432')
  WHERE NOT EXISTS (SELECT FROM pg_foreign_server WHERE srvname='plane_srv')\gexec
SELECT format('CREATE USER MAPPING FOR CURRENT_USER SERVER %I OPTIONS (user %L, password %L)',
              'plane_srv','fdw_reader',:'fdw_pass')
  WHERE NOT EXISTS (SELECT FROM pg_user_mappings WHERE srvname='plane_srv' AND usename=current_user)\gexec

CREATE SCHEMA IF NOT EXISTS plane_src;

-- Plane uses UUID keys and timestamptz. Confirm column names against the fork's
-- issues table before first apply (Plane's schema evolves between releases).
CREATE FOREIGN TABLE IF NOT EXISTS plane_src.issues (
  id           uuid,
  name         text,
  priority     text,
  created_at   timestamptz,
  completed_at timestamptz,
  project_id   uuid
) SERVER plane_srv OPTIONS (schema_name 'public', table_name 'issues');

CREATE OR REPLACE VIEW reporting.plane_issues AS
  SELECT id, name, priority, created_at, completed_at, project_id
  FROM plane_src.issues;

GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO bi_reader;
