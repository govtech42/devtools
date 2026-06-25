#!/usr/bin/env bash
# Provision the Lightsail host for a deployment group (default: dev / 16 GB).
# Requires AWS CLI v2 configured (`aws configure`).
set -euo pipefail

REGION="${REGION:-us-east-1}"
AZ="${AZ:-us-east-1a}"
NAME="${NAME:-devtools}"
BUNDLE="${BUNDLE:-xlarge_2_0}"          # 16 GB / 4 vCPU (Dev group); support = large_2_0
BLUEPRINT="${BLUEPRINT:-ubuntu_24_04}"  # confirm: aws lightsail get-blueprints
DISK_NAME="${DISK_NAME:-devtools-data}"
DISK_SIZE_GB="${DISK_SIZE_GB:-80}"
KEY_PAIR="${KEY_PAIR:-devtools-key}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OWNER_IP="$(curl -fsS https://checkip.amazonaws.com)"
echo "Owner IP for SSH allowlist: $OWNER_IP"

# key pair (saved locally; gitignored)
if ! aws lightsail get-key-pair --key-pair-name "$KEY_PAIR" --region "$REGION" >/dev/null 2>&1; then
  aws lightsail create-key-pair --key-pair-name "$KEY_PAIR" --region "$REGION" \
    --query 'privateKeyBase64' --output text > "$HERE/${KEY_PAIR}.pem"
  chmod 600 "$HERE/${KEY_PAIR}.pem"
else
  echo "key pair $KEY_PAIR already exists; reusing"
fi

aws lightsail create-instances --region "$REGION" \
  --instance-names "$NAME" \
  --availability-zone "$AZ" \
  --blueprint-id "$BLUEPRINT" \
  --bundle-id "$BUNDLE" \
  --key-pair-name "$KEY_PAIR" \
  --user-data "file://$HERE/user-data.sh"

echo "waiting for instance to run..."
until [ "$(aws lightsail get-instance-state --instance-name "$NAME" --region "$REGION" \
  --query 'state.name' --output text 2>/dev/null)" = "running" ]; do sleep 5; done

# static IP
aws lightsail allocate-static-ip --static-ip-name "${NAME}-ip" --region "$REGION" >/dev/null 2>&1 || true
aws lightsail attach-static-ip --static-ip-name "${NAME}-ip" --instance-name "$NAME" --region "$REGION"

# block disk
aws lightsail create-disk --disk-name "$DISK_NAME" --availability-zone "$AZ" \
  --size-in-gb "$DISK_SIZE_GB" --region "$REGION" >/dev/null 2>&1 || true
until [ "$(aws lightsail get-disk --disk-name "$DISK_NAME" --region "$REGION" \
  --query 'disk.state' --output text 2>/dev/null)" = "available" ]; do sleep 5; done
aws lightsail attach-disk --disk-name "$DISK_NAME" --disk-path /dev/xvdf \
  --instance-name "$NAME" --region "$REGION"

# firewall: substitute owner IP, apply
sed "s#OWNER_IP#${OWNER_IP}#" "$HERE/../firewall.json" > /tmp/fw.json
aws lightsail put-instance-public-ports --instance-name "$NAME" --region "$REGION" \
  --port-infos "file:///tmp/fw.json"

IP="$(aws lightsail get-static-ip --static-ip-name "${NAME}-ip" --region "$REGION" \
  --query 'staticIp.ipAddress' --output text)"
echo "== Lightsail ready =="
echo "Static IP: $IP"
echo "DNS: point git/chat/plane.code42.dev -> $IP"
echo "SSH: ssh -i $HERE/${KEY_PAIR}.pem ubuntu@$IP"
