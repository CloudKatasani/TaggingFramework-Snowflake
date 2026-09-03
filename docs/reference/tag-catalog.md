<!-- GENERATED FILE - DO NOT EDIT. Source: config/tag_catalog.yaml. Rebuild with `make build`. -->


# Enterprise Tag Catalog

- **Catalog version:** 1.0.0
- **Framework version:** 1.0.0
- **Owner:** Enterprise Data Governance Office (EDGO)
- **Review cadence:** Quarterly (Data Governance Council)
- **Total tags:** 42 (17 Tier 1, 14 Tier 2, 11 Tier 3)


## Tier 1 — Core Mandatory

### `BUSINESS_UNIT`

Top-level legal/reporting entity accountable for the object. Anchors cost allocation, access boundaries and regulatory jurisdiction.

| Property | Value |
|---|---|
| Category | business |
| Value source | `reference_data` |
| Reference set | `REF_BUSINESS_UNIT` |
| Format | `^[A-Z0-9][A-Z0-9_]{1,62}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | EDGO |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `ACCOUNT`, `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `WAREHOUSE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `ROLE`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | `DATABASE`, `WAREHOUSE` |
| Consumed by | `finops_chargeback`, `access_boundary`, `discovery`, `compliance_reporting` |

### `DOMAIN`

Data Mesh domain that owns the object (e.g. CUSTOMER, FINANCE, SUPPLY_CHAIN). The unit of federated governance and of data-product publication.

| Property | Value |
|---|---|
| Category | business |
| Value source | `reference_data` |
| Reference set | `REF_DOMAIN` |
| Format | `^[A-Z0-9][A-Z0-9_]{1,62}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | EDGO |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `WAREHOUSE`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | `DATABASE`, `SCHEMA` |
| Consumed by | `data_mesh`, `discovery`, `federated_governance`, `finops_showback` |

### `DATA_PRODUCT`

Named, versioned, independently consumable data product. In this framework a data product maps 1:1 to a schema (the publication boundary).

| Property | Value |
|---|---|
| Category | business |
| Value source | `reference_data` |
| Reference set | `REF_DATA_PRODUCT` |
| Format | `^[A-Z0-9][A-Z0-9_]{2,62}$` |
| Inheritance | `inherit` |
| Override rule | `none` |
| Owner | DOMAIN_COUNCIL |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `SHARE`, `NOTEBOOK`, `STREAMLIT` |
| Mandatory on | `SCHEMA`, `SHARE` |
| Consumed by | `data_mesh`, `discovery`, `lineage`, `sla_management`, `finops_showback` |

### `DATA_OWNER`

Accountable business owner (RACI 'A') for the data. Named individual or enterprise group. Approves access, classification and retention decisions.

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
| Mandatory on | `DATABASE`, `SCHEMA` |
| Consumed by | `access_approval`, `incident_routing`, `attestation`, `discovery` |

### `DATA_STEWARD`

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
| Mandatory on | `SCHEMA` |
| Consumed by | `stewardship_workflow`, `attestation`, `remediation_routing` |

### `SUPPORT_GROUP`

Operational on-call group that owns break/fix for the object. Must resolve to a real queue in the enterprise ITSM tool.

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
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `DYNAMIC_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `WAREHOUSE`, `APPLICATION` |
| Mandatory on | `DATABASE`, `PIPE`, `TASK` |
| Consumed by | `incident_routing`, `sla_management`, `operational_reporting` |

### `DATA_CLASSIFICATION`

Enterprise confidentiality level. The primary driver of masking, sharing eligibility and export controls. Most restrictive value in the lineage wins.

| Property | Value |
|---|---|
| Category | classification |
| Value source | `controlled_vocabulary` |
| Allowed values | `PUBLIC`, `INTERNAL`, `CONFIDENTIAL`, `RESTRICTED`, `HIGHLY_RESTRICTED` |
| Severity order | `PUBLIC` ‹ `INTERNAL` ‹ `CONFIDENTIAL` ‹ `RESTRICTED` ‹ `HIGHLY_RESTRICTED` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | CISO_DATA_SECURITY |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `ACCOUNT`, `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `EXTERNAL_TABLE`, `ICEBERG_TABLE`, `COLUMN`, `STAGE`, `SHARE`, `NOTEBOOK`, `STREAMLIT` |
| Mandatory on | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `STAGE`, `SHARE` |
| Consumed by | `dynamic_masking`, `sharing_control`, `export_control`, `compliance_reporting`, `discovery` |

### `PII`

Object contains Personally Identifiable Information as defined by the enterprise privacy standard. Set automatically at column level by the Snowflake classification reconciliation job; human-overridable with reason.

| Property | Value |
|---|---|
| Category | privacy |
| Value source | `controlled_vocabulary` |
| Allowed values | `YES`, `NO` |
| Severity order | `NO` ‹ `YES` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | PRIVACY_OFFICE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `EXTERNAL_TABLE`, `ICEBERG_TABLE`, `COLUMN`, `STAGE`, `SHARE` |
| Mandatory on | `TABLE`, `VIEW`, `COLUMN`, `SHARE` |
| Consumed by | `dynamic_masking`, `privacy_reporting`, `dsar_fulfilment`, `gdpr_ccpa_evidence`, `auto_classification` |

### `ENVIRONMENT`

Deployment environment of the object. Never inherited across a clone into a different environment - the clone-remediation task rewrites it.

| Property | Value |
|---|---|
| Category | lifecycle |
| Value source | `controlled_vocabulary` |
| Allowed values | `DEV`, `TEST`, `UAT`, `PROD`, `SANDBOX`, `DR` |
| Inheritance | `inherit` |
| Override rule | `none` |
| Owner | PLATFORM_ENGINEERING |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `ACCOUNT`, `DATABASE`, `SCHEMA`, `WAREHOUSE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `ROLE`, `INTEGRATION`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | `DATABASE`, `WAREHOUSE` |
| Consumed by | `policy_selection`, `finops_chargeback`, `promotion_gate`, `masking_strictness` |

### `DATA_LIFECYCLE`

Lifecycle state of the object itself. Drives deprecation comms, consumer warnings and the automated archive/purge pipeline.

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
| Mandatory on | `SCHEMA`, `TABLE`, `VIEW` |
| Consumed by | `retirement_automation`, `consumer_notification`, `cost_avoidance`, `discovery` |

### `CRITICALITY`

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
| Mandatory on | `DATABASE`, `SCHEMA` |
| Consumed by | `dr_scope`, `monitoring_depth`, `change_control`, `incident_severity` |

### `COST_CENTER`

GL cost centre charged for the compute and storage attributed to the object. Must exist and be open in the ERP chart of accounts.

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
| Applies to | `ACCOUNT`, `DATABASE`, `SCHEMA`, `WAREHOUSE`, `TASK`, `PIPE`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION`, `ROLE`, `USER` |
| Mandatory on | `DATABASE`, `WAREHOUSE` |
| Consumed by | `finops_chargeback`, `budget_enforcement`, `department_reporting` |

### `RETENTION_CLASS`

Records-management retention class from the enterprise retention schedule. Drives the automated archive/purge pipeline. LEGAL_HOLD always supersedes.

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
| Mandatory on | `SCHEMA`, `TABLE`, `STAGE` |
| Consumed by | `retention_automation`, `purge_pipeline`, `compliance_reporting`, `storage_cost_control` |

### `REGULATION`

The GOVERNING regulatory regime - the single regime whose controls are the most stringent for this object, resolved by documented precedence. The full multi-regime scope lives in CONTROL.REGULATORY_SCOPE (Snowflake tags are single-valued); see docs/02-tag-taxonomy.md#multi-valued-attributes.

| Property | Value |
|---|---|
| Category | compliance |
| Value source | `controlled_vocabulary` |
| Allowed values | `NONE`, `SOX`, `GDPR`, `CCPA`, `HIPAA`, `PCI_DSS`, `GLBA`, `FERPA`, `LGPD`, `PIPEDA`, `PDPA`, `MULTI` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | COMPLIANCE_OFFICE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `EXTERNAL_TABLE`, `COLUMN`, `STAGE`, `SHARE` |
| Mandatory on | `SCHEMA`, `TABLE`, `SHARE` |
| Consumed by | `compliance_reporting`, `residency_control`, `audit_evidence`, `policy_selection` |

### `MASKING_REQUIRED`

Declares that the column must carry a masking policy. This is the DECLARED INTENT; SNOWFLAKE.CORE tag-based masking attachment is the ENFORCEMENT. The drift detector reconciles the two and raises on divergence.

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
| Mandatory on | `COLUMN` |
| Consumed by | `dynamic_masking`, `control_attestation`, `drift_detection` |

### `ROW_ACCESS_REQUIRED`

Declares that the table/view must carry a row access policy. Snowflake does NOT support attaching row access policies to tags, so enforcement is via the SP_APPLY_ROW_ACCESS_POLICIES reconciliation task, not tag attachment.

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
| Mandatory on | `TABLE`, `VIEW` |
| Consumed by | `row_access_policy`, `control_attestation`, `drift_detection` |

### `SLA_TIER`

Freshness/availability commitment published to consumers of the data product. Drives monitoring thresholds, alert routing and DR tiering.

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
| Mandatory on | `SCHEMA`, `PIPE`, `TASK` |
| Consumed by | `sla_management`, `monitoring_depth`, `alert_routing`, `dr_scope` |


## Tier 2 — Governance

### `SUB_DOMAIN`

Second-level decomposition of DOMAIN, for large domains only.

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

### `APPLICATION`

CMDB application identifier of the producing or consuming system. Enables impact analysis between Snowflake objects and the application portfolio.

| Property | Value |
|---|---|
| Category | business |
| Value source | `reference_data` |
| Reference set | `REF_APPLICATION` |
| Format | `^APP-[0-9]{4,8}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | ENTERPRISE_ARCHITECTURE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `DYNAMIC_TABLE`, `STAGE`, `PIPE`, `TASK`, `STREAM`, `INTEGRATION`, `NOTEBOOK`, `STREAMLIT`, `APPLICATION` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `impact_analysis`, `cmdb_reconciliation`, `incident_routing` |

### `APPLICATION_OWNER`

Accountable owner of the APPLICATION referenced by the object.

| Property | Value |
|---|---|
| Category | ownership |
| Value source | `free_text` |
| Format | `^(?:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|GRP-[A-Z0-9-]{3,48})$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | ENTERPRISE_ARCHITECTURE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `STAGE`, `PIPE`, `TASK`, `INTEGRATION`, `APPLICATION` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `impact_analysis`, `incident_routing`, `attestation` |

### `PLATFORM_OWNER`

Platform engineering team accountable for the Snowflake infrastructure object (warehouse, integration, share, account-level construct).

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
| Mandatory on | `WAREHOUSE`, `INTEGRATION` |
| Consumed by | `incident_routing`, `platform_attestation`, `finops_chargeback` |

### `DOMAIN_OWNER`

Accountable owner of the mesh DOMAIN. Normally set once on the domain's database and inherited; a per-object override is an exception.

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

### `DATA_PRODUCT_OWNER`

Product owner accountable for the data product's roadmap, SLA and consumer contract. Distinct from DATA_OWNER (who is accountable for the data itself).

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
| Mandatory on | `SHARE` |
| Consumed by | `data_mesh`, `sla_management`, `consumer_contract`, `access_approval` |

### `DATA_PRODUCT_TYPE`

Mesh archetype of the data product; sets default quality and SLA expectations.

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

### `PHI`

Protected Health Information under HIPAA. Conditionally MANDATORY wherever REGULATION resolves to HIPAA. Drives the HIPAA masking policy set.

| Property | Value |
|---|---|
| Category | privacy |
| Value source | `controlled_vocabulary` |
| Allowed values | `YES`, `NO` |
| Severity order | `NO` ‹ `YES` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | PRIVACY_OFFICE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `EXTERNAL_TABLE`, `ICEBERG_TABLE`, `COLUMN`, `STAGE`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `dynamic_masking`, `hipaa_evidence`, `privacy_reporting`, `auto_classification` |

### `PCI`

Cardholder data in PCI-DSS scope. Conditionally MANDATORY wherever REGULATION resolves to PCI_DSS. Drives tokenisation/masking and CDE scoping.

| Property | Value |
|---|---|
| Category | privacy |
| Value source | `controlled_vocabulary` |
| Allowed values | `YES`, `NO` |
| Severity order | `NO` ‹ `YES` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | CISO_DATA_SECURITY |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE`, `EXTERNAL_TABLE`, `ICEBERG_TABLE`, `COLUMN`, `STAGE`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `dynamic_masking`, `pci_scoping`, `audit_evidence`, `auto_classification` |

### `LEGAL_HOLD`

Litigation hold. When YES, all retention-driven archive and purge automation is suppressed regardless of RETENTION_CLASS. Set only by Legal.

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

### `ENCRYPTION_REQUIRED`

Declares that application-layer or client-side encryption is required in addition to Snowflake's transparent encryption at rest. Applies mainly to external stages and to columns holding secrets or key material.

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

### `DATA_QUALITY_TIER`

Certified quality level of the object. Set only by the data-quality pipeline after DMF results are evaluated; manual promotion requires an exception.

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

### `REFRESH_TYPE`

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

### `PROJECT_CODE`

Capital or programme project funding the workload. Enables project-level cost attribution separate from the steady-state COST_CENTER.

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


## Tier 3 — Optional / Domain

### `CAPABILITY`

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

### `SOURCE_SYSTEM`

System of record from which the data originates. Supports lineage rooting.

| Property | Value |
|---|---|
| Category | business |
| Value source | `reference_data` |
| Reference set | `REF_APPLICATION` |
| Format | `^APP-[0-9]{4,8}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | DOMAIN_COUNCIL |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `SCHEMA`, `TABLE`, `VIEW`, `EXTERNAL_TABLE`, `ICEBERG_TABLE`, `STAGE`, `PIPE`, `STREAM` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `lineage`, `impact_analysis`, `discovery` |

### `DATA_RESIDENCY`

ISO-3166 region in which the data must remain. Drives replication and cross-region share eligibility checks.

| Property | Value |
|---|---|
| Category | compliance |
| Value source | `controlled_vocabulary` |
| Allowed values | `GLOBAL`, `US`, `EU`, `UK`, `APAC`, `CANADA`, `LATAM`, `CHINA`, `INDIA`, `JAPAN`, `AUSTRALIA` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | COMPLIANCE_OFFICE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `ICEBERG_TABLE`, `EXTERNAL_TABLE`, `STAGE`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `residency_control`, `replication_control`, `sharing_control`, `compliance_reporting` |

### `SENSITIVE_DATA`

Special-category / sensitive data beyond PII (e.g. biometric, union membership, religion, sexual orientation) per GDPR Art. 9.

| Property | Value |
|---|---|
| Category | privacy |
| Value source | `controlled_vocabulary` |
| Allowed values | `YES`, `NO` |
| Severity order | `NO` ‹ `YES` |
| Inheritance | `inherit` |
| Override rule | `more_restrictive_only` |
| Owner | PRIVACY_OFFICE |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `TABLE`, `VIEW`, `COLUMN` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `dynamic_masking`, `privacy_reporting`, `gdpr_ccpa_evidence` |

### `PROGRAM`

Multi-project programme rollup for executive cost reporting.

| Property | Value |
|---|---|
| Category | financial |
| Value source | `reference_data` |
| Reference set | `REF_PROJECT` |
| Format | `^PRG-[A-Z0-9]{2,4}-[0-9]{3,6}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | FINANCE_FINOPS |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `WAREHOUSE`, `TASK`, `PIPE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `finops_chargeback`, `project_reporting` |

### `PRODUCT_CODE`

Commercial product/SKU whose P&L the workload supports.

| Property | Value |
|---|---|
| Category | financial |
| Value source | `reference_data` |
| Reference set | `REF_PRODUCT` |
| Format | `^[A-Z0-9][A-Z0-9_]{1,62}$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | FINANCE_FINOPS |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `WAREHOUSE`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `finops_chargeback`, `product_pnl` |

### `PRODUCT_OWNER`

Commercial owner of the PRODUCT_CODE. Distinct from DATA_PRODUCT_OWNER.

| Property | Value |
|---|---|
| Category | ownership |
| Value source | `free_text` |
| Format | `^(?:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|GRP-[A-Z0-9-]{3,48})$` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | FINANCE_FINOPS |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `product_pnl`, `access_approval` |

### `RPO`

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

### `RTO`

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

### `SHARING_SCOPE`

Maximum permitted distribution of the object. Checked before any listing, share or reader-account grant is created.

| Property | Value |
|---|---|
| Category | security |
| Value source | `controlled_vocabulary` |
| Allowed values | `INTERNAL_ONLY`, `AFFILIATE`, `PARTNER`, `PUBLIC_MARKETPLACE`, `PROHIBITED` |
| Severity order | `PROHIBITED` ‹ `INTERNAL_ONLY` ‹ `AFFILIATE` ‹ `PARTNER` ‹ `PUBLIC_MARKETPLACE` |
| Inheritance | `inherit` |
| Override rule | `any` |
| Owner | CISO_DATA_SECURITY |
| Version | 1.0.0 (ACTIVE) |
| Applies to | `DATABASE`, `SCHEMA`, `TABLE`, `VIEW`, `DYNAMIC_TABLE`, `ICEBERG_TABLE`, `SHARE` |
| Mandatory on | _nothing — conditional or advisory only_ |
| Consumed by | `sharing_control`, `export_control`, `compliance_reporting` |

### `COST_ALLOCATION_MODEL`

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


## Conditional mandates

Tags that become mandatory only when a predicate over other *effective* tag values holds.

| Rule | Severity | When | Then mandatory | On |
|---|---|---|---|---|
| **CR-001** | HIGH | `REGULATION` ∈ ['HIPAA', 'MULTI'] | `PHI` | `TABLE`, `VIEW`, `COLUMN` |
| | | _HIPAA-regulated objects must declare PHI status at column level._ | | |
| **CR-002** | CRITICAL | `REGULATION` ∈ ['PCI_DSS', 'MULTI'] | `PCI` | `TABLE`, `VIEW`, `COLUMN` |
| | | _PCI-DSS-regulated objects must declare PCI status at column level._ | | |
| **CR-003** | HIGH | `DATA_CLASSIFICATION` ∈ ['RESTRICTED', 'HIGHLY_RESTRICTED'] | `ROW_ACCESS_REQUIRED` | `TABLE`, `VIEW`, `MATERIALIZED_VIEW`, `DYNAMIC_TABLE` |
| | | _RESTRICTED and HIGHLY_RESTRICTED data must declare row-level access intent._ | | |
| **CR-004** | CRITICAL | `PII` ∈ ['YES'] | `MASKING_REQUIRED` | `COLUMN` |
| | | _PII columns must declare masking intent._ | | |
| **CR-005** | HIGH | `REGULATION` ∈ ['GDPR', 'CCPA', 'LGPD', 'MULTI'] | `DATA_RESIDENCY` | `DATABASE`, `SCHEMA`, `SHARE` |
| | | _Objects subject to GDPR/CCPA/LGPD must declare data residency so replication and cross-region sharing can be evaluated._ | | |
| **CR-006** | MEDIUM | `CRITICALITY` ∈ ['CRITICAL'] | `RPO`, `RTO` | `DATABASE`, `SCHEMA`, `TABLE` |
| | | _CRITICAL objects must publish RPO and RTO for DR planning._ | | |
| **CR-007** | CRITICAL | _always_ | `SHARING_SCOPE`, `DATA_CLASSIFICATION`, `DATA_PRODUCT_OWNER` | `SHARE` |
| | | _Anything leaving the account must declare its permitted distribution._ | | |
| **CR-008** | MEDIUM | `COST_ALLOCATION_MODEL` ∈ ['CHARGEBACK'] | `COST_CENTER` | `WAREHOUSE`, `DATABASE` |
| | | _Project-funded workloads must carry the funding programme._ | | |

## Regulation precedence

`REGULATION` holds a single governing regime. Where several apply, the earliest in this order wins and the tag is set to `MULTI`, with the full set recorded in `CONTROL.REGULATORY_SCOPE`.

`HIPAA` → `PCI_DSS` → `GLBA` → `SOX` → `GDPR` → `LGPD` → `PIPEDA` → `PDPA` → `CCPA` → `FERPA` → `NONE`
