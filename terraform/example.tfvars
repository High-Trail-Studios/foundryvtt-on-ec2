# Copy to terraform.tfvars and fill in. terraform.tfvars is gitignored.

# --- required ---------------------------------------------------------------

# Must sit inside route53_zone_id. See REQUIREMENTS.md R1 — delegating a
# subdomain is safer than moving a whole domain's DNS to Route 53.
domain_name     = "vtt.example.com"
route53_zone_id = "Z0123456789ABCDEFGHIJ"

acme_email  = "you@example.com"
alert_email = "you@example.com"

# --- common overrides -------------------------------------------------------

aws_region      = "us-east-1"
foundry_version = "14.364"

# t4g.medium is the default. c7g.large costs ~2x for non-burstable CPU —
# worth it only for a large table with heavy modules.
# instance_type = "c7g.large"

# Billed 24/7 whether or not you play. Size to your assets, not your hopes.
# data_volume_size = 30

# --- bring your own network -------------------------------------------------

# Leave empty to create a dedicated VPC. If you supply a subnet it MUST be
# public: there is deliberately no NAT gateway.
# vpc_id    = "vpc-0123456789abcdef0"
# subnet_id = "subnet-0123456789abcdef0"

# --- teardown ---------------------------------------------------------------

# Leave false until you have verified you no longer need the backups.
# s3_force_destroy = true
# ecr_force_delete = true
