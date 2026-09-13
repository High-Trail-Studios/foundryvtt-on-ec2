# Instance role.
#
# Least privilege, documented explicitly — per org policy the IAM policy is
# part of the product, not an afterthought. See REQUIREMENTS.md R6.

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "instance" {
  name_prefix = "${var.name_prefix}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.name_prefix}-"
  role        = aws_iam_role.instance.name
}

# Shell access without an open port 22 or key management (R8).
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "instance" {
  name_prefix = "${var.name_prefix}-"
  role        = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken cannot be scoped to a repository — AWS
        # requires "*" for this action specifically.
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        # Pull AND push, scoped to the one repository. Push is required
        # because the instance builds its own image (R13). Accepted tradeoff:
        # a compromised instance could poison its own image. Moving the build
        # to CodeBuild would return this to pull-only.
        Sid    = "EcrRepository"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = aws_ecr_repository.foundry.arn
      },
      {
        Sid      = "S3List"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.data.arn
      },
      {
        Sid    = "S3Objects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.data.arn}/*"
      },
      {
        # The instance owns its own A record. No Elastic IP means the public
        # address changes on every start, so the boot script UPSERTs the
        # record before Caddy requests a certificate.
        Sid      = "Route53UpdateOwnRecord"
        Effect   = "Allow"
        Action   = "route53:ChangeResourceRecordSets"
        Resource = "arn:aws:route53:::hostedzone/${var.route53_zone_id}"
      },
      {
        # Required to poll until a record change has propagated. Cannot be
        # scoped — Route 53 change IDs are not resource-addressable.
        Sid      = "Route53PollChange"
        Effect   = "Allow"
        Action   = "route53:GetChange"
        Resource = "*"
      },
    ]
  })
}
