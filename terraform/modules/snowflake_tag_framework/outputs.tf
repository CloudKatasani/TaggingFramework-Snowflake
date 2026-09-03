output "tag_fqns" {
  description = "Fully qualified names of every deployed enterprise tag, keyed by tag name."
  value       = { for k, v in snowflake_tag.enterprise : k => v.fully_qualified_name }
}

output "tier1_tags" {
  description = "Tier 1 tag names. Consumed by the CI deployment gate."
  value       = sort([for k, v in var.tags : k if v.tier == 1])
}

output "role_names" {
  description = "Functional roles created by the framework."
  value       = { for k, v in snowflake_account_role.framework : k => v.name }
}

output "catalog_version" {
  description = "Catalog version this deployment corresponds to."
  value       = var.catalog_version
}
