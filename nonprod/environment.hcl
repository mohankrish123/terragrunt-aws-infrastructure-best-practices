locals {
  terraform_version = "~> 1.14.0"
}

generate "common_vars" {
  path      = "common_vars.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
variable "account" {
  description = "The AWS account name"
  type        = string
  default     = "nonprod"
}

variable "repo" {
  description = "The name of the repository"
  type        = string
  default     = "my-app-infra"
}

variable "environment" {
  description = "The deployment environment"
  type        = string
  default     = "nonprod"
}

variable "application" {
  description = "The name of the application"
  type        = string
  default     = "my-app"
}

variable "folder" {
  description = "The folder name"
  type        = string
  default     = "${path_relative_to_include()}"
}

variable "project" {
  description = "The project name"
  type        = string
  default     = "infra"
}

variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "ap-southeast-2"
}
EOF
}

inputs = {
  account     = "nonprod"
  environment = "nonprod"
}
