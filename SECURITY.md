# Security

## Model
- **N2 network:** only ports 22 (SSH, owner IP via Lightsail firewall), 80, and 443
  (Caddy) are public. Postgres, PostgREST, Adminer, and MinIO publish **no host port**
  — reach them with `ssh -L <localport>:127.0.0.1:<svcport> <host>`.
- **TLS:** Caddy terminates with automatic Let's Encrypt certificates.
- **Auth:** each app has its own login (no SSO yet — model A1).
- **BI:** PostgREST connects as a SELECT-only `bi_reader` role over the `reporting`
  schema; it cannot reach app databases directly.

## Secrets
- Live in `deploy/<group>/.env` on the host, `chmod 600`, gitignored. Never committed.
- App secret keys, Postgres passwords, GHCR tokens, MinIO keys, WhatsApp Cloud API
  tokens are all env-only. Rotate by changing the env var and redeploying.
- `.gitignore` blocks `.env`, `*.env.plane`, `infra/scripts/*.pem`, `*.tfstate`,
  `*.tfvars`. Do not weaken it.

## Data
- No automated backups. The Lightsail block disk at `/data` is the only durability
  (survives instance recreation, not disk deletion). Treat destructive commands
  (`down -v`, volume prune, `destroy-lightsail.sh`, deleting the disk) as irreversible.

## Reporting a vulnerability
This is a private, single-operator deployment. Report issues directly to the owner
(`admin@analyticsbi.cloud`). Do not open public issues for security matters.
