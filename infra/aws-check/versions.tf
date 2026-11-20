terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state in the OpsAgent state bucket of the AWS Check account.
  backend "s3" {
    bucket       = "opsagent-tf-state-12bbcef4"
    key          = "calc/aws-check/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "calc"
      ManagedBy = "opsagent-terraform"
      Repo      = "zacknaviteq/calc"
    }
  }
}
