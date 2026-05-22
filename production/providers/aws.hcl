locals {
  required_providers = {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  provider_block = <<-PROVIDER
provider "aws" {
  region = "ap-southeast-2"
  default_tags {
    tags = {
      CreatedBy   = "terraform"
      Environment = var.environment
      Account     = var.account
      Repo        = var.repo
      Application = var.application
      Folder      = var.folder
      Project     = var.project
    }
  }
}

data "aws_caller_identity" "current" {
}
PROVIDER
}
