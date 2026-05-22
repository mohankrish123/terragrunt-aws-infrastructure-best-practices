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

dependencies {
  paths = ["../networking"]
}

inputs = {
  db_engine            = "postgres"
  db_engine_version    = "17.4"
  db_instance_class    = "db.t4g.micro"
  db_allocated_storage = 20
  db_storage_type      = "gp3"
  enable_multi_az      = false

  db_backup_retention_period = 7
  db_maintenance_window      = "sat:19:30-sat:20:00"
  db_backup_window           = "20:30-21:00"

  db_parameters = [
    {
      name  = "log_connections"
      value = "1"
    },
    {
      name  = "log_disconnections"
      value = "1"
    },
    {
      name         = "shared_preload_libraries"
      value        = "pg_stat_statements,pgaudit"
      apply_method = "pending-reboot"
    },
    {
      name  = "pgaudit.log"
      value = "all"
    },
  ]
}
