variable "name" {
  type        = string
  description = "Instance label + resource name prefix (e.g. devtools-monitoring)."
}

variable "region" {
  type    = string
  default = "ewr" # New Jersey
}

variable "plan" {
  type    = string
  default = "vc2-4c-8gb" # 8 GB; dev = vc2-6c-16gb, monitoring = vc2-1c-2gb
}

variable "owner_ip" {
  type        = string
  description = "Operator public IP allowed to SSH (no CIDR suffix; /32 is added)."
}

variable "public_key" {
  type        = string
  description = "SSH public key contents."
}

variable "os_name" {
  type    = string
  default = "Ubuntu 24.04 LTS x64"
}
