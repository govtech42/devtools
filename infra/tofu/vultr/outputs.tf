output "public_ip" {
  value = vultr_instance.this.main_ip
}

output "ssh_user" {
  value = "root"
}

output "instance_id" {
  value = vultr_instance.this.id
}
