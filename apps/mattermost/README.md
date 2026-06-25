# mattermost — chat

Overlays `mattermost/mattermost-team-edition:10.11` (amd64; runs under Rosetta on
the arm64 dev box, native on the x86 VPS). DB: shared Postgres `mattermost`.

- Config via `MM_*` env (set in `deploy/<group>/docker-compose.yml`).
- Native API (goal A): `https://chat.code42.dev/api/v4`.
- Health: `GET /api/v4/system/ping`.
- Migrations run automatically on boot; first admin created on first web visit.
