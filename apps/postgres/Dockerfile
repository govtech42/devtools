FROM pgvector/pgvector:pg16
# pgvector image = postgres:16 + the `vector` extension + bundled contrib
# (incl. postgres_fdw). Chatwoot needs `vector`; the other apps simply ignore it.
# Init scripts in /docker-entrypoint-initdb.d run once, on first init (empty data dir),
# in lexical order. *.sh and *.sql are executed; other extensions are ignored.
