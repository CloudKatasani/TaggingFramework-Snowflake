# =============================================================================
# Production deployment of the enterprise tagging framework.
# -----------------------------------------------------------------------------
# Tag definitions arrive from tags.auto.tfvars.json, generated from
# config/tag_catalog.yaml. Terraform never needs editing to add a tag.
#
# Authentication: key-pair, via environment variables. Never commit a private
# key or place credentials in a .tfvars file.
#   SNOWFLAKE_ORGANIZATION_NAME, SNOWFLAKE_ACCOUNT_NAME,
#   SNOWFLAKE_USER, SNOWFLAKE_PRIVATE_KEY, SNOWFLAKE_ROLE=ACCOUNTADMIN
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }

  # Configure your own remote state backend before first apply. Local state for
  # an account-level governance deployment is a single point of failure.
  # backend "s3" { ... }
}

provider "snowflake" {
  # Credentials come from the environment; see the header.
  preview_features_enabled = ["snowflake_tag_association_resource"]
}

module "tag_framework" {
  source = "../../modules/snowflake_tag_framework"

  governance_database = var.governance_database
  tag_schema          = var.tag_schema
  policy_schema       = var.policy_schema
  warehouse           = var.warehouse
  catalog_version     = var.catalog_version
  tags                = var.tags

  environment                = "PRD"
  platform_operating_company = "SHARED"
  platform_department        = "CORPORATE"
  platform_team              = "team-data-governance"
  platform_application       = "app-tag-governance"
}

output "tier1_tags" {
  description = "Tier 1 tag names, consumed by the deployment gate."
  value       = module.tag_framework.tier1_tags
}
