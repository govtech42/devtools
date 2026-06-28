output "public_ip" {
  value = aws_eip.this.public_ip
}

output "ssh_user" {
  value = "ubuntu"
}

output "instance_id" {
  value = aws_instance.this.id
}
