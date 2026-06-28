# EC2 host for one deployment group. N2 posture: SG opens only 22 (owner IP),
# 80, 443. Docker/dirs are installed by the installer over SSH (bootstrap-host.sh),
# so no user_data here. /data lives on the (enlarged) root volume in v1.
provider "aws" {
  region = var.region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = var.ssh_key_name
  public_key = var.public_key
}

resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "devtools N2: ssh(owner), http, https"

  ingress {
    description = "ssh (owner only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.owner_ip}/32"]
  }

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "https"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sg"
  }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.this.key_name
  vpc_security_group_ids = [aws_security_group.this.id]

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
  }

  tags = {
    Name = var.name
  }
}

# Stable address (survives stop/start), mirroring the Lightsail static IP.
resource "aws_eip" "this" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-ip"
  }
}

resource "aws_eip_association" "this" {
  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this.id
}
