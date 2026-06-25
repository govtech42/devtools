# postgrest — BI REST API over `reporting`

Serves the `reporting` schema's curated views as a REST API. Connects as the
`authenticator` role and switches to `bi_reader` (SELECT-only on `reporting`).

- **N2:** no published host port. Reach it via SSH tunnel, e.g.
  `ssh -L 3001:127.0.0.1:<postgrest-port> <host>` (or query from a sidecar).
- Config is driven by `PGRST_*` env in the compose file; `postgrest.conf` is a
  reference only.
- The view set is defined in `apps/postgres/reporting.sql` (apply with `make reporting`).
- Adminer (also no host port) is the SQL explorer over the same DB.
