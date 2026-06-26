-- Planka reporting: FDW foreign table + curated view. Applied via `make reporting GROUP=support`.
\connect reporting
SELECT format('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L, port %L)',
              'planka_srv','localhost','planka','5432')
  WHERE NOT EXISTS (SELECT FROM pg_foreign_server WHERE srvname='planka_srv')\gexec
SELECT format('CREATE USER MAPPING FOR CURRENT_USER SERVER %I OPTIONS (user %L, password %L)',
              'planka_srv','fdw_reader',:'fdw_pass')
  WHERE NOT EXISTS (SELECT FROM pg_user_mappings WHERE srvname='planka_srv' AND usename=current_user)\gexec
CREATE SCHEMA IF NOT EXISTS planka_src;
CREATE FOREIGN TABLE IF NOT EXISTS planka_src.card (
  id          bigint,
  board_id    bigint,
  list_id     bigint,
  name        text,
  created_at  timestamptz
) SERVER planka_srv OPTIONS (schema_name 'public', table_name 'card');
CREATE OR REPLACE VIEW reporting.kanban_cards AS
  SELECT id, board_id, list_id, name, created_at FROM planka_src.card;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO bi_reader;
