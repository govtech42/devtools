#!/usr/bin/env bash
# Lightsail first-boot bootstrap (Ubuntu 24.04). Idempotent where practical.
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

REPO_URL="${REPO_URL:-https://github.com/govtech42/devtools.git}"  # private repo
APP_DIR="/opt/devtools"
DATA_DISK="${DATA_DISK:-/dev/xvdf}"   # first attached Lightsail block disk; verify with lsblk

echo "== install docker =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl git gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker ubuntu || true   # run docker without sudo (next login)

echo "== 4GB swap =="
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

echo "== mount block disk at /data =="
if [ -b "$DATA_DISK" ]; then
  blkid "$DATA_DISK" >/dev/null 2>&1 || mkfs.ext4 -F "$DATA_DISK"
  mkdir -p /data
  grep -q "$DATA_DISK" /etc/fstab || echo "$DATA_DISK /data ext4 defaults,nofail 0 2" >> /etc/fstab
  mount -a
else
  echo "WARN: $DATA_DISK not present; using instance disk for /data"
  mkdir -p /data
fi
# data dirs matching the compose bind volumes (DATA_ROOT=/data on the VPS).
# Group-agnostic — mirrors infra/scripts/bootstrap-host.sh and the Makefile so any
# group works regardless of which one this host runs.
mkdir -p \
  /data/caddy/data /data/caddy/config /data/postgres /data/forgejo \
  /data/mattermost/data /data/mattermost/config \
  /data/plane/minio /data/plane/redis /data/plane/rabbitmq \
  /data/planka /data/chatwoot/storage /data/chatwoot/redis /data/minio \
  /data/twenty /data/twenty-docker-data /data/beszel

echo "== clone repo =="
# Non-fatal: the repo is private, so a first-boot clone may fail without creds —
# the installer ships the repo via rsync afterwards. Everything above already ran.
if [ ! -d "$APP_DIR/.git" ]; then
  git clone "$REPO_URL" "$APP_DIR" || echo "WARN: clone falhou (repo privado?). Use o instalador (rsync) ou clone manualmente."
else
  git -C "$APP_DIR" pull --ff-only || true
fi
mkdir -p "$APP_DIR"
chown -R ubuntu:ubuntu "$APP_DIR" /data || true

cat <<'EOF'
== bootstrap done ==
Next: use the installer (./bin/install -> Remoto) which rsyncs the repo, ships the
.env, and runs `docker compose up`. Or do it manually:
  1. scp deploy/<group>/.env -> /opt/devtools/deploy/<group>/.env  (DATA_ROOT=/data), chmod 600
  2. docker login ghcr.io -u <GHCR_USER> -p <GHCR_TOKEN>   (dev/support: fork images)
  3. docker compose -f deploy/<group>/docker-compose.yml up -d
EOF
