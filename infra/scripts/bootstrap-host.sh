#!/usr/bin/env bash
# Idempotent host bootstrap — installs Docker, swap, data dirs, and the app dir.
# Used two ways:
#   - piped over SSH by the installer for an *existing* host (`ssh ... bash -s`);
#   - sourced/duplicated by infra/scripts/user-data.sh on first boot of a fresh
#     Lightsail/EC2/Vultr instance (where the block disk is also mounted at /data).
# Safe to re-run. Assumes Ubuntu/Debian (apt). Uses sudo when not already root.
set -euo pipefail

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"
LOGIN_USER="$(id -un)"
APP_DIR="${APP_DIR:-/opt/devtools}"

echo "== docker =="
if ! command -v docker >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -y
  $SUDO apt-get install -y ca-certificates curl git gnupg rsync
  $SUDO install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
  $SUDO apt-get update -y
  $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
# let the login user run docker without sudo (effective on next login/session)
$SUDO usermod -aG docker "$LOGIN_USER" || true

echo "== 4GB swap =="
if [ ! -f /swapfile ]; then
  $SUDO fallocate -l 4G /swapfile
  $SUDO chmod 600 /swapfile
  $SUDO mkswap /swapfile
  $SUDO swapon /swapfile
  echo "/swapfile none swap sw 0 0" | $SUDO tee -a /etc/fstab >/dev/null
fi

echo "== data dirs under /data =="
# Group-agnostic: create every group's bind targets (harmless when unused).
$SUDO mkdir -p \
  /data/caddy/data /data/caddy/config /data/postgres /data/forgejo \
  /data/mattermost/data /data/mattermost/config \
  /data/plane/minio /data/plane/redis /data/plane/rabbitmq \
  /data/planka /data/chatwoot/storage /data/chatwoot/redis /data/minio \
  /data/twenty /data/twenty-docker-data /data/beszel
$SUDO chown -R "$LOGIN_USER":"$LOGIN_USER" /data || true

echo "== app dir =="
$SUDO mkdir -p "$APP_DIR"
$SUDO chown -R "$LOGIN_USER":"$LOGIN_USER" "$APP_DIR"

echo "== bootstrap done =="
