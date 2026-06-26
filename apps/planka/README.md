# planka — kanban (overlay + branding)

Overlays `ghcr.io/plankanban/planka:1.26.2` (multi-arch). DB: shared Postgres
`planka`. Listens on **1337**. Branding via files in `branding/` copied into the
image's static assets (see Dockerfile).

- Env: `DATABASE_URL`, `BASE_URL`, `SECRET_KEY`, `DEFAULT_ADMIN_*` (first admin).
- Migrates on boot. Native API (goal A) for programmatic access.
- Persistence: `/app/private` (attachments) on the `planka_data` volume.
