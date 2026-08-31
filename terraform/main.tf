provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project   = var.project_name
    Purpose   = "temporary-exam-lab"
    ManagedBy = "terraform"
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
