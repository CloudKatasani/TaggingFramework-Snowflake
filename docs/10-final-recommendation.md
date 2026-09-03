# 10. Final Enterprise Recommendation

## 10.1 Tier 1 — The published allocation hierarchy (10)

These are exactly the tags named in the enterprise FinOps Tagging Strategy,
applied at every resource across AWS, Snowflake, Denodo and Collibra. Untagged
production resources are blocked at CI/CD.

| # | Tag | Level | Mandatory | Mandatory on | Drives |
|---|---|---|---|---|---|
| 1 | `operating_company` | Operating Company | Yes | database, warehouse | Chargeback, consolidation, jurisdiction |
| 2 | `department` | Department | Yes | database, warehouse | Departmental cost reports, budgets |
| 3 | `domain` | Data Domain | Yes | database, schema | Mesh governance, discovery, row scoping |
| 4 | `team` | Team | Yes | database, schema, warehouse, task, pipe | Incident routing, stewardship |
| 5 | `application` | Application | Yes | schema, warehouse, task, pipe | CMDB reconciliation, impact analysis |
| 6 | `workload_type` | Role / Workload Class | Yes | warehouse, task, pipe | Right-sizing, workload analytics |
| 7 | `owner_user` | Owner / User | **Recommended** | — | Incident routing, accountability |
| 8 | `environment` | Environment | Yes | database, warehouse | Policy selection, promotion gate |
| 9 | `data_classification_enterprise` | Data Classification | Yes | database, schema, table, view, stage, share | **Masking attachment**, sharing control |
| 10 | `data_classification_regulatory` | Data Classification | Yes | schema, table, view, column, stage, share | Masking branch, DSAR, PCI scoping |

`owner_user` is Recommended in the standard, so it is Recommended here. The
repository is never stricter than the published standard, and
`test_mandatory_column_matches_the_published_standard` asserts it.

## 10.2 Tier 2 — Governance (15)

Not part of the published hierarchy, but each is consumed by an automated control
the hierarchy alone cannot drive.

| Tag | Becomes mandatory when |
|---|---|
| `data_owner` | Regulated data (CR-004); always on `SHARE` (CR-007) |
| `retention_class` | Regulated data (CR-004) — without it no purge can run |
| `masking_required` | Any regulated column (CR-001) |
| `row_access_required` | `data_classification_enterprise = RESTRICTED` (CR-003) |
| `data_residency` | `SPII`, `PHI` or `PCI` (CR-005) |
| `support_group`, `sla_tier` | `environment = PRD` (CR-008) |
| `cost_center` | `cost_allocation_model = CHARGEBACK` (CR-009) |
| `data_product` | Always on `SHARE` (CR-007) |
| `legal_hold` | Legal issues a hold; overrides all retention |
| `regulation` | The regime, as distinct from the data category |
| `criticality` | Drives DR scope and incident severity |
| `data_lifecycle` | Drives retirement and cost avoidance |
| `data_steward` | Stewardship routing |
| `data_quality_tier` | Set by the quality pipeline, never asserted |

## 10.3 Tier 3 — Optional / Domain (15)

`sub_domain` · `source_system` · `application_owner` · `platform_owner` ·
`domain_owner` · `data_product_owner` · `data_product_type` · `capability` ·
`project_code` · `cost_allocation_model` · `encryption_required` ·
`sharing_scope` · `refresh_type` · `rpo` · `rto`

Never enterprise-mandatory. A domain or operating company may make one locally
mandatory via `CONTROL.DOMAIN_TAG_POLICY`, which can only tighten the enterprise
standard, never relax it. Four become conditionally mandatory through CR-002,
CR-005, CR-006, CR-007 and CR-009.

## 10.4 Tag hierarchy

```
                    ┌───────────────────────────────┐
                    │   ENTERPRISE TAG TAXONOMY     │
                    │          40 tags              │
                    └───────────────┬───────────────┘
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
┌────────────────┐        ┌──────────────────┐        ┌──────────────────┐
│    TIER 1      │        │     TIER 2       │        │     TIER 3       │
│ Allocation (10)│        │ Governance (15)  │        │  Domain (15)     │
└───────┬────────┘        └─────────┬────────┘        └─────────┬────────┘
        │                           │                           │
        ▼                           ▼                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ WHO PAYS            WHO OWNS           WHAT IT IS         WHAT IT COSTS │
│                                                                         │
│ operating_company   domain             data_classification_             │
│ department          team                 enterprise ★                   │
│ cost_center         application        data_classification_             │
│ project_code        owner_user           regulatory                     │
│ cost_allocation_    data_owner         regulation                       │
│   model             data_steward       retention_class                  │
│                     support_group      legal_hold                       │
│                     data_product       data_residency                   │
│                     domain_owner       sharing_scope                    │
│                                        masking_required                 │
│                                        row_access_required              │
│                                        encryption_required              │
│                                                                         │
│ HOW IT BEHAVES                          HOW GOOD IT IS                  │
│ environment · workload_type              data_quality_tier              │
│ criticality · data_lifecycle             sla_tier · refresh_type        │
│ rpo · rto                                                               │
└─────────────────────────────────────────────────────────────────────────┘

  ★ data_classification_enterprise is the ONLY tag carrying masking policy
    attachments. data_classification_regulatory is read inside the policy
    body - two attached tags would make the winning policy depend on lineage
    proximity rather than on which control is stronger (§5.2).
```

## 10.5 Example tag definitions

Canonical keys are lowercase; Snowflake folds unquoted identifiers to upper case,
so the deployed identifier is `OPERATING_COMPANY` while AWS, Denodo and Collibra
use `operating_company`. Both forms are carried in `CONTROL.TAG_CATALOG`
(§12.1).

```sql
-- Controlled vocabulary. Snowflake rejects anything outside the list at SET time.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.OPERATING_COMPANY
    ALLOWED_VALUES 'OPCO_AEP_OHIO', 'OPCO_AEP_TEXAS', 'OPCO_APPALACHIAN',
                   'OPCO_AEP_INDIANA_MICHIGAN', 'OPCO_KENTUCKY_POWER',
                   'OPCO_PSC_OKLAHOMA', 'OPCO_SEPC', 'SHARED'
    COMMENT = 'Top-level legal and financial entity for chargeback and '
           || 'consolidation.';

-- Ordinal vocabulary. The order is load-bearing: most-restrictive-wins
-- inheritance compares ORDINAL_POSITION, and the masking policy branches on it.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_CLASSIFICATION_REGULATORY
    ALLOWED_VALUES 'NONE', 'PII', 'SPII', 'PHI', 'PCI'
    COMMENT = 'Regulatory-driven data classification. Holds the governing '
           || 'category; the full set lives in CONTROL.REGULATORY_SCOPE.';

-- Reference data: no ALLOWED_VALUES, validated by SP_APPLY_TAG against
-- REF_TEAM so a disbanded team stops being a legal owner the day it dissolves.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.TEAM
    COMMENT = 'Engineering team accountable for build and run.';
```

Full generated DDL: [`sql/_generated/10_tag_ddl.sql`](../sql/_generated/10_tag_ddl.sql).

## 10.6 End-to-end worked example

Onboarding `dp-customer-360` for AEP Ohio. Full script:
[`examples/02_onboard_data_product.sql`](../examples/02_onboard_data_product.sql).

```sql
USE ROLE TAG_STEWARD;

-- 1. Database: the hierarchy down to team, plus a classification floor.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'OPERATING_COMPANY', 'OPCO_AEP_OHIO', 'Onboarding', 'CHG-88213', 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'DEPARTMENT', 'CUSTOMER', 'Onboarding', 'CHG-88213', 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'TEAM', 'team-customer-360', 'Onboarding', 'CHG-88213', 'CICD');
--  … domain, environment, data_classification_enterprise = CONFIDENTIAL

-- 2. Schema: application, data product, and the governance tags CR-004/008 need.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PRD.C360', NULL,
    'APPLICATION', 'app-cust360-api', 'Onboarding', 'CHG-88213', 'CICD');

-- 3. Warehouse: nothing is inherited - all six allocation tags set directly.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('WAREHOUSE', 'CUSTOMER_ANALYTICS_WH',
    NULL, 'WORKLOAD_TYPE', 'ANALYTICS', 'Onboarding', 'CHG-88213', 'CICD');

-- 4. Table: escalate to RESTRICTED - accepted, because it is MORE restrictive
--    than the inherited CONFIDENTIAL. The reverse is rejected.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('TABLE',
    'CUSTOMER_PRD.C360.CUSTOMER_MASTER', NULL,
    'DATA_CLASSIFICATION_ENTERPRISE', 'RESTRICTED',
    'Full customer identity set', 'CHG-88213', 'CICD');

-- 5. Columns: the enforcement point. SPII outranks PII, so SSN masks harder
--    than EMAIL_ADDRESS in the same table.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PRD.C360.CUSTOMER_MASTER', 'SSN',
    'DATA_CLASSIFICATION_REGULATORY', 'SPII', 'Sensitive identifier',
    'CHG-88213', 'CICD');
```

What happens without any further action:

| | |
|---|---|
| **Immediately** | Both columns are masked. `MP_ENTERPRISE_STRING` is attached to `DATA_CLASSIFICATION_ENTERPRISE`, which the table carries, so lineage puts the policy on every `STRING` column; the body reads the regulatory category and returns `PID#<hash>` for the email and `***SPII REDACTED***` for the SSN. |
| **Within 15 min** | `RAP_OPERATING_COMPANY_SCOPE` is applied by `TASK_APPLY_ROW_ACCESS`. Only OHIO_ANALYST and GROUP_REPORTING see rows. |
| **Within 24 h** | The classifier proposes a regulatory category on any column the steward missed; the scan confirms Tier 1 coverage and checks XR-001. |
| **Next month** | Compute and storage appear against `OPCO_AEP_OHIO` / `CUSTOMER` in `VW_CHARGEBACK_MONTHLY`, and against `ANALYTICS` in the workload rollup. |
| **Continuously** | `VW_COMPLIANCE_EVIDENCE` reports `CONTROLS ALIGNED`; the AWS side of the estate joins on the same keys (§12.4). |

Roughly twenty assignments — most at database and schema level, reused by every
future table — protect the whole product.

## 10.7 Why this design

| Choice | Alternative rejected | Reason |
|---|---|---|
| Tier 1 = the published standard, exactly | Adding "obviously useful" tags to Tier 1 | "Mandatory" means the same thing here as on the slide every team was shown; enforced by a test |
| `owner_user` Recommended, not Mandatory | Enforcing it anyway | The repository is never stricter than the standard; a mandated owner tag fills with stale names before JML feeds exist |
| Contradiction rules alongside conditional ones | Coverage metrics only | Two-tag classification makes `PCI` + `PUBLIC` possible, and it scores 100% on coverage while leaking (XR-001) |
| One tag carries masking | A policy on each classification tag | Removes ambiguous resolution when a column carries both (§5.2) |
| Most-restrictive-wins for controls | Uniform nearest-wins | Prevents the most common way tag-based masking is defeated (AP-09) |
| Governing value + scope table | A boolean tag per category | Bounds tag growth while keeping automation deterministic (§2.3) |
| Lowercase canonical keys | Upper case everywhere | AWS tag keys are case-sensitive; Snowflake folds. Both forms are stored so cross-platform joins actually match (§12.1) |
| Reconciliation task for row access | Claiming tags drive row policies | Snowflake has no such mechanism; the gap is stated and measured (§5.3) |
| Generated SQL from YAML | Hand-maintained DDL | Published matrix and deployed tags cannot diverge (AP-10) |
| `SP_APPLY_TAG` over raw grants | `APPLY TAG` to all stewards | `APPLY TAG` cannot be scoped below the account (AP-12) |
| Time-boxed exceptions only | Permanent waivers | A permanent exception is a standard that was wrong (AP-11) |
