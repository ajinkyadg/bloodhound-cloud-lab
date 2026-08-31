data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  docker_compose_rendered = templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
    bloodhound_port = var.bloodhound_port
  })

  caddyfile_rendered = templatefile("${path.module}/templates/Caddyfile.tftpl", {
    bloodhound_port = var.bloodhound_port
  })

  user_data_rendered = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    docker_compose_yml = local.docker_compose_rendered
    caddyfile          = local.caddyfile_rendered
  })
}

resource "aws_instance" "bloodhound" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bloodhound.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name
  user_data              = local.user_data_rendered
  # Only affects re-creation, not stop/start: keep the instance if user-data drifts,
  # so a plan doesn't accidentally propose destroying (and thus re-formatting) the box.
  user_data_replace_on_change = false

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  tags = { Name = "${var.project_name}-instance" }
}

# Neo4j + Postgres data lives here. Survives instance stop/start automatically.
# Deliberately destroyable by `terraform destroy` - run scripts/final-export.sh first.
resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${var.project_name}-data" }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.bloodhound.id
}
