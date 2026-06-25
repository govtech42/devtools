# apps/ — shared per-app contexts

One self-contained context per application. These are the reusable library;
`deploy/<group>/docker-compose.yml` composes them into a host.

| context | image strategy |
|---|---|
| `caddy` | official + bind-mounted Caddyfile |
| `postgres` | custom build (postgres + postgres_fdw), `init/` SQL |
| `forgejo` | overlay on official |
| `mattermost` | overlay on official |
| `plane` | **our fork** built off-host → GHCR (see `plane/README.md`) |
| `postgrest` | official, config-driven |
| `adminer` | official |

## Local testing (macOS, Colima)

```bash
make up           # GROUP=dev by default; brings the stack up via Colima
make smoke        # run the smoke suite
make down         # stop (keeps data)
```

`DATA_ROOT` selects where volumes live: `/data` on the VPS, `<repo>/.data` locally.
Secrets: copy `deploy/dev/.env.example` → `deploy/dev/.env`, fill, `chmod 600`.

Reach Postgres/PostgREST/Adminer (N2 — no public port): `ssh -L 5432:127.0.0.1:5432 <host>`.
