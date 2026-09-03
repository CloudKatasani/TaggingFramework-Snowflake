variable "governance_database" {
  description = "Governance database holding tags, policies and the control plane."
  type        = string
  default     = "GOVERNANCE"
}

variable "tag_schema" {
  description = "The one schema in which enterprise tags may exist."
  type        = string
  default     = "TAGS"
}

variable "policy_schema" {
  description = "Schema holding masking, row access, aggregation and projection policies."
  type        = string
  default     = "POLICIES"
}

variable "warehouse" {
  description = "Warehouse running governance automation and reporting."
  type        = string
  default     = "GOVERNANCE_WH"
}

variable "catalog_version" {
  description = "Version of config/tag_catalog.yaml this deployment was generated from."
  type        = string
}

variable "tags" {
  description = <<-EOT
    Enterprise tag definitions, generated from config/tag_catalog.yaml by
    scripts/generate_tfvars.py. Never edit by hand - `make build` regenerates it
    and CI fails if the committed file is stale.
  EOT
  type = map(object({
    comment        = string
    allowed_values = list(string)
    tier           = number
    category       = string
    owner_role     = string
  }))
}

variable "environment" {
  description = "Environment of this Snowflake account. Sets ENVIRONMENT on framework-owned objects."
  type        = string

  validation {
    condition     = contains(["DEV", "TEST", "UAT", "PROD", "SANDBOX", "DR"], var.environment)
    error_message = "environment must be one of the ENVIRONMENT tag's allowed values."
  }
}

variable "platform_business_unit" {
  description = "BUSINESS_UNIT charged for the governance platform itself."
  type        = string
}

variable "platform_cost_center" {
  description = "COST_CENTER charged for the governance platform itself."
  type        = string

  validation {
    condition     = can(regex("^CC-[0-9]{4,8}$", var.platform_cost_center))
    error_message = "platform_cost_center must match the COST_CENTER tag format, e.g. CC-004120."
  }
}
