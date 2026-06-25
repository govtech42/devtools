# infra/ — Lightsail provisioning (no OpenTofu)

All cloud/host provisioning. Per deployment group (Dev = 16 GB `xlarge_2_0`,
Support = 8 GB `large_2_0`). Requires AWS CLI v2 (`aws configure`).

## Provision

```bash
# Dev group (default)
bash infra/scripts/create-lightsail.sh
# Support group (later): override bundle/name
NAME=devtools-support BUNDLE=large_2_0 DISK_NAME=support-data bash infra/scripts/create-lightsail.sh
```

It creates: key pair (`infra/scripts/<KEY_PAIR>.pem`, gitignored), instance,
static IP, attached block disk (`/dev/xvdf` → `/data`), firewall (22 owner-IP,
80, 443), and runs `user-data.sh` (Docker, 4 GB swap, mount `/data`, clone repo).

## After provisioning

1. DNS A-records `git.`/`chat.`/`plane.code42.dev` → printed static IP.
2. `scp -i infra/scripts/devtools-key.pem deploy/dev/.env ubuntu@<ip>:/opt/devtools/deploy/dev/.env`
   (set `DATA_ROOT=/data`), then `chmod 600`.
3. `ssh` in, `docker login ghcr.io`, build/push the Plane fork images to GHCR.
4. `docker compose -f deploy/dev/docker-compose.yml --profile plane up -d`
5. `make reporting GROUP=dev` (after apps migrate) and apply `apps/plane/reporting-plane.sql`.

## Teardown (DANGER — no backups)

```bash
bash infra/scripts/destroy-lightsail.sh   # deletes instance + IP; KEEPS the data disk
```

`firewall.json` holds the port rules (`OWNER_IP` is substituted at apply time).
