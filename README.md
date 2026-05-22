# Terragrunt AWS Infrastructure Best Practices

A reference repository demonstrating production-ready patterns for managing multi-environment AWS infrastructure with Terragrunt. This repo captures hard-won lessons from migrating real-world Terraform repositories to Terragrunt, focusing on the **why** behind each design decision.

## Table of Contents

- [Why Terragrunt?](#why-terragrunt)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Design Decisions](#design-decisions)
- [Getting Started](#getting-started)
- [CI/CD](#cicd)
- [Customising for Your Project](#customising-for-your-project)

## Why Terragrunt?

Terragrunt adds two capabilities that plain Terraform lacks at scale:

### 1. Dependency Linking Between Components

Infrastructure naturally has dependencies — a database needs a VPC, an application needs a database. In plain Terraform, these dependencies are either managed manually (run components in the right order) or collapsed into a single monolithic state (everything in one `terraform apply`).

Terragrunt makes dependencies explicit:

```hcl
dependencies {
  paths = ["../networking"]
}
```

Running `terragrunt run-all apply` plans and applies components in the correct order automatically. No scripts, no manual coordination.

### 2. Generating Shared Configuration

Every Terraform component needs boilerplate: backend configuration, provider blocks, common variables. In a multi-environment setup, this boilerplate is repeated across every component in every environment.

Terragrunt generates these files at plan/apply time from a single source:

- **`backend.hcl`** generates `backend.tf` — S3 state configuration with the correct bucket and key
- **`environment.hcl`** generates `common_vars.tf` — shared variables like account, environment, region
- **Provider profiles** generate `providers.tf` — provider blocks with correct versions and default tags

This eliminates configuration drift without eliminating the `.tf` files themselves.

### What Terragrunt Does NOT Do Here

Terragrunt is **not** used to eliminate code duplication across environments. Each environment (nonprod, production) has its own copy of the `.tf` files. This is intentional — it gives developers the flexibility to make changes in lower environments, test with confidence, and promote to production when ready. If a networking change needs testing, you modify `nonprod/networking/*.tf`, verify it works, then apply the same change to `production/networking/*.tf`. The environment boundary is explicit and safe.

## Architecture

### Component Dependency Graph

```
   networking ──────► database
   (VPC, Subnets,     (RDS PostgreSQL)
    NAT Gateway)
```

Components are deployed in dependency order. Terragrunt handles this automatically — running `terragrunt run-all plan` from an environment directory will plan components in the correct sequence.

### Environment Isolation

Each environment maps to a separate AWS account:

| Environment | AWS Account | Purpose |
|---|---|---|
| `nonprod` | Staging (non-prod) | Pre-production testing and validation |
| `production` | Production | Live workloads |

## Repository Structure

```
.
├── README.md
├── .gitignore
├── .tool-versions                  # Pinned terraform + terragrunt versions
├── nonprod/                        # Staging environment
│   ├── backend.hcl                 # S3 remote state config (generates backend.tf)
│   ├── environment.hcl             # Common variables (generates common_vars.tf)
│   ├── providers/                  # Modular provider profiles
│   │   └── aws.hcl                 # AWS provider + default tags (generates providers.tf)
│   ├── networking/                 # Network layer
│   │   ├── terragrunt.hcl
│   │   ├── vpc.tf
│   │   ├── subnets.tf
│   │   ├── nat.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── database/                   # Data stores
│       ├── terragrunt.hcl
│       ├── rds.tf
│       ├── variables.tf
│       └── outputs.tf
├── production/                     # Production environment (own copy of .tf files)
│   └── ...                         # Same structure, production-sized values
└── .github/workflows/
    ├── pr.yml                      # Terragrunt plan on pull request
    ├── apply.yml                   # Terragrunt apply on merge to main
    ├── run_terragrunt.yaml         # Reusable workflow for plan/apply
    └── format.yml                  # Terraform and Terragrunt format check
```

### What Gets Committed vs Generated

| File | Committed? | Source |
|---|---|---|
| `*.tf` (resource definitions) | Yes | Hand-written per environment |
| `terragrunt.hcl` (component config) | Yes | Hand-written per component |
| `backend.hcl`, `environment.hcl` | Yes | Hand-written per environment |
| `providers/*.hcl` | Yes | Hand-written per environment |
| `backend.tf` | No | Generated from `backend.hcl` |
| `providers.tf` | No | Generated from provider profiles |
| `common_vars.tf` | No | Generated from `environment.hcl` |

Generated files are in `.gitignore`. They are created fresh on every `terragrunt init`/`plan`/`apply`, ensuring they always match the current configuration.

## Design Decisions

### Why Environment Directories, Not Workspaces?

Terraform workspaces were designed for temporary, short-lived environments (e.g., feature branches), not long-lived staging/production splits.

**Problems with workspaces for permanent environments:**

1. **Shared backend**: Workspaces share the same S3 bucket configuration. If staging and production are in different AWS accounts (they should be for security isolation), workspaces cannot point at different backends.
2. **Invisible context**: The active workspace is not visible in the code. A developer running `terraform apply` might not realise they are targeting production. With directories, the file path makes the target explicit — you are always aware which environment you are operating in.
3. **Ternary sprawl**: Production needs different instance sizes, replica counts, and retention policies. With workspaces, this becomes `terraform.workspace == "prod" ? "db.r6g.xlarge" : "db.t4g.micro"` scattered throughout the code. With directories, each environment has its own inputs — clean and auditable.

### Why Code is Duplicated Across Environments

Each environment has its own copy of the `.tf` files. This looks like duplication, but it is a deliberate design choice:

- **Safe experimentation**: A developer can modify `nonprod/networking/vpc.tf` to test a CIDR change without any risk to production. The files are independent.
- **Environment-specific divergence**: Production might need resources that staging does not (e.g., cross-region replicas, WAF rules). With shared code, this requires conditional logic. With separate files, you simply add the resource where it is needed.
- **Confident deployments**: When you deploy to production, you are deploying exactly the code in `production/` — not shared code filtered through workspace conditionals. What you see is what gets applied.
- **Independent review**: A PR changing staging infrastructure is clearly scoped. Reviewers know exactly what is being changed and where.

The shared configuration (backend, providers, common variables) is still DRY via Terragrunt generation. The infrastructure definitions themselves are intentionally per-environment.

### Why Modular Provider Profiles?

Provider configuration lives in `providers/*.hcl` files rather than being defined directly in each component:

```
providers/
├── aws.hcl        # AWS provider + default tags
├── helm.hcl       # Helm provider (if needed)
└── datadog.hcl    # Datadog provider (if needed)
```

Each component selects which providers it needs:

```hcl
locals {
  _profiles = {
    for p in ["aws"] :
    p => read_terragrunt_config("${get_terragrunt_dir()}/../providers/${p}.hcl").locals
  }
}
```

**Why?**

- **Single source of truth per environment**: Provider version and configuration defined once. When upgrading the AWS provider from v5 to v6, you change one file per environment — not every component.
- **Selective inclusion**: A networking component needs only the AWS provider. An application component might need AWS + Helm. Each component declares exactly what it uses, keeping the generated `providers.tf` minimal.
- **Consistent tagging**: Default tags are set in the AWS provider profile. Every resource created in that environment is automatically tagged without developers needing to remember `tags = local.common_tags`.

### Why Per-Component State Files?

Each component has its own Terraform state file:

```
my-app-infra/networking/terraform.tfstate
my-app-infra/database/terraform.tfstate
```

**Why not one state file per environment?**

- **Blast radius**: A corrupted or locked state file affects one component, not the entire environment.
- **Concurrency**: Team members can work on different components simultaneously without state lock contention.
- **Plan speed**: `terraform plan` only evaluates resources in the targeted component. For large environments with hundreds of resources, this saves significant time.
- **Lifecycle alignment**: Networking rarely changes after initial setup. Database schemas evolve independently. Separate state reflects these different change frequencies.

### Why Explicit Dependencies Over Implicit Data Sources?

Components declare dependencies using Terragrunt `dependencies` blocks:

```hcl
dependencies {
  paths = ["../networking"]
}
```

**Why not rely solely on Terraform data sources?**

- **Ordering guarantee**: `terragrunt run-all apply` respects the dependency graph. Without explicit dependencies, Terragrunt would attempt to create a database before the VPC exists.
- **Fail-fast**: If a dependency has not been applied, Terragrunt fails with a clear message rather than a cryptic data source timeout.
- **Readable dependency graph**: The dependencies are visible in the `terragrunt.hcl` file. A new team member can understand the deployment order without tracing data source references across files.

## Getting Started

### Prerequisites

Install the required tools using [asdf](https://asdf-vm.com/):

```bash
asdf plugin add terraform
asdf plugin add terragrunt
asdf install    # Reads .tool-versions
```

Or install manually:

- [Terraform](https://developer.hashicorp.com/terraform/install) ~> 1.14.0
- [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/) >= 0.77.0
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

### Authenticate to AWS

```bash
aws sso login --profile <your-profile>
```

### Running Locally

```bash
# Navigate to the component you want to work on
cd nonprod/networking

# Initialise (downloads providers, generates backend/provider/common_vars files)
terragrunt init

# Preview changes
terragrunt plan

# Apply changes
terragrunt apply
```

### Running All Components in an Environment

```bash
cd nonprod
terragrunt run-all plan     # Plans all components in dependency order
terragrunt run-all apply    # Applies all components in dependency order
```

## CI/CD

### Pull Request — Plan

When a PR is opened, the workflow:

1. Detects which environments and components have changed files
2. Runs `terragrunt plan` for each affected component
3. Posts the plan output as a PR comment

Every infrastructure change is reviewed before it is applied. No surprises at merge time.

### Merge to Main — Apply

When a PR is merged:

1. Detects changed components
2. Applies staging first
3. Production requires manual approval before applying

**Why apply-on-merge?**

- **Auditability**: Every change is tied to a reviewed and approved PR
- **No drift**: The repo is always the source of truth for what is deployed
- **Confidence**: The plan was already reviewed in the PR — the apply executes the same change

## Customising for Your Project

To use this as a starting point:

1. Update `backend.hcl` in each environment with your S3 bucket and region
2. Update `environment.hcl` with your application name, repo name, and account
3. Replace the example components with your actual infrastructure
4. Update CI/CD workflows with your runner configuration and approval process

## Licence

MIT
