#!/usr/bin/env bash
# DANGER: deletes the Lightsail instance + static IP. NO BACKUPS EXIST.
# The data disk is detached but KEPT (delete it manually if you really mean to).
set -euo pipefail
REGION="${REGION:-us-east-1}"
NAME="${NAME:-devtools}"
DISK_NAME="${DISK_NAME:-devtools-data}"

echo "This DELETES the Lightsail instance '$NAME' and its static IP."
echo "The data disk '$DISK_NAME' is detached but NOT deleted. NO BACKUPS EXIST."
read -r -p "Type the instance name to confirm: " CONFIRM
[ "$CONFIRM" = "$NAME" ] || { echo "aborted"; exit 1; }

aws lightsail detach-disk --disk-name "$DISK_NAME" --region "$REGION" || true
aws lightsail delete-instance --instance-name "$NAME" --region "$REGION"
aws lightsail release-static-ip --static-ip-name "${NAME}-ip" --region "$REGION" || true
echo "Instance gone. Disk '$DISK_NAME' kept (reattach to a new instance to recover data)."
