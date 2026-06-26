# RUNBOOK — VPS Dev Tools

Group `dev` (Forgejo, Mattermost, Plane). Local dev uses **Colima**; the VPS uses
Docker. Same compose, `DATA_ROOT` differs (`<repo>/.data` local, `/data` on VPS).

## Local (macOS + Colima)

```bash
make lint                 # static checks (compose config, bash -n, caddy validate)
make up                   # colima + build (mattermost cross-built amd64) + core stack
make reporting            # apply FDW + reporting views (after apps migrate)
make smoke                # live smoke suite (expect 17 pass, plane skipped)
make down                 # stop (keeps .data)
make logs SVC=forgejo     # follow a service
```

Plane is OFF locally (profile `plane`, fork images not built). Mattermost is
amd64-only → built with `docker buildx` on the arm64 dev box.

## VPS (Lightsail, group dev)

```bash
bash infra/scripts/create-lightsail.sh          # instance(16GB)+static IP+disk+firewall
# DNS: git/chat/plane.code42.dev -> printed static IP
scp -i infra/scripts/devtools-key.pem deploy/dev/.env \
    ubuntu@<ip>:/opt/devtools/deploy/dev/.env    # set DATA_ROOT=/data, then chmod 600
ssh -i infra/scripts/devtools-key.pem ubuntu@<ip>
# on host:
cd /opt/devtools && docker login ghcr.io -u <GHCR_USER> -p <GHCR_TOKEN>
# Plane fork: add submodule, build+push images to GHCR (see apps/plane/README.md)
docker compose -f deploy/dev/docker-compose.yml --profile plane up -d
make reporting GROUP=dev
cat apps/plane/reporting-plane.sql | docker compose -f deploy/dev/docker-compose.yml \
    --env-file deploy/dev/.env exec -T postgres \
    psql -v ON_ERROR_STOP=1 -U postgres -d reporting -v fdw_pass="<FDW_READER_PASSWORD>"
```

The VPS builds everything natively (amd64); no buildx needed —
`docker compose ... up -d --build`.

## Verify (TLS, live)

```bash
for h in git chat plane; do curl -fsS -o /dev/null -w '%{http_code} ssl=%{ssl_verify_result}\n' https://$h.code42.dev/; done
```

## BI access (N2 — no public DB/PostgREST/Adminer ports)

```bash
ssh -L 5432:127.0.0.1:5432 ubuntu@<ip>     # then psql via docker exec, or a BI tool
# PostgREST/Adminer reached the same way (tunnel to their container ports)
```

## Plane fork update

```bash
git -C apps/plane/upstream fetch upstream
git -C apps/plane/upstream rebase upstream/<tag>   # resolve vs apps/plane/CHANGES.md
# rebuild+push GHCR, bump PLANE_IMAGE_TAG in .env, redeploy
```

## Add a reporting view

Edit `apps/postgres/reporting.sql` (or `apps/plane/reporting-plane.sql`), re-run
`make reporting` (idempotent).

## DANGER — irreversible, NO BACKUPS

`docker compose down -v` · `docker volume prune` · removing `DATA_ROOT`/the Lightsail
disk `devtools-data` · `infra/scripts/destroy-lightsail.sh`. Confirm before running.

## Admin group (Twenty CRM)

```bash
make up GROUP=admin && make smoke GROUP=admin     # local (Colima)
```
VPS: `NAME=devtools-admin BUNDLE=large_2_0 DISK_NAME=admin-data bash infra/scripts/create-lightsail.sh`
DNS: `crm.code42.dev` -> admin static IP. Native API (goal A): Twenty GraphQL/REST at https://crm.code42.dev.
Reporting: per-group infra present; curated Twenty views deferred (dynamic schema).

## Support group (Planka + Chatwoot)

```bash
make up GROUP=support
# wait for planka + chatwoot, then:
make reporting GROUP=support
make smoke GROUP=support          # expect 14/0
```
VPS: `NAME=devtools-support BUNDLE=large_2_0 DISK_NAME=support-data bash infra/scripts/create-lightsail.sh`
DNS: `board.`/`support.code42.dev` -> support static IP.
- Chatwoot fork: build off-host -> GHCR, set `CHATWOOT_IMAGE` + `CHATWOOT_STORAGE=s3_compatible` on the host (MinIO).
- WhatsApp: add the Cloud API channel in the Chatwoot UI; webhook -> https://support.code42.dev
- Local note: Chatwoot/Mattermost are amd64 — they run under Rosetta on the arm64 dev box (slow first boot).

## Monitoring group (Beszel)

```bash
make up GROUP=monitoring && make smoke GROUP=monitoring   # hub only (agents profile off)
```
VPS: `NAME=devtools-monitoring BUNDLE=small_2_0 DISK_NAME=monitoring-data bash infra/scripts/create-lightsail.sh`
DNS: `status.code42.dev` -> monitoring static IP.
Agents: in the Beszel UI copy the public key -> set `BESZEL_KEY` in `.env`, then
`docker compose -f deploy/monitoring/docker-compose.yml --profile agents up -d`.
Remote agents on other hosts are cross-host (deferred).
