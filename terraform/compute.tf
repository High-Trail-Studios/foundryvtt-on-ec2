# The instance.
#
# Disposable by design: it can be destroyed and rebuilt, and the data volume
# and S3 backups carry everything that matters. Created STOPPED — the image
# does not exist in ECR yet at apply time, and nothing should bill before the
# adopter is ready.

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "foundry" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  availability_zone      = local.availability_zone

  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  lifecycle {
    # A newer Ubuntu AMI should not silently replace a running instance.
    # Rebuilds are cheap here, but they should be deliberate.
    ignore_changes = [ami]
  }

  # The instance launches running and immediately reads its configuration from
  # S3. Without this, Terraform is free to create it before those objects
  # exist and the first boot fails for no good reason.
  depends_on = [
    aws_s3_object.boot,
    aws_s3_object.backup,
    aws_s3_object.env,
    aws_s3_object.dockerfile,
    aws_s3_object.compose,
    aws_s3_object.caddyfile,
  ]

  tags = { Name = var.name_prefix }
}

# Terraform cannot create an instance in a stopped state, so this stops it
# immediately after launch. ignore_changes makes that a create-time action
# only: starting the instance for a session does not show up as drift, and a
# later `terraform apply` will not shut down a live game.
resource "aws_ec2_instance_state" "foundry" {
  instance_id = aws_instance.foundry.id
  state       = "stopped"

  lifecycle {
    ignore_changes = [state]
  }

  # Attach the data volume before stopping, otherwise the attachment races a
  # shutting-down instance.
  depends_on = [aws_volume_attachment.data]
}

locals {
  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    bucket          = aws_s3_bucket.data.id
    region          = var.aws_region
    boot_script_key = aws_s3_object.boot.key
  })
}
