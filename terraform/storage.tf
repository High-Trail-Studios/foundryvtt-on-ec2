# Storage.
#
# Two tiers, deliberately split (see CLAUDE.md):
#   - EBS  : the live filesystem. Foundry v14 worlds are LevelDB and need a
#            block device. This volume outlives the instance.
#   - S3   : durable seed, backup, and the Foundry distribution zip.
#
# EFS was rejected on cost (~13x S3) and on NFS file-locking reliability with
# LevelDB.

# ---------------------------------------------------------------------------
# Persistent data volume
# ---------------------------------------------------------------------------

resource "aws_ebs_volume" "data" {
  availability_zone = local.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  # This holds the campaign. It is the one thing here that cannot be rebuilt
  # from code, so it has its own lifecycle and survives the instance being
  # destroyed and rebuilt.
  #
  # This also blocks `terraform destroy` by design. Clean teardown is a
  # deliberate two-stage path — see REQUIREMENTS.md R15.
  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.name_prefix}-data" }
}

resource "aws_volume_attachment" "data" {
  # Nitro instances expose this as an NVMe device, not /dev/sdf. The boot
  # script resolves the real device by matching the volume ID in the NVMe
  # serial rather than trusting this name.
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.foundry.id

  # Let the instance be replaced without a manual detach.
  stop_instance_before_detaching = true
}

# ---------------------------------------------------------------------------
# Bucket: distribution zip, backups, and runtime config
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "data" {
  bucket_prefix = "${var.name_prefix}-"
  force_destroy = var.s3_force_destroy
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  # Versioning is the backstop for a bad backup overwriting a good one.
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  # Versioning without expiry is a slow, silent bill. Old versions are a
  # safety net, not an archive.
  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.data]
}
