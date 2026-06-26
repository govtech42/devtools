# VPS Dev Tools

Self-hosted developer & business tooling on AWS Lightsail, Docker Compose, and a
shared PostgreSQL — one repo, several **deployment groups**, one host per group.

| Group | Apps | Subdomains | Status |
|---|---|---|---|
| **Dev** | Forgejo (git), Mattermost (chat), Plane (PM) | `git.` `chat.` `plane.` | shipped |
| **Support** | Planka (kanban), Chatwoot (helpdesk, WhatsApp) | `board.` `support.` | shipped |
| **Admin** | Twenty CRM | `crm.` | shipped |
| **Monitoring** | Beszel (*to confirm*) | `status.` | radar |

Each host is self-contained: **Caddy** (sole public ingress, auto-TLS) + **Postgres**
(one DB per app) + a curated **`reporting`** layer (`postgres_fdw` → read-only views →
**PostgREST**). Network model **N2**: only 22/80/443 are public; Postgres/PostgREST/
Adminer/MinIO are reachable only via SSH tunnel.

## Quickstart (local, macOS + Colima)

```bash
devtools init                 # Colima + buildx + per-group .env + data dirs
devtools up   --dev           # bring a group up   (also --support / --admin)
devtools smoke --dev          # live smoke suite
devtools down --dev           # stop, KEEPS data
```
`bin/devtools` wraps the `Makefile` (`make up GROUP=dev`, etc.). `DATA_ROOT` gives
dev/prod parity (`<repo>/.data-*` local, `/data` on the VPS).

## Deploy (VPS)

```bash
NAME=devtools-dev BUNDLE=xlarge_2_0 bash infra/scripts/create-lightsail.sh
# DNS -> static IP; scp deploy/<group>/.env; docker compose ... up -d
```
See [docs/RUNBOOK.md](docs/RUNBOOK.md).

## Layout

```
infra/      cloud/host provisioning (Lightsail AWS CLI scripts, no OpenTofu)
apps/       shared per-app contexts (caddy, postgres, forgejo, mattermost, plane,
            planka, chatwoot, twenty, postgrest, adminer)
deploy/     one docker-compose per group -> one host (dev, support, admin)
test/       lint + group-aware live smoke
bin/        devtools CLI
docs/       specs, plans, recipes, RUNBOOK
```

## Docs

- [DECISIONS.md](DECISIONS.md) — durable decision ledger (the *why* + pivots)
- [docs/RUNBOOK.md](docs/RUNBOOK.md) — operate each group, local + VPS
- [docs/recipes/](docs/recipes/) — onboarding a new app + hard-won gotchas
- [docs/superpowers/specs/](docs/superpowers/specs/) — design specs per group
- [CONTRIBUTING.md](CONTRIBUTING.md) · [SECURITY.md](SECURITY.md) · [ARCHITECTURE.md](ARCHITECTURE.md)
- [CLAUDE.md](CLAUDE.md) — operating doctrine (Karpathy + twelve-factor)

## Conventions

Plane and Chatwoot are **our forks** (built off-host → GHCR; submodule under
`apps/<app>/upstream`). Everything else overlays official images. Pin tags, no
`:latest` in production. **No backups exist** — the Lightsail block disk at `/data`
is the only durability; guard destructive commands.
