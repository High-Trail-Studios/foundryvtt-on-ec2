# Runtime configuration delivered via S3.
#
# The boot script, the Docker build context and the compose stack live in the
# bucket rather than baked into user-data. Three reasons: user-data is capped
# at 16KB, Terraform templating and bash both use ${...} so embedding shell in
# a template is error-prone, and this way config can be corrected without
# replacing the instance.
#
# etag on file content means a changed file is re-uploaded on apply.

resource "aws_s3_object" "boot" {
  bucket = aws_s3_bucket.data.id
  key    = "config/boot.sh"
  source = "${path.module}/scripts/boot.sh"
  etag   = filemd5("${path.module}/scripts/boot.sh")
}

resource "aws_s3_object" "backup" {
  bucket = aws_s3_bucket.data.id
  key    = "config/backup.sh"
  source = "${path.module}/scripts/backup.sh"
  etag   = filemd5("${path.module}/scripts/backup.sh")
}

resource "aws_s3_object" "dns_park" {
  bucket = aws_s3_bucket.data.id
  key    = "config/dns-park.sh"
  source = "${path.module}/scripts/dns-park.sh"
  etag   = filemd5("${path.module}/scripts/dns-park.sh")
}

resource "aws_s3_object" "dockerfile" {
  bucket = aws_s3_bucket.data.id
  key    = "config/Dockerfile"
  source = "${path.module}/../docker/Dockerfile"
  etag   = filemd5("${path.module}/../docker/Dockerfile")
}

resource "aws_s3_object" "compose" {
  bucket = aws_s3_bucket.data.id
  key    = "config/docker-compose.yml"
  source = "${path.module}/../docker/docker-compose.yml"
  etag   = filemd5("${path.module}/../docker/docker-compose.yml")
}

resource "aws_s3_object" "caddyfile" {
  bucket = aws_s3_bucket.data.id
  key    = "config/Caddyfile"
  source = "${path.module}/../docker/Caddyfile"
  etag   = filemd5("${path.module}/../docker/Caddyfile")
}

# Values the boot script needs. Written as a shell-sourceable env file.
resource "aws_s3_object" "env" {
  bucket = aws_s3_bucket.data.id
  key    = "config/foundry.env"

  content = <<-ENV
    AWS_REGION=${var.aws_region}
    S3_BUCKET=${aws_s3_bucket.data.id}
    ECR_REPO=${aws_ecr_repository.foundry.repository_url}
    FOUNDRY_VERSION=${var.foundry_version}
    FOUNDRY_DOMAIN=${var.domain_name}
    ACME_EMAIL=${var.acme_email}
    ROUTE53_ZONE_ID=${var.route53_zone_id}
    DNS_TTL=60
    DATA_VOLUME_ID=${aws_ebs_volume.data.id}
  ENV
}
