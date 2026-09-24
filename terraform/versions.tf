terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pinned to the tested release; patch updates only. Bump deliberately
      # after testing, not by drift. The pin lives here rather than only in
      # .terraform.lock.hcl because the lock file is registry-specific: its
      # OpenTofu entries mean nothing to HashiCorp Terraform.
      version = "~> 5.100.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project   = var.name_prefix
        ManagedBy = "terraform"
      },
      var.tags,
    )
  }
}

# CloudWatch billing metrics only exist in us-east-1, regardless of where the
# rest of the stack lives. This alias exists solely for the billing alarm.
provider "aws" {
  alias  = "billing"
  region = "us-east-1"

  default_tags {
    tags = merge(
      {
        Project   = var.name_prefix
        ManagedBy = "terraform"
      },
      var.tags,
    )
  }
}
