<!-- GENERATED FILE - DO NOT EDIT. Source: config/tag_catalog.yaml. Rebuild with `make build`. -->


# Enterprise Tag Catalog

- **Catalog version:** 2.0.0
- **Framework version:** 2.0.0
- **Owner:** Enterprise Data Governance Office (EDGO)
- **Review cadence:** Quarterly (Data Governance Council)
- **Total tags:** 40 (10 Tier 1, 15 Tier 2, 15 Tier 3)


## Tier 1 — Core Mandatory

### `operating_company`

Top-level legal and financial entity for chargeback and consolidation. The consolidation boundary for every cost report and the outermost jurisdiction boundary for data residency.

| Property | Value |
|---|---|
| Category | business |
| Value source | `controlled_vocabulary` |
| Allowed values | `OPCO_AEP_OHIO`, `OPCO_AEP_TEXAS`, `OPCO_APPALACHIAN`, `OPCO_AEP_INDIANA_MICHIGAN`, `OPCO_KENTUCKY_POWER`, `OPCO_PSC_OKLAHOMA`, `OPCO_SEPC`, `SHARED` |
| Format | `^(?:OPCO_[A-Z0-9_]{2,48}|SHARED)$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | FINANCE_FINOPS |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `ACCOUNT`, `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `WAREHOUSE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `ROLE`, `USER`, `SHARE`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | `DATABASE`, `WAREHOUSE` |
| Consumed by | `finops_chargeback`, `finops_consolidation`, `access_boundary`, `residency_control`, `discovery` |

### `department`

Business unit or cost centre within the operating company. The level at which departmental cost reports are produced and budgets are owned.

| Property | Value |
|---|---|
| Category | business |
| Value source | `controlled_vocabulary` |
| Allowed values | `FINANCE`, `HR`, `MARKETING`, `DISTRIBUTION`, `GENERATION`, `COMOPS`, `GIS`, `CORPORATE`, `CUSTOMER`, `SHARED_SERVICES` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | FINANCE_FINOPS |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `WAREHOUSE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `ROLE`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | `DATABASE`, `WAREHOUSE` |
| Consumed by | `finops_chargeback`, `department_reporting`, `budget_enforcement`, `discovery` |

### `domain`

Logical data domain owning the workload, mesh-style. The unit of federated governance and of data-product publication. Independent of department: one domain routinely serves several departments.

| Property | Value |
|---|---|
| Category | business |
| Value source | `controlled_vocabulary` |
| Allowed values | `CUSTOMER`, `LOCATION`, `METER`, `FINANCE`, `SUPPLY_CHAIN`, `MARKETING`, `RISK`, `TELEMETRY` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | EDGO |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `WAREHOUSE`, `SHARE`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | `DATABASE`, `SCHEMA` |
| Consumed by | `data_mesh`, `federated_governance`, `discovery`, `finops_showback`, `row_access_policy` |

### `team`

Engineering team accountable for build and run. Validated against the team registry so a disbanded team cannot keep owning production workloads.

| Property | Value |
|---|---|
| Category | ownership |
| Value source | `reference_data` |
| Reference set | `REF_TEAM` |
| Format | `^team-[a-z0-9][a-z0-9-]{1,48}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `WAREHOUSE`, `FUNCTION`, `PROCEDURE`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | `DATABASE`, `SCHEMA`, `PIPE`, `TASK`, `WAREHOUSE` |
| Consumed by | `incident_routing`, `stewardship_workflow`, `finops_showback`, `operational_reporting` |

### `application`

Discrete application or data product, aligned to the CMDB. The join key between Snowflake objects and the enterprise application portfolio, which is what makes cross-platform impact analysis possible at all.

| Property | Value |
|---|---|
| Category | business |
| Value source | `reference_data` |
| Reference set | `REF_APPLICATION` |
| Format | `^app-[a-z0-9][a-z0-9-]{1,48}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | ENTERPRISE_ARCHITECTURE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `WAREHOUSE`, `INTEGRATION`, `SHARE`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | `SCHEMA`, `PIPE`, `TASK`, `WAREHOUSE` |
| Consumed by | `cmdb_reconciliation`, `impact_analysis`, `finops_chargeback`, `discovery`, `incident_routing` |

### `workload_type`

Workload class, for resource-pattern rollups. Lets FinOps compare like with like across the estate - ML training spend against ML training spend, not against BI - and drives right-sizing recommendations per pattern.

| Property | Value |
|---|---|
| Category | operational |
| Value source | `controlled_vocabulary` |
| Allowed values | `INGEST`, `TRANSFORM`, `ANALYTICS`, `ML_TRAIN`, `ML_SERVE`, `BI`, `GOVERNANCE`, `PLATFORM_OPS` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `WAREHOUSE`, `FUNCTION`, `PROCEDURE`, `NOTEBOOK`, `STREAMLIT` |
| Mandatory on | `PIPE`, `TASK`, `WAREHOUSE` |
| Consumed by | `finops_rightsizing`, `workload_analytics`, `capacity_planning`, `finops_showback` |

### `owner_user`

Accountable individual by SSO email, or the named service account that owns an automated workload. Recommended rather than mandatory: an owner tag that is mandated before joiner-mover-leaver feeds are wired up fills with stale names, which is worse than an honest blank.

| Property | Value |
|---|---|
| Category | ownership |
| Value source | `free_text` |
| Format | `^(?:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|service-account-[a-z0-9][a-z0-9-]{1,48})$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | EDGO |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `ACCOUNT`, `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `WAREHOUSE`, `ROLE`, `USER`, `INTEGRATION`, `SHARE`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `incident_routing`, `access_approval`, `attestation`, `finops_accountability` |

### `environment`

Lifecycle stage, required alongside the core tags. Never inherited across a clone into a different environment - the clone-remediation job rewrites it.

| Property | Value |
|---|---|
| Category | lifecycle |
| Value source | `controlled_vocabulary` |
| Allowed values | `PRD`, `UAT`, `TST`, `DEV`, `TRAINING`, `BACKUP` |
| Inheritance | `inherit` |
| Override rule | `none` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `ACCOUNT`, `DATABASE`, `SCHEMA`, `WAREHOUSE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `ROLE`, `INTEGRATION`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | `DATABASE`, `WAREHOUSE` |
| Consumed by | `policy_selection`, `promotion_gate`, `finops_chargeback`, `masking_strictness`, `nonprod_waste_analysis` |

### `data_classification_enterprise`

Core enterprise confidentiality classification. The only tag carrying masking policy attachments, so it is the anchor of the whole protection model. Most restrictive value in the lineage wins.

| Property | Value |
|---|---|
| Category | classification |
| Value source | `controlled_vocabulary` |
| Allowed values | `NONE`, `PUBLIC`, `INTERNAL`, `CONFIDENTIAL`, `RESTRICTED` |
| Severity order | `NONE` ‹ `PUBLIC` ‹ `INTERNAL` ‹ `CONFIDENTIAL` ‹ `RESTRICTED` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | CISO_DATA_SECURITY |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `ACCOUNT`, `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `EXTERNAL_TABLE`, `ICEBERG_TABLE`, `COLUMN`, `STAGE`, `SHARE`, `NOTEBOOK`, `STREAMLIT` |
| Mandatory on | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `STAGE`, `SHARE` |
| Consumed by | `dynamic_masking`, `sharing_control`, `export_control`, `compliance_reporting`, `discovery` |

### `data_classification_regulatory`

Regulatory-driven data classification. Holds the GOVERNING category - the one whose technical controls are most prescriptive - resolved by documented precedence. Where several categories apply, the full set is recorded in CONTROL.REGULATORY_SCOPE, because a Snowflake tag holds only one value.

| Property | Value |
|---|---|
| Category | privacy |
| Value source | `controlled_vocabulary` |
| Allowed values | `NONE`, `PII`, `SPII`, `PHI`, `PCI` |
| Severity order | `NONE` ‹ `PII` ‹ `SPII` ‹ `PHI` ‹ `PCI` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | PRIVACY_OFFICE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `EXTERNAL_TABLE`, `ICEBERG_TABLE`, `COLUMN`, `STAGE`, `SHARE` |
| Mandatory on | `SCHEMA`, `TABLE`, `VIEW`, `COLUMN`, `STAGE`, `SHARE` |
| Consumed by | `dynamic_masking`, `privacy_reporting`, `dsar_fulfilment`, `audit_evidence`, `auto_classification`, `pci_scoping` |


## Tier 2 — Governance

### `data_product`

Named, versioned, independently consumable data product. Maps 1:1 to a schema, which is the publication boundary. Distinct from `application`: one application can publish several data products.

| Property | Value |
|---|---|
| Category | business |
| Value source | `reference_data` |
| Reference set | `REF_DATA_PRODUCT` |
| Format | `^dp-[a-z0-9][a-z0-9-]{2,48}$` |
| Inheritance | `inherit` |
| Override rule | `none` |
| Owner | DOMAIN_COUNCIL |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `SHARE`, `NOTEBOOK`, `STREAMLIT` |
| Mandatory on | `SHARE` |
| Consumed by | `data_mesh`, `discovery`, `lineage`, `sla_management`, `consumer_contract` |

### `data_owner`

Accountable business owner (RACI 'A') for the DATA, as distinct from owner_user who is accountable for the RESOURCE. Approves access, classification and retention decisions.

| Property | Value |
|---|---|
| Category | ownership |
| Value source | `free_text` |
| Format | `^(?:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|GRP-[A-Z0-9-]{3,48})$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | EDGO |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `STAGE`, `SHARE`, `APPLICATION` |
| Mandatory on | `SHARE` |
| Consumed by | `access_approval`, `attestation`, `remediation_routing`, `audit_evidence` |

### `data_steward`

Responsible steward (RACI 'R') executing day-to-day governance: tagging, classification review, quality remediation, metadata curation.

| Property | Value |
|---|---|
| Category | ownership |
| Value source | `free_text` |
| Format | `^(?:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|GRP-[A-Z0-9-]{3,48})$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | EDGO |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `STAGE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `stewardship_workflow`, `attestation`, `remediation_routing` |

### `support_group`

ITSM queue that owns break/fix. Complements `team`, which names the accountable engineers; support_group names where the ticket actually lands out of hours.

| Property | Value |
|---|---|
| Category | ownership |
| Value source | `reference_data` |
| Reference set | `REF_SUPPORT_GROUP` |
| Format | `^GRP-[A-Z0-9-]{3,48}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `DYNAMIC_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `WAREHOUSE`, `INTEGRATION`, `APPLICATION` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `incident_routing`, `sla_management`, `operational_reporting` |

### `cost_center`

GL cost centre code. `department` is the human-facing allocation level; cost_center is the posting key a journal entry actually needs. Required wherever cost_allocation_model is CHARGEBACK.

| Property | Value |
|---|---|
| Category | financial |
| Value source | `reference_data` |
| Reference set | `REF_COST_CENTER` |
| Format | `^CC-[0-9]{4,8}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | FINANCE_FINOPS |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `ACCOUNT`, `DATABASE`, `SCHEMA`, `WAREHOUSE`, `TASK`, `PIPE`, `ROLE`, `USER`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `finops_chargeback`, `budget_enforcement`, `gl_posting` |

### `criticality`

Business impact if the object is unavailable or incorrect. Drives DR scope, monitoring depth, change-control rigour and incident severity.

| Property | Value |
|---|---|
| Category | lifecycle |
| Value source | `controlled_vocabulary` |
| Allowed values | `LOW`, `MEDIUM`, `HIGH`, `CRITICAL` |
| Severity order | `LOW` ‹ `MEDIUM` ‹ `HIGH` ‹ `CRITICAL` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `PIPE`, `TASK`, `STREAM`, `WAREHOUSE`, `APPLICATION` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `dr_scope`, `monitoring_depth`, `change_control`, `incident_severity` |

### `data_lifecycle`

Lifecycle state of the object itself. Drives deprecation comms, consumer warnings and the automated archive/purge pipeline. Deprecated data nobody deleted is consistently one of the largest recoverable cost lines.

| Property | Value |
|---|---|
| Category | lifecycle |
| Value source | `controlled_vocabulary` |
| Allowed values | `ACTIVE`, `DEPRECATED`, `ARCHIVED`, `PENDING_PURGE` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | EDGO |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `retirement_automation`, `consumer_notification`, `cost_avoidance`, `discovery` |

### `retention_class`

Records-management retention class from the enterprise retention schedule. Drives the automated archive and purge pipeline. legal_hold always supersedes it.

| Property | Value |
|---|---|
| Category | compliance |
| Value source | `controlled_vocabulary` |
| Allowed values | `TRANSIENT_30D`, `SHORT_1Y`, `STANDARD_3Y`, `EXTENDED_7Y`, `REGULATORY_10Y`, `PERMANENT`, `INDEFINITE_REVIEW` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | RECORDS_MANAGEMENT |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `EXTERNAL_TABLE`, `STAGE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `retention_automation`, `purge_pipeline`, `compliance_reporting`, `storage_cost_control` |

### `legal_hold`

Litigation hold. When YES, all retention-driven archive and purge automation is suppressed regardless of retention_class. Set only by Legal.

| Property | Value |
|---|---|
| Category | compliance |
| Value source | `controlled_vocabulary` |
| Allowed values | `YES`, `NO` |
| Severity order | `NO` ‹ `YES` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | LEGAL |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `EXTERNAL_TABLE`, `STAGE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `purge_suppression`, `ediscovery`, `audit_evidence` |

### `regulation`

The governing regulatory REGIME, as distinct from data_classification_regulatory which states what the DATA IS. A financial ledger with no personal data at all is still in SOX scope; the two tags answer different questions and are both needed for evidence.

| Property | Value |
|---|---|
| Category | compliance |
| Value source | `controlled_vocabulary` |
| Allowed values | `NONE`, `SOX`, `GDPR`, `CCPA`, `HIPAA`, `PCI_DSS`, `GLBA`, `FERPA`, `NERC_CIP`, `MULTI` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | COMPLIANCE_OFFICE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `EXTERNAL_TABLE`, `COLUMN`, `STAGE`, `SHARE` |
| Mandatory on | `SHARE` |
| Consumed by | `compliance_reporting`, `audit_evidence`, `policy_selection`, `residency_control` |

### `sla_tier`

Freshness and availability commitment published to consumers. Drives monitoring thresholds, alert routing and DR tiering.

| Property | Value |
|---|---|
| Category | operational |
| Value source | `controlled_vocabulary` |
| Allowed values | `PLATINUM_15M`, `GOLD_1H`, `SILVER_4H`, `BRONZE_24H`, `BEST_EFFORT` |
| Severity order | `BEST_EFFORT` ‹ `BRONZE_24H` ‹ `SILVER_4H` ‹ `GOLD_1H` ‹ `PLATINUM_15M` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `PIPE`, `TASK`, `STREAM`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `sla_management`, `monitoring_depth`, `alert_routing`, `dr_scope` |

### `masking_required`

Declares that the column must carry a masking policy. This is DECLARED INTENT; the tag-based policy attachment is ENFORCEMENT. The drift detector reconciles the two, and divergence is the finding that matters most.

| Property | Value |
|---|---|
| Category | security |
| Value source | `controlled_vocabulary` |
| Allowed values | `YES`, `NO` |
| Severity order | `NO` ‹ `YES` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | CISO_DATA_SECURITY |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `EXTERNAL_TABLE`, `ICEBERG_TABLE`, `COLUMN` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `dynamic_masking`, `control_attestation`, `drift_detection` |

### `row_access_required`

Declares that the table or view must carry a row access policy. Snowflake does NOT support attaching row access policies to tags, so enforcement runs through the SP_APPLY_ROW_ACCESS_POLICIES reconciliation task.

| Property | Value |
|---|---|
| Category | security |
| Value source | `controlled_vocabulary` |
| Allowed values | `YES`, `NO` |
| Severity order | `NO` ‹ `YES` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | CISO_DATA_SECURITY |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `EXTERNAL_TABLE`, `ICEBERG_TABLE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `row_access_policy`, `control_attestation`, `drift_detection` |

### `data_residency`

Region in which the data must remain. Drives replication scope and cross-region share eligibility.

| Property | Value |
|---|---|
| Category | compliance |
| Value source | `controlled_vocabulary` |
| Allowed values | `US`, `US_EAST`, `US_WEST`, `EU`, `UK`, `CANADA`, `APAC`, `GLOBAL` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | COMPLIANCE_OFFICE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `ICEBERG_TABLE`, `EXTERNAL_TABLE`, `STAGE`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `residency_control`, `replication_control`, `sharing_control`, `compliance_reporting` |

### `data_quality_tier`

Certified quality level. Set only by the data-quality pipeline once data metric function results are evaluated; never inherited, because a table in a GOLD schema is not GOLD until its own measurements say so.

| Property | Value |
|---|---|
| Category | data_quality |
| Value source | `controlled_vocabulary` |
| Allowed values | `BRONZE`, `SILVER`, `GOLD`, `PLATINUM` |
| Severity order | `BRONZE` ‹ `SILVER` ‹ `GOLD` ‹ `PLATINUM` |
| Inheritance | `explicit_only` |
| Override rule | `any` |
| Owner | EDGO |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `quality_reporting`, `consumer_contract`, `discovery`, `certification` |


## Tier 3 — Optional / Domain

### `sub_domain`

Second-level decomposition of domain, for large domains only.

| Property | Value |
|---|---|
| Category | business |
| Value source | `reference_data` |
| Reference set | `REF_SUB_DOMAIN` |
| Format | `^[A-Z0-9][A-Z0-9_]{1,62}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | DOMAIN_COUNCIL |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `TASK`, `PIPE`, `STREAM` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `discovery`, `federated_governance`, `finops_showback` |

### `source_system`

System of record the data originates from. Roots lineage at the edge.

| Property | Value |
|---|---|
| Category | business |
| Value source | `reference_data` |
| Reference set | `REF_APPLICATION` |
| Format | `^app-[a-z0-9][a-z0-9-]{1,48}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | DOMAIN_COUNCIL |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `EXTERNAL_TABLE`, `ICEBERG_TABLE`, `STAGE`, `PIPE`, `STREAM` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `lineage`, `impact_analysis`, `discovery` |

### `application_owner`

Accountable owner of the application referenced by the object.

| Property | Value |
|---|---|
| Category | ownership |
| Value source | `free_text` |
| Format | `^(?:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|service-account-[a-z0-9][a-z0-9-]{1,48})$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | ENTERPRISE_ARCHITECTURE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `STAGE`, `PIPE`, `TASK`, `INTEGRATION`, `APPLICATION` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `impact_analysis`, `incident_routing`, `attestation` |

### `platform_owner`

Platform engineering team accountable for the infrastructure object.

| Property | Value |
|---|---|
| Category | ownership |
| Value source | `reference_data` |
| Reference set | `REF_SUPPORT_GROUP` |
| Format | `^GRP-[A-Z0-9-]{3,48}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `ACCOUNT`, `WAREHOUSE`, `INTEGRATION`, `SHARE`, `ROLE`, `DATABASE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `incident_routing`, `platform_attestation`, `finops_chargeback` |

### `domain_owner`

Accountable owner of the mesh domain. Normally set once, on the domain's database.

| Property | Value |
|---|---|
| Category | data_mesh |
| Value source | `free_text` |
| Format | `^(?:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|GRP-[A-Z0-9-]{3,48})$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | DOMAIN_COUNCIL |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `data_mesh`, `federated_governance`, `access_approval` |

### `data_product_owner`

Product owner accountable for the data product's roadmap, SLA and consumer contract. Distinct from data_owner, who is accountable for the data itself.

| Property | Value |
|---|---|
| Category | data_mesh |
| Value source | `free_text` |
| Format | `^(?:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|GRP-[A-Z0-9-]{3,48})$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | DOMAIN_COUNCIL |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `SHARE`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `data_mesh`, `sla_management`, `consumer_contract`, `access_approval` |

### `data_product_type`

Mesh archetype; sets default quality and SLA expectations.

| Property | Value |
|---|---|
| Category | data_mesh |
| Value source | `controlled_vocabulary` |
| Allowed values | `SOURCE_ALIGNED`, `AGGREGATE`, `CONSUMER_ALIGNED`, `SHARED`, `PLATFORM` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | DOMAIN_COUNCIL |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `data_mesh`, `discovery`, `quality_expectation` |

### `capability`

Business capability from the enterprise capability model (L2).

| Property | Value |
|---|---|
| Category | business |
| Value source | `reference_data` |
| Reference set | `REF_CAPABILITY` |
| Format | `^[A-Z0-9][A-Z0-9_]{1,62}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | ENTERPRISE_ARCHITECTURE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `DYNAMIC_TABLE`, `APPLICATION` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `discovery`, `portfolio_analysis` |

### `project_code`

Capital or programme project funding the workload.

| Property | Value |
|---|---|
| Category | financial |
| Value source | `reference_data` |
| Reference set | `REF_PROJECT` |
| Format | `^(PRJ|PRG)-[A-Z0-9]{2,4}-[0-9]{3,6}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | FINANCE_FINOPS |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `WAREHOUSE`, `TASK`, `PIPE`, `NOTEBOOK`, `STREAMLIT` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `finops_chargeback`, `project_reporting`, `capitalisation` |

### `cost_allocation_model`

How this object's consumption is settled with the business. SHOWBACK reports only; CHARGEBACK posts a journal entry to the ERP.

| Property | Value |
|---|---|
| Category | financial |
| Value source | `controlled_vocabulary` |
| Allowed values | `SHOWBACK`, `CHARGEBACK`, `SHARED_SERVICE`, `ABSORBED_PLATFORM` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | FINANCE_FINOPS |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `WAREHOUSE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `finops_chargeback`, `department_reporting` |

### `encryption_required`

Declares that application-layer or client-side encryption is required in addition to transparent encryption at rest. Mainly external stages and columns holding secrets or key material.

| Property | Value |
|---|---|
| Category | security |
| Value source | `controlled_vocabulary` |
| Allowed values | `YES`, `NO` |
| Severity order | `NO` ‹ `YES` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | CISO_DATA_SECURITY |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `TABLE`, `COLUMN`, `STAGE`, `PIPE`, `INTEGRATION` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `encryption_control`, `audit_evidence`, `drift_detection` |

### `sharing_scope`

Maximum permitted distribution. Checked before any listing, share or reader-account grant is created.

| Property | Value |
|---|---|
| Category | security |
| Value source | `controlled_vocabulary` |
| Allowed values | `PROHIBITED`, `INTERNAL_ONLY`, `AFFILIATE`, `PARTNER`, `PUBLIC_MARKETPLACE` |
| Severity order | `PROHIBITED` ‹ `INTERNAL_ONLY` ‹ `AFFILIATE` ‹ `PARTNER` ‹ `PUBLIC_MARKETPLACE` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | CISO_DATA_SECURITY |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `sharing_control`, `export_control`, `compliance_reporting` |

### `refresh_type`

How the object's data is refreshed. Drives freshness monitoring logic.

| Property | Value |
|---|---|
| Category | operational |
| Value source | `controlled_vocabulary` |
| Allowed values | `STREAMING`, `MICRO_BATCH`, `BATCH_HOURLY`, `BATCH_DAILY`, `BATCH_WEEKLY`, `BATCH_MONTHLY`, `ON_DEMAND`, `STATIC` |
| Inheritance | `explicit_only` |
| Override rule | `any` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `EXTERNAL_TABLE`, `ICEBERG_TABLE`, `PIPE`, `TASK`, `STREAM` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `freshness_monitoring`, `sla_management`, `lineage` |

### `rpo`

Recovery Point Objective as an ISO-8601 duration (e.g. PT15M, P1D).

| Property | Value |
|---|---|
| Category | operational |
| Value source | `free_text` |
| Format | `^PT(?:[0-9]{1,3}H)?(?:[0-9]{1,3}M)?$|^P[0-9]{1,3}D$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `DYNAMIC_TABLE`, `ICEBERG_TABLE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `dr_scope`, `replication_control`, `sla_management` |

### `rto`

Recovery Time Objective as an ISO-8601 duration (e.g. PT4H, P1D).

| Property | Value |
|---|---|
| Category | operational |
| Value source | `free_text` |
| Format | `^PT(?:[0-9]{1,3}H)?(?:[0-9]{1,3}M)?$|^P[0-9]{1,3}D$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `DYNAMIC_TABLE`, `ICEBERG_TABLE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `dr_scope`, `sla_management` |


## Conditional mandates

Tags that become mandatory only when a predicate over other *effective* tag values holds.

| Rule | Severity | When | Then mandatory | On |
|---|---|---|---|---|
| **CR-001** | CRITICAL | `data_classification_regulatory` ∈ ['PII', 'SPII', 'PHI', 'PCI'] | `masking_required` | `COLUMN` |
| | | _Any column carrying regulated data must declare masking intent, so that declared-versus-enforced drift is detectable for it._ | | |
| **CR-002** | CRITICAL | `data_classification_regulatory` ∈ ['PCI'] | `encryption_required` | `TABLE`, `COLUMN`, `STAGE` |
| | | _Cardholder data requires application-layer encryption in addition to Snowflake's transparent encryption at rest._ | | |
| **CR-003** | HIGH | `data_classification_enterprise` ∈ ['RESTRICTED'] | `row_access_required` | `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE` |
| | | _RESTRICTED data must declare row-level access intent; confidentiality at this level is rarely satisfied by column masking alone._ | | |
| **CR-004** | HIGH | `data_classification_regulatory` ∈ ['PII', 'SPII', 'PHI', 'PCI'] | `data_owner`, `retention_class` | `SCHEMA`, `TABLE`, `VIEW` |
| | | _Regulated data needs an accountable data owner and a retention class - without both, neither a DSAR nor a purge can be executed._ | | |
| **CR-005** | HIGH | `data_classification_regulatory` ∈ ['SPII', 'PHI', 'PCI'] | `data_residency` | `DATABASE`, `SCHEMA`, `SHARE` |
| | | _Personal and health data must declare residency so replication and cross-region sharing can be evaluated before, not after, the fact._ | | |
| **CR-006** | MEDIUM | `criticality` ∈ ['CRITICAL'] | `rpo`, `rto` | `DATABASE`, `SCHEMA`, `TABLE` |
| | | _Business-critical objects must publish RPO and RTO for DR planning._ | | |
| **CR-007** | CRITICAL | _always_ | `sharing_scope`, `data_classification_enterprise`, `data_owner`, `data_product` | `SHARE` |
| | | _Data leaving the account always needs a named owner, a classification and an explicit distribution scope. There is no version of a share for which this is optional._ | | |
| **CR-008** | MEDIUM | `environment` ∈ ['PRD'] | `support_group`, `sla_tier` | `SCHEMA`, `TASK`, `PIPE` |
| | | _Production workloads must name an on-call queue and an SLA commitment. An unroutable production incident is the failure this prevents._ | | |
| **CR-009** | MEDIUM | `cost_allocation_model` ∈ ['CHARGEBACK'] | `cost_center` | `WAREHOUSE`, `DATABASE`, `SCHEMA` |
| | | _Chargeback settlement posts a journal entry, which needs a GL cost centre code; `department` alone is not a posting key._ | | |

## Regulation precedence

`REGULATION` holds a single governing regime. Where several apply, the earliest in this order wins and the tag is set to `MULTI`, with the full set recorded in `CONTROL.REGULATORY_SCOPE`.

`HIPAA` → `PCI_DSS` → `NERC_CIP` → `GLBA` → `SOX` → `GDPR` → `CCPA` → `FERPA` → `NONE`
