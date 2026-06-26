# Recipe: cross-arch images & builds

Dev box is **arm64** (Apple Silicon + Colima); the Lightsail VPS is **amd64**.

## Running amd64-only images locally
Mattermost and Chatwoot publish amd64-only (or amd64-primary) images. They run on
the arm64 dev box under **Rosetta** (Colima VZ has it) — just slower to boot. Pin
`platform: linux/amd64` on the service so the right manifest is pulled. No action
needed beyond patience on first boot (poll health with retries in smoke).

## Building an overlay of an amd64-only base locally
The legacy Docker builder can't cross-build. Use **buildx**:
```bash
brew install docker-buildx
mkdir -p ~/.docker/cli-plugins
ln -sfn "$(brew --prefix docker-buildx)/bin/docker-buildx" ~/.docker/cli-plugins/docker-buildx
docker buildx create --name devtools --driver docker-container --use
docker buildx build --platform linux/amd64 --load -t devtools/mattermost:0.1.0 apps/mattermost
```
The Makefile `build` target does this for `dev` (mattermost) automatically.

## Forks → GHCR (Plane, Chatwoot)
Build the fork off-host for the VPS arch and push to GHCR; the host only pulls:
```bash
docker buildx build --platform linux/amd64 --push -t ghcr.io/$GHCR_USER/<app>:<tag> -f <fork>/<Dockerfile> <fork>
```
Then set `<APP>_IMAGE=ghcr.io/$GHCR_USER/<app>:<tag>` in the host `.env`. The VPS
builds everything else natively (`docker compose up -d --build`) — buildx is a
dev-box-only convenience.

## Multi-arch images (Twenty, Planka, Postgres, Caddy, Valkey, MinIO, Adminer)
These ship arm64 + amd64 → build/run native on both. No special handling.
