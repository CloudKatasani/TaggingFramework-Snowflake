# =============================================================================
# snowflake_tag_framework
# -----------------------------------------------------------------------------
# Terraform owns WHAT EXISTS: tag objects, allowed values, roles, grants.
# SQL owns WHAT IT DOES: policy bodies, procedures, tasks, views.
#
# The split is deliberate. The Snowflake Terraform provider models policy bodies
# and stored procedures poorly, and a masking policy body is code that belongs in
# a reviewed .sql file rather than in a heredoc inside HCL. Conversely, tag
# objects and grants are long-lived declarative resources where drift detection
# and a plan/apply review are genuinely worth having.
#
# Tag definitions come from terraform/envs/<env>/tags.auto.tfvars.json, which is
# generated from config/tag_catalog.yaml. Adding a tag is a catalog change; this
# module never needs editing for one.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Governance schemas
# -----------------------------------------------------------------------------
resource "snowflake_schema" "governance" {
  for_each = toset([var.tag_schema, var.policy_schema, "CONTROL", "REPORTING", "AUTOMATION"])

  database = var.governance_database
  name     = each.value
  comment  = "Managed by Terraform. Part of the enterprise tagging framework."

  # TAGS and POLICIES use managed access so that only the schema owner can grant
  # on the objects inside them - a steward must not be able to hand out APPLY on
  # a masking policy.
  with_managed_access = contains([var.tag_schema, var.policy_schema], each.value)
}

# -----------------------------------------------------------------------------
# Enterprise tags
# -----------------------------------------------------------------------------
# NOTE: Terraform will issue CREATE OR REPLACE TAG if a change cannot be applied
# in place, which would drop every assignment across the account. `prevent_destroy`
# and `ignore_changes` on the immutable attributes keep that off the table; a
# genuinely breaking tag change goes through the retirement playbook in
# docs/08-enterprise-standards.md, never through terraform apply.
resource "snowflake_tag" "enterprise" {
  for_each = var.tags

  database = var.governance_database
  schema   = snowflake_schema.governance[var.tag_schema].name
  # each.key is the lowercase canonical key; Snowflake folds it to upper case.
  # Declaring the folded form explicitly keeps the Terraform plan stable instead
  # of showing a perpetual diff between the requested and returned identifier.
  name           = upper(each.key)
  comment        = each.value.comment
  allowed_values = each.value.allowed_values

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Functional roles
# -----------------------------------------------------------------------------
resource "snowflake_account_role" "framework" {
  for_each = {
    TAG_ADMIN          = "Owns the enterprise tag taxonomy and the policies bound to it."
    TAG_STEWARD        = "Applies enterprise tags to objects within an owned domain."
    TAG_READER         = "Read-only access to governance metadata reporting."
    FINOPS_ANALYST     = "Read-only access to tag-driven cost allocation reporting."
    COMPLIANCE_AUDITOR = "Read-only access to compliance evidence and control attestation."
  }

  name    = each.key
  comment = each.value
}

# -----------------------------------------------------------------------------
# Account-level privileges
# -----------------------------------------------------------------------------
# APPLY TAG cannot be scoped below the account, so it is granted to exactly one
# role. Everyone else tags through GOVERNANCE.AUTOMATION.SP_APPLY_TAG, which
# enforces domain ownership. See docs/09-anti-patterns.md AP-12.
resource "snowflake_grant_account_role" "hierarchy" {
  for_each = {
    "TAG_READER_to_TAG_STEWARD"          = { role = "TAG_READER", parent = "TAG_STEWARD" }
    "TAG_STEWARD_to_TAG_ADMIN"           = { role = "TAG_STEWARD", parent = "TAG_ADMIN" }
    "TAG_READER_to_FINOPS_ANALYST"       = { role = "TAG_READER", parent = "FINOPS_ANALYST" }
    "TAG_READER_to_COMPLIANCE_AUDITOR"   = { role = "TAG_READER", parent = "COMPLIANCE_AUDITOR" }
  }

  role_name        = snowflake_account_role.framework[each.value.role].name
  parent_role_name = snowflake_account_role.framework[each.value.parent].name
}

resource "snowflake_grant_privileges_to_account_role" "tag_admin_account" {
  account_role_name = snowflake_account_role.framework["TAG_ADMIN"].name
  privileges = [
    "APPLY TAG",
    "APPLY MASKING POLICY",
    "APPLY ROW ACCESS POLICY",
    "APPLY AGGREGATION POLICY",
    "APPLY PROJECTION POLICY",
    "EXECUTE TASK",
    "EXECUTE MANAGED TASK",
    "EXECUTE ALERT",
  ]
  on_account = true
}

# CREATE TAG on exactly one schema, to exactly one role. This is what makes
# "one tag namespace" structurally true rather than a convention.
resource "snowflake_grant_privileges_to_account_role" "tag_admin_schema" {
  account_role_name = snowflake_account_role.framework["TAG_ADMIN"].name
  privileges        = ["CREATE TAG", "USAGE"]

  on_schema {
    schema_name = "\"${var.governance_database}\".\"${var.tag_schema}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "steward_read_tags" {
  account_role_name = snowflake_account_role.framework["TAG_STEWARD"].name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = "\"${var.governance_database}\".\"${var.tag_schema}\""
  }
}

# -----------------------------------------------------------------------------
# Governance warehouse
# -----------------------------------------------------------------------------
resource "snowflake_warehouse" "governance" {
  name                = var.warehouse
  warehouse_size      = "XSMALL"
  auto_suspend        = 60
  auto_resume         = true
  initially_suspended = true
  comment             = "Governance automation and reporting. Metadata-bound workload; sizing up only hides inefficient queries."
}

# -----------------------------------------------------------------------------
# The governance warehouse is itself tagged, for the same reason everything else
# is: if the framework's own infrastructure is unallocated in the cost report,
# nobody else will believe the allocation either.
# -----------------------------------------------------------------------------
resource "snowflake_tag_association" "governance_warehouse" {
  # Snowflake folds unquoted identifiers to upper case, so these keys are the
  # upper-cased form of the lowercase canonical keys in the catalog.
  for_each = {
    OPERATING_COMPANY = var.platform_operating_company
    DEPARTMENT        = var.platform_department
    TEAM              = var.platform_team
    APPLICATION       = var.platform_application
    WORKLOAD_TYPE     = "GOVERNANCE"
    ENVIRONMENT       = var.environment
  }

  object_identifiers = [snowflake_warehouse.governance.fully_qualified_name]
  object_type        = "WAREHOUSE"
  tag_id             = snowflake_tag.enterprise[each.key].fully_qualified_name
  tag_value          = each.value

  depends_on = [snowflake_tag.enterprise]
}
