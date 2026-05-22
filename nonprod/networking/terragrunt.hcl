include "backend" {
  path = find_in_parent_folders("backend.hcl")
}

include "environment" {
  path   = find_in_parent_folders("environment.hcl")
  expose = true
}

locals {
  _profiles = {
    for p in ["aws"] :
    p => read_terragrunt_config("${get_terragrunt_dir()}/../providers/${p}.hcl").locals
  }

  all_required_providers = merge([for _, p in local._profiles : p.required_providers]...)
  all_provider_blocks    = join("\n", [for _, p in local._profiles : p.provider_block])
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
terraform {
  required_version = "${include.environment.locals.terraform_version}"
  required_providers {
%{for name, provider in local.all_required_providers~}
    ${name} = {
      source  = "${provider.source}"
      version = "${provider.version}"
    }
%{endfor~}
  }
}

${local.all_provider_blocks}
EOF
}

inputs = {
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  availability_zones   = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
  enable_nat_gateway   = true
}
