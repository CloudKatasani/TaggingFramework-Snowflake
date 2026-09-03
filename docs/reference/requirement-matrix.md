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


## Tier 1 — Core Mandatory (10 tags)

| Tag | Database | Schema | Table | View | Column | Warehouse | Drives |
|---|---|---|---|---|---|---|---|
| `operating_company` | **M** | _i_ | _i_ | _i_ | – | **M** | finops_chargeback, finops_consolidation, access_boundary, … |
| `department` | **M** | _i_ | _i_ | _i_ | – | **M** | finops_chargeback, department_reporting, budget_enforcement, … |
| `domain` | **M** | **M** | _i_ | _i_ | – | _i_ | data_mesh, federated_governance, discovery, … |
| `team` | **M** | **M** | _i_ | _i_ | – | **M** | incident_routing, stewardship_workflow, finops_showback, … |
| `application` | _i_ | **M** | _i_ | _i_ | – | **M** | cmdb_reconciliation, impact_analysis, finops_chargeback, … |
| `workload_type` | – | R | _i_ | _i_ | – | **M** | finops_rightsizing, workload_analytics, capacity_planning, … |
| `owner_user` | R | R | O | O | – | R | incident_routing, access_approval, attestation, … |
| `environment` | **M** | _i_ | – | – | – | **M** | policy_selection, promotion_gate, finops_chargeback, … |
| `data_classification_enterprise` | **M** | **M** | **M** | **M** | R | – | dynamic_masking, sharing_control, export_control, … |
| `data_classification_regulatory` | _i_ | **M** | **M** | **M** | **M** | – | dynamic_masking, privacy_reporting, dsar_fulfilment, … |

## Tier 2 — Governance (15 tags)

| Tag | Database | Schema | Table | View | Column | Warehouse | Drives |
|---|---|---|---|---|---|---|---|
| `data_product` | – | R | _i_ | _i_ | – | – | data_mesh, discovery, lineage, … |
| `data_owner` | _i_ | R | _i_ | _i_ | – | – | access_approval, attestation, remediation_routing, … |
| `data_steward` | _i_ | R | _i_ | _i_ | – | – | stewardship_workflow, attestation, remediation_routing |
| `support_group` | _i_ | _i_ | _i_ | _i_ | – | _i_ | incident_routing, sla_management, operational_reporting |
| `cost_center` | R | _i_ | – | – | – | R | finops_chargeback, budget_enforcement, gl_posting |
| `criticality` | R | R | _i_ | _i_ | – | _i_ | dr_scope, monitoring_depth, change_control, … |
| `data_lifecycle` | _i_ | R | R | _i_ | – | – | retirement_automation, consumer_notification, cost_avoidance, … |
| `retention_class` | _i_ | R | _i_ | _i_ | – | – | retention_automation, purge_pipeline, compliance_reporting, … |
| `legal_hold` | O | O | O | O | – | – | purge_suppression, ediscovery, audit_evidence |
| `regulation` | _i_ | R | _i_ | _i_ | O | – | compliance_reporting, audit_evidence, policy_selection, … |
| `sla_tier` | – | _i_ | _i_ | _i_ | – | – | sla_management, monitoring_depth, alert_routing, … |
| `masking_required` | – | – | R | O | R | – | dynamic_masking, control_attestation, drift_detection |
| `row_access_required` | – | – | R | R | – | – | row_access_policy, control_attestation, drift_detection |
| `data_residency` | _i_ | _i_ | _i_ | _i_ | – | – | residency_control, replication_control, sharing_control, … |
| `data_quality_tier` | – | O | O | O | – | – | quality_reporting, consumer_contract, discovery, … |

## Tier 3 — Optional / Domain (15 tags)

| Tag | Database | Schema | Table | View | Column | Warehouse | Drives |
|---|---|---|---|---|---|---|---|
| `sub_domain` | – | O | O | O | – | – | discovery, federated_governance, finops_showback |
| `source_system` | – | O | O | O | – | – | lineage, impact_analysis, discovery |
| `application_owner` | O | O | – | – | – | – | impact_analysis, incident_routing, attestation |
| `platform_owner` | O | – | – | – | – | O | incident_routing, platform_attestation, finops_chargeback |
| `domain_owner` | O | O | – | – | – | – | data_mesh, federated_governance, access_approval |
| `data_product_owner` | – | O | – | – | – | – | data_mesh, sla_management, consumer_contract, … |
| `data_product_type` | – | O | – | – | – | – | data_mesh, discovery, quality_expectation |
| `capability` | – | O | O | O | – | – | discovery, portfolio_analysis |
| `project_code` | O | O | – | – | – | O | finops_chargeback, project_reporting, capitalisation |
| `cost_allocation_model` | O | O | – | – | – | R | finops_chargeback, department_reporting |
| `encryption_required` | – | – | O | – | O | – | encryption_control, audit_evidence, drift_detection |
| `sharing_scope` | O | O | O | O | – | – | sharing_control, export_control, compliance_reporting |
| `refresh_type` | – | – | O | O | – | – | freshness_monitoring, sla_management, lineage |
| `rpo` | O | O | O | – | – | – | dr_scope, replication_control, sla_management |
| `rto` | O | O | O | – | – | – | dr_scope, sla_management |

## Mandatory load per object type

The count of tags a team must set *directly* on each object type. The framework budget is 12; Snowflake's hard ceiling is 50.

| Object type | Mandatory tags | Tags |
|---|---|---|
| `DATABASE` | 6 | `data_classification_enterprise`, `department`, `domain`, `environment`, `operating_company`, `team` |
| `SCHEMA` | 5 | `application`, `data_classification_enterprise`, `data_classification_regulatory`, `domain`, `team` |
| `TABLE` | 2 | `data_classification_enterprise`, `data_classification_regulatory` |
| `VIEW` | 2 | `data_classification_enterprise`, `data_classification_regulatory` |
| `COLUMN` | 1 | `data_classification_regulatory` |
| `STAGE` | 2 | `data_classification_enterprise`, `data_classification_regulatory` |
| `PIPE` | 3 | `application`, `team`, `workload_type` |
| `TASK` | 3 | `application`, `team`, `workload_type` |
| `WAREHOUSE` | 6 | `application`, `department`, `environment`, `operating_company`, `team`, `workload_type` |
| `SHARE` | 5 | `data_classification_enterprise`, `data_classification_regulatory`, `data_owner`, `data_product`, `regulation` |
