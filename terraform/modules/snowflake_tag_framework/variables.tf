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
  description = "Environment of this Snowflake account. Sets environment on framework-owned objects."
  type        = string

  validation {
    condition     = contains(["PRD", "UAT", "TST", "DEV", "TRAINING", "BACKUP"], var.environment)
    error_message = "environment must be one of the environment tag's allowed values."
  }
}

# The governance platform tags itself. If the framework's own infrastructure is
# unallocated in the cost report, nobody else will believe the allocation either.
variable "platform_operating_company" {
  description = "operating_company charged for the governance platform itself."
  type        = string

  validation {
    condition     = can(regex("^(OPCO_[A-Z0-9_]{2,48}|SHARED)$", var.platform_operating_company))
    error_message = "platform_operating_company must match the operating_company tag format."
  }
}

variable "platform_department" {
  description = "department charged for the governance platform itself."
  type        = string
}

variable "platform_team" {
  description = "team accountable for building and running the governance platform."
  type        = string

  validation {
    condition     = can(regex("^team-[a-z0-9][a-z0-9-]{1,48}$", var.platform_team))
    error_message = "platform_team must match team-<lowercase>, e.g. team-data-governance."
  }
}

variable "platform_application" {
  description = "application (CMDB id) of the governance platform."
  type        = string

  validation {
    condition     = can(regex("^app-[a-z0-9][a-z0-9-]{1,48}$", var.platform_application))
    error_message = "platform_application must match app-<id>, e.g. app-tag-governance."
  }
}
