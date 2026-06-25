-- Reporting layer: FDW foreign tables + curated read-only views.
-- Applied AFTER the apps have migrated (NOT an init script). Run: `make reporting`.
-- Idempotent. Foreign tables are declared with an explicit minimal column list
-- (NOT IMPORT FOREIGN SCHEMA) so app-side custom types (e.g. Mattermost's
-- channel_type enum) don't break the import — enums travel as text over the wire.
\connect reporting

-- ---- foreign servers (same Postgres instance, host=localhost) ----
SELECT format('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L, port %L)',
              'forgejo_srv','localhost','forgejo','5432')
  WHERE NOT EXISTS (SELECT FROM pg_foreign_server WHERE srvname='forgejo_srv')\gexec
SELECT format('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L, port %L)',
              'mattermost_srv','localhost','mattermost','5432')
  WHERE NOT EXISTS (SELECT FROM pg_foreign_server WHERE srvname='mattermost_srv')\gexec

-- ---- user mappings (fdw_reader; :'fdw_pass' substituted in plain SQL, not in DO) ----
SELECT format('CREATE USER MAPPING FOR CURRENT_USER SERVER %I OPTIONS (user %L, password %L)',
              'forgejo_srv','fdw_reader',:'fdw_pass')
  WHERE NOT EXISTS (SELECT FROM pg_user_mappings WHERE srvname='forgejo_srv' AND usename=current_user)\gexec
SELECT format('CREATE USER MAPPING FOR CURRENT_USER SERVER %I OPTIONS (user %L, password %L)',
              'mattermost_srv','fdw_reader',:'fdw_pass')
  WHERE NOT EXISTS (SELECT FROM pg_user_mappings WHERE srvname='mattermost_srv' AND usename=current_user)\gexec

CREATE SCHEMA IF NOT EXISTS forgejo_src;
CREATE SCHEMA IF NOT EXISTS mattermost_src;

-- ---- explicit foreign tables (minimal columns; enum -> text) ----
CREATE FOREIGN TABLE IF NOT EXISTS forgejo_src.repository (
  id          bigint,
  owner_id    bigint,
  owner_name  varchar,
  lower_name  varchar,
  is_private  boolean,
  created_unix bigint
) SERVER forgejo_srv OPTIONS (schema_name 'public', table_name 'repository');

CREATE FOREIGN TABLE IF NOT EXISTS mattermost_src.channels (
  id          varchar,
  createat    bigint,
  type        text,          -- remote type is the channel_type enum
  displayname varchar,
  name        varchar
) SERVER mattermost_srv OPTIONS (schema_name 'public', table_name 'channels');

-- ---- curated views (stable contract) ----
CREATE OR REPLACE VIEW reporting.repositories AS
  SELECT id, owner_id, owner_name, lower_name AS name, is_private, created_unix
  FROM forgejo_src.repository;

CREATE OR REPLACE VIEW reporting.chat_channels AS
  SELECT id, name, displayname, type, createat
  FROM mattermost_src.channels;

GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO bi_reader;
