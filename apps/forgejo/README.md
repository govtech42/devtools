# forgejo — git hosting

Overlays `codeberg.org/forgejo/forgejo:11`. DB: shared Postgres `forgejo`.

- Config via `FORGEJO__<section>__<KEY>` env (set in `deploy/<group>/docker-compose.yml`).
- Native API (goal A): `https://git.code42.dev/api/v1`.
- Health: `GET /api/healthz`.
- First run: create the admin via the web installer, or lock install and use
  `forgejo admin user create` (CLI) — decide at deploy.
