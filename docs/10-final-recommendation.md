# 10. Final Enterprise Recommendation

## 10.1 Tier 1 — Core Mandatory (17)

Non-negotiable enterprise-wide. Blocks promotion to production.

| # | Tag | Mandatory on | Drives |
|---|---|---|---|
| 1 | `BUSINESS_UNIT` | database, warehouse | Chargeback, access boundary, jurisdiction |
| 2 | `DOMAIN` | database, schema | Mesh governance, discovery, showback |
| 3 | `DATA_PRODUCT` | schema, share | Mesh publication, lineage, SLA |
| 4 | `DATA_OWNER` | database, schema | Access approval, attestation |
| 5 | `DATA_STEWARD` | schema | Stewardship routing, remediation |
| 6 | `SUPPORT_GROUP` | database, task, pipe | Incident routing |
| 7 | `DATA_CLASSIFICATION` | database, schema, table, view, stage, share | **Masking attachment**, sharing, export control |
| 8 | `PII` | table, view, column, share | Masking branch, DSAR, privacy reporting |
| 9 | `ENVIRONMENT` | database, warehouse | Policy selection, promotion gate, chargeback |
| 10 | `DATA_LIFECYCLE` | schema, table, view | Retirement automation, cost avoidance |
| 11 | `CRITICALITY` | database, schema | DR scope, change control, incident severity |
| 12 | `COST_CENTER` | database, warehouse | Chargeback, budget enforcement |
| 13 | `RETENTION_CLASS` | schema, table, stage | Retention and purge automation |
| 14 | `REGULATION` | schema, table, share | Compliance reporting, residency, policy selection |
| 15 | `MASKING_REQUIRED` | column | Control attestation, drift detection |
| 16 | `ROW_ACCESS_REQUIRED` | table, view | Row access reconciliation |
| 17 | `SLA_TIER` | schema, task, pipe | SLA management, alert routing, DR tiering |

Fifteen of these are the set named in the original brief. Two were added, each for
a specific operational reason:

- **`SUPPORT_GROUP`** — without it, every governance finding routes to a central
  inbox and ages there. It is also the tag with the strongest natural feedback
  loop: a wrong value is discovered at 3 a.m. on the first incident, which makes
  it the most reliably accurate tag in the estate.
- **`DATA_LIFECYCLE`** — retention and cost automation cannot distinguish an
  active dataset from a deprecated one without it, and deprecated data nobody
  deleted is consistently one of the largest recoverable line items in a mature
  estate.

## 10.2 Tier 2 — Governance (14)

Mandatory when a condition holds, otherwise recommended.

| Tag | Becomes mandatory when |
|---|---|
| `PHI` | `REGULATION ∈ {HIPAA, MULTI}` (CR-001) |
| `PCI` | `REGULATION ∈ {PCI_DSS, MULTI}` (CR-002) |
| `LEGAL_HOLD` | Legal issues a hold; overrides all retention |
| `ENCRYPTION_REQUIRED` | External stage or key material |
| `DATA_QUALITY_TIER` | A data product publishes a quality commitment |
| `DATA_PRODUCT_OWNER` | Always on `SHARE` (CR-007) |
| `DATA_PRODUCT_TYPE` | Data product registration |
| `DOMAIN_OWNER` | Domain registration |
| `SUB_DOMAIN` | Domain exceeds ~20 data products |
| `APPLICATION` | Object is produced or consumed by a CMDB application |
| `APPLICATION_OWNER` | `APPLICATION` is set |
| `PLATFORM_OWNER` | Always on warehouse and integration |
| `REFRESH_TYPE` | Object has freshness monitoring |
| `PROJECT_CODE` | Project-funded workload |

## 10.3 Tier 3 — Optional / Domain (11)

`CAPABILITY` · `SOURCE_SYSTEM` · `DATA_RESIDENCY` · `SENSITIVE_DATA` · `PROGRAM` ·
`PRODUCT_CODE` · `PRODUCT_OWNER` · `RPO` · `RTO` · `SHARING_SCOPE` ·
`COST_ALLOCATION_MODEL`

Never enterprise-mandatory. A domain may make one locally mandatory via
`CONTROL.DOMAIN_TAG_POLICY`, which can only tighten the enterprise standard, never
relax it. Three become conditionally mandatory through rules CR-005, CR-006 and
CR-007.

## 10.4 Tag hierarchy

```
                        ┌──────────────────────┐
                        │    ENTERPRISE TAG    │
                        │      TAXONOMY        │
                        │      42 tags         │
                        └───────────┬──────────┘
            ┌───────────────────────┼───────────────────────┐
            ▼                       ▼                       ▼
    ┌───────────────┐      ┌────────────────┐     ┌─────────────────┐
    │    TIER 1     │      │     TIER 2     │     │     TIER 3      │
    │  17 · always  │      │ 14 · condition │     │ 11 · domain     │
    └───────┬───────┘      └────────┬───────┘     └────────┬────────┘
            │                       │                      │
   ┌────────┴────────┬──────────────┴───────┬──────────────┴────────┐
   ▼                 ▼                      ▼                       ▼
┌──────────┐  ┌──────────────┐   ┌──────────────────┐  ┌──────────────────┐
│ IDENTITY │  │  PROTECTION  │   │   OBLIGATION     │  │   ECONOMICS      │
│          │  │              │   │                  │  │                  │
│BUSINESS_ │  │DATA_CLASSIF- │   │REGULATION        │  │COST_CENTER       │
│  UNIT    │  │  ICATION ★   │   │RETENTION_CLASS   │  │PROJECT_CODE      │
│DOMAIN    │  │PII·PHI·PCI   │   │LEGAL_HOLD        │  │PROGRAM           │
│DATA_     │  │SENSITIVE_DATA│   │DATA_RESIDENCY    │  │PRODUCT_CODE      │
│ PRODUCT  │  │MASKING_REQ   │   │SLA_TIER          │  │COST_ALLOCATION_  │
│APPLICATION│ │ROW_ACCESS_REQ│   │RPO · RTO         │  │  MODEL           │
│CAPABILITY│  │ENCRYPTION_REQ│   │DATA_LIFECYCLE    │  │                  │
│SOURCE_SYS│  │SHARING_SCOPE │   │CRITICALITY       │  │                  │
└──────────┘  └──────────────┘   └──────────────────┘  └──────────────────┘
      │              │                     │                    │
      └──────────────┴──────────┬──────────┴────────────────────┘
                                ▼
                    ┌───────────────────────┐
                    │     ACCOUNTABILITY    │
                    │  DATA_OWNER           │
                    │  DATA_STEWARD         │
                    │  DATA_PRODUCT_OWNER   │
                    │  DOMAIN_OWNER         │
                    │  APPLICATION_OWNER    │
                    │  PLATFORM_OWNER       │
                    │  SUPPORT_GROUP        │
                    └───────────────────────┘

  ★ DATA_CLASSIFICATION is the only tag carrying masking policy attachments.
    Every other protection tag is read inside the policy body (§5.2).
```

## 10.5 Example tag definitions

```sql
-- Controlled vocabulary, ordinal, drives masking.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_CLASSIFICATION
    ALLOWED_VALUES 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL',
                   'RESTRICTED', 'HIGHLY_RESTRICTED'
    COMMENT = 'Enterprise confidentiality level. The primary driver of masking, '
           || 'sharing eligibility and export controls. Most restrictive value '
           || 'in the lineage wins.';

-- Reference data: no ALLOWED_VALUES, validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.COST_CENTER
    COMMENT = 'GL cost centre charged for the compute and storage attributed to '
           || 'the object. Must exist and be open in the ERP chart of accounts.';

-- Free text with a format contract.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_OWNER
    COMMENT = 'Accountable business owner (RACI A) for the data. Named individual '
           || 'or enterprise group.';
```

Full generated DDL: [`sql/_generated/10_tag_ddl.sql`](../sql/_generated/10_tag_ddl.sql).

## 10.6 End-to-end worked example

Onboarding a data product, `CUSTOMER_360`, in the `CUSTOMER` domain.

```sql
USE ROLE TAG_STEWARD;
USE WAREHOUSE GOVERNANCE_WH;

-- ── 1. Database: identity, economics, operations ─────────────────────────
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'DATABASE', 'CUSTOMER_PROD', NULL, 'BUSINESS_UNIT', 'RETAIL_BANKING',
    'Data product onboarding CUSTOMER_360', 'CHG-88213', 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'DATABASE', 'CUSTOMER_PROD', NULL, 'ENVIRONMENT', 'PROD',
    'Data product onboarding CUSTOMER_360', 'CHG-88213', 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'DATABASE', 'CUSTOMER_PROD', NULL, 'COST_CENTER', 'CC-004120',
    'Data product onboarding CUSTOMER_360', 'CHG-88213', 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'DATABASE', 'CUSTOMER_PROD', NULL, 'DATA_CLASSIFICATION', 'CONFIDENTIAL',
    'Baseline for the database; individual objects may escalate', 'CHG-88213', 'CICD');
-- … DOMAIN, SUPPORT_GROUP, DATA_OWNER, CRITICALITY

-- ── 2. Schema = the data product boundary ────────────────────────────────
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'SCHEMA', 'CUSTOMER_PROD.C360', NULL, 'DATA_PRODUCT', 'CUSTOMER_360',
    'Data product onboarding', 'CHG-88213', 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'SCHEMA', 'CUSTOMER_PROD.C360', NULL, 'REGULATION', 'GDPR',
    'EU customer master data', 'CHG-88213', 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'SCHEMA', 'CUSTOMER_PROD.C360', NULL, 'RETENTION_CLASS', 'EXTENDED_7Y',
    'Retention schedule RS-114', 'CHG-88213', 'CICD');
-- … DATA_STEWARD, SLA_TIER, DATA_LIFECYCLE

-- ── 3. Table: escalate classification, declare PII and row access ────────
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'TABLE', 'CUSTOMER_PROD.C360.CUSTOMER_MASTER', NULL,
    'DATA_CLASSIFICATION', 'RESTRICTED',
    'Contains full customer identity set', 'CHG-88213', 'CICD');
--   ↑ accepted: RESTRICTED is more restrictive than the inherited CONFIDENTIAL.
--     The reverse would be rejected by SP_APPLY_TAG.

CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'TABLE', 'CUSTOMER_PROD.C360.CUSTOMER_MASTER', NULL, 'PII', 'YES',
    'Customer identity data', 'CHG-88213', 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'TABLE', 'CUSTOMER_PROD.C360.CUSTOMER_MASTER', NULL,
    'ROW_ACCESS_REQUIRED', 'YES',
    'CR-003: RESTRICTED data requires row scoping', 'CHG-88213', 'CICD');

-- ── 4. Column: the enforcement point ─────────────────────────────────────
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'COLUMN', 'CUSTOMER_PROD.C360.CUSTOMER_MASTER', 'EMAIL_ADDRESS',
    'PII', 'YES', 'Direct identifier', 'CHG-88213', 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG(
    'COLUMN', 'CUSTOMER_PROD.C360.CUSTOMER_MASTER', 'EMAIL_ADDRESS',
    'MASKING_REQUIRED', 'YES', 'CR-004', 'CHG-88213', 'CICD');
```

What happens without any further action:

| | |
|---|---|
| **Immediately** | `EMAIL_ADDRESS` is masked. `MP_ENTERPRISE_STRING` is attached to `DATA_CLASSIFICATION`, which the table carries, so lineage puts the policy on every `STRING` column; the body reads `PII = YES` and returns `***MASKED***` — or `PID#<hash>` for `PSEUDONYM_ANALYST`. |
| **Within 15 min** | `RAP_BUSINESS_UNIT_SCOPE` is applied by `TASK_APPLY_ROW_ACCESS`. |
| **Within 24 h** | The classifier proposes `PII` on any column the steward missed; the scan confirms Tier 1 coverage. |
| **Next month** | The product's compute and storage appear against `CC-004120` in `VW_CHARGEBACK_MONTHLY`. |
| **Continuously** | `VW_DATA_PRODUCT_CATALOG` publishes it to consumers; `VW_COMPLIANCE_EVIDENCE` reports `CONTROLS ALIGNED`. |

Roughly twenty assignments — most at database and schema level, reused by every
future table — protect the whole product.

## 10.7 Why this design

| Choice | Alternative rejected | Reason |
|---|---|---|
| 17 mandatory tags | 8 (too thin) / 30 (unadoptable) | Covers security, privacy, finance, ownership and operations with ~6 direct assignments per table |
| One tag carries masking | A policy per privacy tag | Removes ambiguous resolution when a column carries several signals (§5.2) |
| Most-restrictive-wins for controls | Uniform nearest-wins | Prevents the most common way tag-based masking is defeated (AP-09) |
| Governing value + scope table | Boolean tag per regime | Bounds tag growth while keeping automation deterministic (§2.3) |
| Reconciliation task for row access | Claiming tags drive row policies | Snowflake has no such mechanism; the gap is stated and measured (§5.3) |
| Generated SQL from YAML | Hand-maintained DDL | Published matrix and deployed tags cannot diverge (AP-10) |
| `SP_APPLY_TAG` over raw grants | `APPLY TAG` to all stewards | `APPLY TAG` cannot be scoped below the account (AP-12) |
| Time-boxed exceptions only | Permanent waivers | A permanent exception is a standard that was wrong (AP-11) |
