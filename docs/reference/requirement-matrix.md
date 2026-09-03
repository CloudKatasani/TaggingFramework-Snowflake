<!-- GENERATED FILE - DO NOT EDIT. Source: config/tag_catalog.yaml. Rebuild with `make build`. -->


# Tag Requirement Matrix

Requirement level of every enterprise tag against the six object types that carry the bulk of the estate.

| Symbol | Meaning |
|---|---|
| **M** | Mandatory — the object is non-compliant without it. |
| R | Recommended — expected unless there is a reason not to. |
| O | Optional — available, never demanded. |
| _i_ | Inherited — satisfied by an ancestor; setting it directly is an override. |
| – | Not applicable — the tag cannot be set on this object type. |

> **Read the _i_ column carefully.** Most Tier 1 tags are mandatory on databases and schemas and merely *inherited* on tables and columns. That is the whole reason a 17-tag mandatory taxonomy costs a team roughly six direct assignments per table rather than seventeen.


## Tier 1 — Core Mandatory (17 tags)

| Tag | Database | Schema | Table | View | Column | Warehouse | Drives |
|---|---|---|---|---|---|---|---|
| `BUSINESS_UNIT` | **M** | _i_ | _i_ | _i_ | – | **M** | finops_chargeback, access_boundary, discovery, … |
| `DOMAIN` | **M** | **M** | _i_ | _i_ | – | _i_ | data_mesh, discovery, federated_governance, … |
| `DATA_PRODUCT` | – | **M** | _i_ | _i_ | – | – | data_mesh, discovery, lineage, … |
| `DATA_OWNER` | **M** | **M** | _i_ | _i_ | – | – | access_approval, incident_routing, attestation, … |
| `DATA_STEWARD` | _i_ | **M** | _i_ | _i_ | – | – | stewardship_workflow, attestation, remediation_routing |
| `SUPPORT_GROUP` | **M** | _i_ | _i_ | _i_ | – | _i_ | incident_routing, sla_management, operational_reporting |
| `DATA_CLASSIFICATION` | **M** | **M** | **M** | **M** | R | – | dynamic_masking, sharing_control, export_control, … |
| `PII` | _i_ | R | **M** | **M** | **M** | – | dynamic_masking, privacy_reporting, dsar_fulfilment, … |
| `ENVIRONMENT` | **M** | _i_ | – | – | – | **M** | policy_selection, finops_chargeback, promotion_gate, … |
| `DATA_LIFECYCLE` | _i_ | **M** | **M** | **M** | – | – | retirement_automation, consumer_notification, cost_avoidance, … |
| `CRITICALITY` | **M** | **M** | _i_ | _i_ | – | _i_ | dr_scope, monitoring_depth, change_control, … |
| `COST_CENTER` | **M** | _i_ | – | – | – | **M** | finops_chargeback, budget_enforcement, department_reporting |
| `RETENTION_CLASS` | _i_ | **M** | **M** | _i_ | – | – | retention_automation, purge_pipeline, compliance_reporting, … |
| `REGULATION` | _i_ | **M** | **M** | _i_ | O | – | compliance_reporting, residency_control, audit_evidence, … |
| `MASKING_REQUIRED` | – | – | R | R | **M** | – | dynamic_masking, control_attestation, drift_detection |
| `ROW_ACCESS_REQUIRED` | – | – | **M** | **M** | – | – | row_access_policy, control_attestation, drift_detection |
| `SLA_TIER` | – | **M** | _i_ | _i_ | – | – | sla_management, monitoring_depth, alert_routing, … |

## Tier 2 — Governance (14 tags)

| Tag | Database | Schema | Table | View | Column | Warehouse | Drives |
|---|---|---|---|---|---|---|---|
| `SUB_DOMAIN` | – | R | O | O | – | – | discovery, federated_governance, finops_showback |
| `APPLICATION` | O | R | O | O | – | – | impact_analysis, cmdb_reconciliation, incident_routing |
| `APPLICATION_OWNER` | O | O | – | – | – | – | impact_analysis, incident_routing, attestation |
| `PLATFORM_OWNER` | O | – | – | – | – | **M** | incident_routing, platform_attestation, finops_chargeback |
| `DOMAIN_OWNER` | R | O | – | – | – | – | data_mesh, federated_governance, access_approval |
| `DATA_PRODUCT_OWNER` | – | R | – | – | – | – | data_mesh, sla_management, consumer_contract, … |
| `DATA_PRODUCT_TYPE` | – | R | – | – | – | – | data_mesh, discovery, quality_expectation |
| `PHI` | – | O | O | O | R | – | dynamic_masking, hipaa_evidence, privacy_reporting, … |
| `PCI` | – | O | O | O | R | – | dynamic_masking, pci_scoping, audit_evidence, … |
| `LEGAL_HOLD` | O | O | O | O | – | – | purge_suppression, ediscovery, audit_evidence |
| `ENCRYPTION_REQUIRED` | – | – | O | – | O | – | encryption_control, audit_evidence, drift_detection |
| `DATA_QUALITY_TIER` | – | O | R | R | – | – | quality_reporting, consumer_contract, discovery, … |
| `REFRESH_TYPE` | – | – | R | O | – | – | freshness_monitoring, sla_management, lineage |
| `PROJECT_CODE` | O | O | – | – | – | O | finops_chargeback, project_reporting, capitalisation |

## Tier 3 — Optional / Domain (11 tags)

| Tag | Database | Schema | Table | View | Column | Warehouse | Drives |
|---|---|---|---|---|---|---|---|
| `CAPABILITY` | – | O | O | O | – | – | discovery, portfolio_analysis |
| `SOURCE_SYSTEM` | – | O | O | O | – | – | lineage, impact_analysis, discovery |
| `DATA_RESIDENCY` | O | O | O | O | – | – | residency_control, replication_control, sharing_control, … |
| `SENSITIVE_DATA` | – | – | O | O | R | – | dynamic_masking, privacy_reporting, gdpr_ccpa_evidence |
| `PROGRAM` | O | O | – | – | – | O | finops_chargeback, project_reporting |
| `PRODUCT_CODE` | O | O | – | – | – | O | finops_chargeback, product_pnl |
| `PRODUCT_OWNER` | O | O | – | – | – | – | product_pnl, access_approval |
| `RPO` | O | O | O | – | – | – | dr_scope, replication_control, sla_management |
| `RTO` | O | O | O | – | – | – | dr_scope, sla_management |
| `SHARING_SCOPE` | O | O | O | O | – | – | sharing_control, export_control, compliance_reporting |
| `COST_ALLOCATION_MODEL` | O | O | – | – | – | R | finops_chargeback, department_reporting |

## Mandatory load per object type

The count of tags a team must set *directly* on each object type. The framework budget is 12; Snowflake's hard ceiling is 50.

| Object type | Mandatory tags | Tags |
|---|---|---|
| `DATABASE` | 8 | `BUSINESS_UNIT`, `COST_CENTER`, `CRITICALITY`, `DATA_CLASSIFICATION`, `DATA_OWNER`, `DOMAIN`, `ENVIRONMENT`, `SUPPORT_GROUP` |
| `SCHEMA` | 10 | `CRITICALITY`, `DATA_CLASSIFICATION`, `DATA_LIFECYCLE`, `DATA_OWNER`, `DATA_PRODUCT`, `DATA_STEWARD`, `DOMAIN`, `REGULATION`, `RETENTION_CLASS`, `SLA_TIER` |
| `TABLE` | 6 | `DATA_CLASSIFICATION`, `DATA_LIFECYCLE`, `PII`, `REGULATION`, `RETENTION_CLASS`, `ROW_ACCESS_REQUIRED` |
| `VIEW` | 4 | `DATA_CLASSIFICATION`, `DATA_LIFECYCLE`, `PII`, `ROW_ACCESS_REQUIRED` |
| `COLUMN` | 2 | `MASKING_REQUIRED`, `PII` |
| `STAGE` | 2 | `DATA_CLASSIFICATION`, `RETENTION_CLASS` |
| `PIPE` | 2 | `SLA_TIER`, `SUPPORT_GROUP` |
| `TASK` | 2 | `SLA_TIER`, `SUPPORT_GROUP` |
| `WAREHOUSE` | 4 | `BUSINESS_UNIT`, `COST_CENTER`, `ENVIRONMENT`, `PLATFORM_OWNER` |
| `INTEGRATION` | 1 | `PLATFORM_OWNER` |
| `SHARE` | 5 | `DATA_CLASSIFICATION`, `DATA_PRODUCT`, `DATA_PRODUCT_OWNER`, `PII`, `REGULATION` |
