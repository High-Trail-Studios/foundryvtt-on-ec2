terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pinned to a major line. Bump deliberately after testing, not by drift.
      version = "~> 5.0"
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
