# infra/tofu/ — OpenTofu provisioners (EC2, Vultr)

Multi-provider provisioning for the installer's **Remoto** flow. The Lightsail path
stays on the AWS-CLI script (`infra/scripts/create-lightsail.sh`); OpenTofu is used
**only** for EC2 and Vultr (see `DECISIONS.md` → "Provisioning & installer").

Each module creates **one host for one deployment group** and keeps the **N2** posture:
the firewall/SG opens only **22 (operator IP), 80, 443**. Docker, swap, `/data` dirs,
and `/opt/devtools` are set up by `infra/scripts/bootstrap-host.sh` over SSH (run by
the installer), so the modules carry **no `user_data`**.

> **v1 simplification:** `/data` is a directory on an enlarged **root volume** (no
> separate "pet" disk). This avoids the nitro device-naming gotcha; a dedicated data
> volume is a future enhancement.

## Layout

```
ec2/    aws_instance + security group + EIP   (AMI: Ubuntu 24.04; user: ubuntu)
vultr/  vultr_instance + firewall group       (OS: Ubuntu 24.04; user: root)
```

Outputs (both): `public_ip`, `ssh_user`, `instance_id`.

## Credentials

- **EC2:** standard AWS env / `aws configure` (the AWS provider reads them).
- **Vultr:** `VULTR_API_KEY` in the environment (the installer prompts if unset).

## Usage

Normally you don't run these by hand — `./bin/install` → **Remoto** → **EC2/Vultr**
calls `tofu init/apply`, reads `public_ip`, and deploys. The installer generates and
reuses one SSH keypair at `infra/scripts/devtools-tofu` (gitignored).

Manual:

```bash
tofu -chdir=infra/tofu/ec2 init
tofu -chdir=infra/tofu/ec2 apply \
  -var name=devtools-monitoring -var instance_type=t3.small \
  -var owner_ip=$(curl -fsS https://checkip.amazonaws.com) \
  -var public_key="$(cat infra/scripts/devtools-tofu.pub)"
tofu -chdir=infra/tofu/ec2 output -json
```

State is **local** (gitignored: `*.tfstate*`, `.terraform/`). Teardown: `tofu
-chdir=infra/tofu/<p> destroy` — **DANGER, no backups** (same as the Lightsail teardown).
