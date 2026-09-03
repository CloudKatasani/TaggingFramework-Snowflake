# 3. Mandatory vs Recommended vs Optional

The matrix itself is generated:
**[`reference/requirement-matrix.md`](reference/requirement-matrix.md)**.
This page explains how to read it and why the levels fall where they do.

## 3.1 The five levels

| Level | Contract | Enforcement |
|---|---|---|
| **Mandatory** | The object is non-compliant without it | CI blocks promotion to production; nightly scan raises a finding |
| **Recommended** | Expected unless there is a specific reason not to | Reported in coverage metrics; never blocks |
| **Optional** | Available if useful | Not measured |
| **Inherited** | Satisfied by an ancestor; a direct assignment is an *override* | Governed by the tag's `override_rule` |
| **Not applicable** | Cannot be set on this object type | `SP_APPLY_TAG` refuses it |

**Inherited is the level that makes the framework viable.** `BUSINESS_UNIT` is
mandatory on a database and inherited by every schema, table, view and column
beneath it. One assignment covers ten thousand objects. Reading the matrix as if
`_i_` meant "also mandatory here" leads to the conclusion that the framework
demands seventeen tags per table, which it does not.

## 3.2 How a level is chosen

Four questions, in order.

**1. At what level is the fact first true?**
`BUSINESS_UNIT` is a property of a database. `DATA_PRODUCT` is a property of a
schema. `PII` is a property of a column. Mandate the tag where the fact becomes
knowable, and inherit everywhere below.

**2. Does something break if it is missing?**
`COST_CENTER` missing on a warehouse means the bill cannot be allocated — a
finance process fails. Mandatory. `CAPABILITY` missing means an architecture
report is less complete. Optional.

**3. Can it be derived?**
If automation can set it reliably, mandating it costs nothing to the team.
`ENVIRONMENT` is mandatory because CI/CD sets it from the deployment target.

**4. What is the cost of being wrong?**
A wrong `DATA_CLASSIFICATION` risks disclosure. A wrong `REFRESH_TYPE` risks a
misleading dashboard. The first is mandatory, the second recommended.

## 3.3 Conditional mandates

A flat matrix over-demands. `PHI` is essential for a hospital claims table and
meaningless for a logistics table — so making it universally mandatory produces
tens of thousands of objects tagged `PHI = NO`, which is pure noise that hides the
`YES` values.

Conditional rules make the demand follow the risk. All eight live in
[`config/tag_catalog.yaml`](../config/tag_catalog.yaml) and are evaluated against
**effective** (inheritance-resolved) values, so a rule triggered by a schema-level
`REGULATION` correctly reaches every table beneath it.

| Rule | When | Then mandatory | Severity |
|---|---|---|---|
| CR-001 | `REGULATION ∈ {HIPAA, MULTI}` | `PHI` | HIGH |
| CR-002 | `REGULATION ∈ {PCI_DSS, MULTI}` | `PCI` | CRITICAL |
| CR-003 | `DATA_CLASSIFICATION ∈ {RESTRICTED, HIGHLY_RESTRICTED}` | `ROW_ACCESS_REQUIRED` | HIGH |
| CR-004 | `PII = YES` | `MASKING_REQUIRED` | CRITICAL |
| CR-005 | `REGULATION ∈ {GDPR, CCPA, LGPD, MULTI}` | `DATA_RESIDENCY` | HIGH |
| CR-006 | `CRITICALITY = CRITICAL` | `RPO`, `RTO` | MEDIUM |
| CR-007 | *always*, on `SHARE` | `SHARING_SCOPE`, `DATA_CLASSIFICATION`, `DATA_PRODUCT_OWNER` | CRITICAL |
| CR-008 | `COST_ALLOCATION_MODEL = CHARGEBACK` | `COST_CENTER` | MEDIUM |

CR-007 is unconditional because a share is data leaving the account. There is no
version of that which should be possible without a named owner, a classification
and an explicit distribution scope.

The validator refuses a rule that makes a tag mandatory on an object type the tag
cannot be set on — an unenforceable rule generates findings nobody can ever close,
which is how teams learn to ignore the findings report.

## 3.4 Column-level scoping

The matrix says `PII` and `MASKING_REQUIRED` are mandatory on `COLUMN`. Taken
literally across a large estate that is hundreds of millions of decisions, and
demanding it would produce a backlog no organisation will ever clear — which
discredits the whole programme.

So the obligation is scoped. `VW_COLUMN_IN_SCOPE` limits column-level mandates to
columns in tables that already indicate regulated or sensitive content:

```sql
WHERE t.PII = 'YES'
   OR t.DATA_CLASSIFICATION IN ('RESTRICTED', 'HIGHLY_RESTRICTED')
   OR COALESCE(t.REGULATION, 'NONE') <> 'NONE'
```

Everything else is covered by inheritance from the table. The scoping is
deliberately **conservative in the risky direction**: a table declaring itself
regulated pulls all of its columns into scope, and the way to reduce that scope is
to correct the table's own tags, not to argue about a column.

## 3.5 What is deliberately not mandatory

Worth stating explicitly, because each was considered and rejected:

- **`DATA_QUALITY_TIER`** — certification must be earned from measurements, not
  asserted. Mandating it guarantees everything is declared `GOLD`.
- **`APPLICATION`** — depends on CMDB coverage the data platform does not control.
  Mandating a tag whose reference data is incomplete produces findings a steward
  cannot close.
- **`RPO`/`RTO`** — only meaningful for `CRITICALITY = CRITICAL` (CR-006).
- **`SUB_DOMAIN`** — most domains do not need one. Mandating it produces
  `SUB_DOMAIN = GENERAL` across the estate, which is a column of noise.
- **`PHI`/`PCI` universally** — see §3.3.

The common thread: **do not mandate a tag whose correct value is unknowable,
unverifiable or almost always the same.** Each produces a compliance number that
looks good and means nothing.
