# chatwoot — helpdesk (OUR FORK)

Fork `chatwoot/chatwoot` → `github.com/code42/chatwoot`, submodule at
`apps/chatwoot/upstream/` (branch `code42`). We add **Kanban + product features**
(log each change in `CHANGES.md`). Build **off-host → GHCR**, host pulls. Locally,
`CHATWOOT_IMAGE` defaults to the official image to validate wiring before fork work.

- **DB:** shared Postgres `chatwoot` (needs the `vector` extension — pre-created via
  `CHATWOOT_DB_EXTENSIONS=vector`; role has `CREATEDB` for `db:chatwoot_prepare`).
- **Redis:** own `chatwoot-redis` (Sidekiq). **Migrations:** `chatwoot-init` runs
  `bundle exec rails db:chatwoot_prepare` once.
- **Storage:** MinIO (bucket `chatwoot`) via Active Storage S3 on the VPS
  (`CHATWOOT_STORAGE=s3_compatible`); local testing uses `local` for boot reliability.
- **WhatsApp:** Cloud API (official) — add the channel in the UI; webhook →
  `https://support.code42.dev`.
- Native API (goal A): `https://support.code42.dev/api`.

## Fork build (off-host → GHCR)
```bash
git submodule add https://github.com/code42/chatwoot.git apps/chatwoot/upstream
git -C apps/chatwoot/upstream remote add upstream https://github.com/chatwoot/chatwoot.git
export TAG=code42-0.1.0 U=apps/chatwoot/upstream
docker buildx build --platform linux/amd64 --push -t ghcr.io/$GHCR_USER/chatwoot:$TAG -f $U/docker/Dockerfile $U
# set CHATWOOT_IMAGE=ghcr.io/code42/chatwoot:code42-0.1.0 on the host
```
