# Vultr host for one deployment group. N2 posture: firewall opens only 22 (owner
# IP), 80, 443. Docker/dirs come from the installer over SSH (bootstrap-host.sh).
# API key is read from the VULTR_API_KEY environment variable.
provider "vultr" {}

data "vultr_os" "ubuntu" {
  filter {
    name   = "name"
    values = [var.os_name]
  }
}

resource "vultr_ssh_key" "this" {
  name    = "${var.name}-key"
  ssh_key = var.public_key
}

resource "vultr_firewall_group" "this" {
  description = "${var.name} N2: ssh(owner), http, https"
}

resource "vultr_firewall_rule" "ssh" {
  firewall_group_id = vultr_firewall_group.this.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = var.owner_ip
  subnet_size       = 32
  port              = "22"
}

resource "vultr_firewall_rule" "http" {
  firewall_group_id = vultr_firewall_group.this.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "80"
}

resource "vultr_firewall_rule" "https" {
  firewall_group_id = vultr_firewall_group.this.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "443"
}

resource "vultr_instance" "this" {
  region            = var.region
  plan              = var.plan
  os_id             = data.vultr_os.ubuntu.id
  label             = var.name
  hostname          = var.name
  firewall_group_id = vultr_firewall_group.this.id
  ssh_key_ids       = [vultr_ssh_key.this.id]
  enable_ipv6       = false
}
