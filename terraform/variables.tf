# ---------------------------------------------------------------------------
# Required
# ---------------------------------------------------------------------------

variable "domain_name" {
  description = "Fully-qualified hostname for Foundry, e.g. vtt.example.com. Must sit inside route53_zone_id. See REQUIREMENTS.md R1."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a fully-qualified hostname, e.g. vtt.example.com."
  }
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID containing domain_name. The instance updates its own A record on boot, so this zone must be in the same AWS account."
  type        = string
}

variable "acme_email" {
  description = "Email for Let's Encrypt expiry and problem notices."
  type        = string
}

variable "alert_email" {
  description = "Email for budget and billing alarms."
  type        = string
}

# ---------------------------------------------------------------------------
# Networking — VPC is optional. Leave vpc_id empty to have one created.
# ---------------------------------------------------------------------------

variable "vpc_id" {
  description = "Existing VPC to deploy into. Leave empty to create a dedicated one."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Existing PUBLIC subnet to deploy into. Leave empty to create one. Must be public — there is deliberately no NAT gateway, and the instance needs outbound access to ECR, S3 and Let's Encrypt."
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR for the created VPC. Ignored when vpc_id is set."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR for the created public subnet. Ignored when subnet_id is set."
  type        = string
  default     = "10.20.1.0/24"
}

variable "availability_zone" {
  description = "AZ to pin the instance and data volume to. Leave empty to pick the first available. Changing this after creation strands the data volume."
  type        = string
  default     = ""
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach 80/443. Defaults to the internet because players need to connect. Narrow it only if every player has a fixed address."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Compute and storage
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "Graviton instance type. t4g.medium (2 vCPU / 4GB) is the default; c7g.large costs roughly 2x for consistent, non-burstable CPU."
  type        = string
  default     = "t4g.medium"
}

variable "root_volume_size" {
  description = "Root volume GB. Needs headroom for Docker plus the image build (REQUIREMENTS.md R13) — 20GB is the practical floor. Billed whether or not the instance is running."
  type        = number
  default     = 20
}

variable "data_volume_size" {
  description = "Persistent Foundry data volume GB. Holds worlds, assets and Caddy's certificates. Billed 24/7 and usually the largest line item."
  type        = number
  default     = 30
}

variable "foundry_version" {
  description = "Foundry version to run, e.g. 14.364. The matching FoundryVTT-Linux-<version>.zip must be uploaded to s3://<bucket>/dist/ before first start."
  type        = string
  default     = "14.364"

  validation {
    condition     = can(regex("^14\\.", var.foundry_version))
    error_message = "This release supports Foundry v14 only (REQUIREMENTS.md R11)."
  }
}

# ---------------------------------------------------------------------------
# Cost guardrails
# ---------------------------------------------------------------------------

variable "budget_limit_usd" {
  description = "Monthly budget threshold in USD. Alerts only — AWS budgets do not cap spend."
  type        = number
  default     = 15
}

variable "enable_auto_stop" {
  description = "Stop the instance on a schedule as a backstop against leaving it running. Forgetting costs roughly 60x the intended monthly bill."
  type        = bool
  default     = true
}

variable "auto_stop_cron" {
  description = "When to force-stop the instance, in EventBridge cron syntax (UTC). Default is 08:00 UTC daily."
  type        = string
  default     = "cron(0 8 * * ? *)"
}

# ---------------------------------------------------------------------------
# Teardown — see REQUIREMENTS.md R15
# ---------------------------------------------------------------------------

variable "s3_force_destroy" {
  description = "Allow terraform destroy to delete a non-empty backup bucket. Leave false until you have verified you no longer need the backups."
  type        = bool
  default     = false
}

variable "ecr_force_delete" {
  description = "Allow terraform destroy to delete the ECR repository with images still in it."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "Region to deploy into. Must offer Graviton instance types (REQUIREMENTS.md R4)."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for resource names and tags."
  type        = string
  default     = "foundry"
}

variable "tags" {
  description = "Extra tags applied to everything."
  type        = map(string)
  default     = {}
}
