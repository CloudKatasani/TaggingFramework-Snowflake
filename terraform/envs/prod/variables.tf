# Variables supplied by tags.auto.tfvars.json (generated from the tag catalog).
# Environment-specific values are set explicitly in main.tf rather than here, so
# a regenerated tfvars file can never silently change which account or cost
# centre this configuration targets.

variable "governance_database" {
  type    = string
  default = "GOVERNANCE"
}

variable "tag_schema" {
  type    = string
  default = "TAGS"
}

variable "policy_schema" {
  type    = string
  default = "POLICIES"
}

variable "warehouse" {
  type    = string
  default = "GOVERNANCE_WH"
}

variable "catalog_version" {
  description = "Version of config/tag_catalog.yaml this deployment was generated from."
  type        = string
}

variable "tags" {
  description = "Enterprise tag definitions. Generated - never hand-edited."
  type = map(object({
    comment        = string
    allowed_values = list(string)
    tier           = number
    category       = string
    owner_role     = string
  }))
}

variable "generator_note" {
  description = "Provenance banner emitted by scripts/generate_tfvars.py. Declared so Terraform does not warn about an undeclared value in the generated tfvars."
  type        = string
  default     = ""
}
