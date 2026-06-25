# plane — project management (OUR FORK)

Plane is the app we modify, so it is built from our fork, not an upstream image.

## Source
- Fork `makeplane/plane` → `github.com/code42/plane`.
- Vendored here as a submodule at `apps/plane/upstream/` (add at deploy time):
  ```bash
  git submodule add https://github.com/code42/plane.git apps/plane/upstream
  git -C apps/plane/upstream remote add upstream https://github.com/makeplane/plane.git
  git -C apps/plane/upstream fetch --all
  git -C apps/plane/upstream checkout -b code42
  ```

## Build / release / run (NEVER build on the host — OOM)
Build off-host (local arm64 dev box uses `--platform linux/amd64`, or GitHub Actions),
push to GHCR, host pulls. The fork already ships the Dockerfiles:
```bash
export TAG=code42-0.1.0 U=apps/plane/upstream
echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
for s in api web admin space live proxy; do
  case $s in
    api)   df=apps/api/Dockerfile.api ;;
    web)   df=apps/web/Dockerfile.web ;;
    admin) df=apps/admin/Dockerfile.admin ;;
    space) df=apps/space/Dockerfile.space ;;
    live)  df=apps/live/Dockerfile.live ;;
    proxy) df=apps/proxy/Dockerfile.ce ;;
  esac
  docker buildx build --platform linux/amd64 --push \
    -t ghcr.io/$GHCR_USER/plane-$s:$TAG -f $U/$df $U
done
```
Then on the host, with the `plane` profile:
`docker compose -f deploy/dev/docker-compose.yml --profile plane up -d`

## Rebase loop
```bash
git -C apps/plane/upstream fetch upstream
git -C apps/plane/upstream rebase upstream/<release-tag>
# resolve against CHANGES.md, rebuild, bump PLANE_IMAGE_TAG, redeploy
```

## Wiring
- DB: shared Postgres `plane` (upstream `plane-db` dropped). Backing services
  `plane-redis` (Valkey), `plane-mq` (RabbitMQ), `plane-minio` are Plane-owned.
- Env is supplied by the compose `environment:` block (interpolated from `.env`).
  Verify variable names against the fork's `apps/api/.env.example` before first boot.
- Native API (goal A): `https://plane.code42.dev/api`. Routed Caddy → `plane-proxy`.
- BI: apply `apps/plane/reporting-plane.sql` (FDW + `reporting.plane_issues`) once
  Plane has migrated.

## Local note
The `plane` compose profile is OFF by default, so local `make up` skips Plane
(the fork/images aren't built yet). Lint still validates the service definitions.
