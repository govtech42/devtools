-- Chatwoot reporting: FDW foreign table + curated view. Applied via `make reporting GROUP=support`.
\connect reporting
SELECT format('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L, port %L)',
              'chatwoot_srv','localhost','chatwoot','5432')
  WHERE NOT EXISTS (SELECT FROM pg_foreign_server WHERE srvname='chatwoot_srv')\gexec
SELECT format('CREATE USER MAPPING FOR CURRENT_USER SERVER %I OPTIONS (user %L, password %L)',
              'chatwoot_srv','fdw_reader',:'fdw_pass')
  WHERE NOT EXISTS (SELECT FROM pg_user_mappings WHERE srvname='chatwoot_srv' AND usename=current_user)\gexec
CREATE SCHEMA IF NOT EXISTS chatwoot_src;
CREATE FOREIGN TABLE IF NOT EXISTS chatwoot_src.conversations (
  id          bigint,
  account_id  bigint,
  inbox_id    bigint,
  status      integer,
  priority    integer,
  display_id  bigint,
  created_at  timestamptz
) SERVER chatwoot_srv OPTIONS (schema_name 'public', table_name 'conversations');
CREATE OR REPLACE VIEW reporting.support_conversations AS
  SELECT id, account_id, inbox_id, status, priority, display_id, created_at
  FROM chatwoot_src.conversations;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO bi_reader;
