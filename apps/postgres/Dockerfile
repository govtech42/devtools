FROM postgres:16-bookworm
# postgres_fdw ships with the official image's bundled contrib modules.
# Init scripts in /docker-entrypoint-initdb.d run once, on first init (empty data dir),
# in lexical order. *.sh and *.sql are executed; other extensions are ignored.
