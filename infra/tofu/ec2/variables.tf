variable "name" {
  type        = string
  description = "Instance + resource name prefix (e.g. devtools-monitoring)."
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.large" # 8 GB; dev = t3.xlarge (16 GB), monitoring = t3.small (2 GB)
}

variable "root_volume_gb" {
  type    = number
  default = 80 # /data is a directory on the root volume (v1 — no separate pet disk)
}

variable "owner_ip" {
  type        = string
  description = "Operator public IP allowed to SSH (no CIDR suffix; /32 is added)."
}

variable "public_key" {
  type        = string
  description = "SSH public key contents for the instance key pair."
}

variable "ssh_key_name" {
  type    = string
  default = "devtools-tofu"
}
