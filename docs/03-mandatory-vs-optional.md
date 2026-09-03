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

**Inherited is the level that makes the framework viable.** `operating_company` is
mandatory on a database and inherited by every schema, table, view and column
beneath it. One assignment covers ten thousand objects. Reading the matrix as if
`_i_` meant "also mandatory here" leads to the conclusion that the framework
demands seventeen tags per table, which it does not.

## 3.2 How a level is chosen

Four questions, in order.

**1. At what level is the fact first true?**
`operating_company` is a property of a database. `data_product` is a property of a
schema. `data_classification_regulatory` (PII) is a property of a column. Mandate the tag where the fact becomes
knowable, and inherit everywhere below.

**2. Does something break if it is missing?**
`cost_center` missing on a warehouse means the bill cannot be allocated — a
finance process fails. Mandatory. `capability` missing means an architecture
report is less complete. Optional.

**3. Can it be derived?**
If automation can set it reliably, mandating it costs nothing to the team.
`environment` is mandatory because CI/CD sets it from the deployment target.

**4. What is the cost of being wrong?**
A wrong `data_classification_enterprise` risks disclosure. A wrong `refresh_type` risks a
misleading dashboard. The first is mandatory, the second recommended.

## 3.3 Conditional mandates

A flat matrix over-demands. Retention class is essential for a customer master
and meaningless for a scratch staging table — making it universally mandatory
produces tens of thousands of objects tagged with a guess, which is noise that
hides the values that matter.

Conditional rules make the demand follow the risk. All nine live in
[`config/tag_catalog.yaml`](../config/tag_catalog.yaml) and are evaluated against
**effective** (inheritance-resolved) values, so a rule triggered by a
schema-level classification correctly reaches every table beneath it.

| Rule | When | Then mandatory | Severity |
|---|---|---|---|
| CR-001 | `data_classification_regulatory ∈ {PII, SPII, PHI, PCI}` | `masking_required` | CRITICAL |
| CR-002 | `data_classification_regulatory = PCI` | `encryption_required` | CRITICAL |
| CR-003 | `data_classification_enterprise = RESTRICTED` | `row_access_required` | HIGH |
| CR-004 | `data_classification_regulatory ∈ {PII, SPII, PHI, PCI}` | `data_owner`, `retention_class` | HIGH |
| CR-005 | `data_classification_regulatory ∈ {SPII, PHI, PCI}` | `data_residency` | HIGH |
| CR-006 | `criticality = CRITICAL` | `rpo`, `rto` | MEDIUM |
| CR-007 | *always*, on `SHARE` | `sharing_scope`, `data_classification_enterprise`, `data_owner`, `data_product` | CRITICAL |
| CR-008 | `environment = PRD` | `support_group`, `sla_tier` | MEDIUM |
| CR-009 | `cost_allocation_model = CHARGEBACK` | `cost_center` | MEDIUM |

Three worth explaining:

**CR-004** demands an owner and a retention class the moment data is regulated,
because without both, neither a subject access request nor a purge can actually
be executed. A DSAR that cannot find an accountable human is a regulatory finding
on its own.

**CR-007** is unconditional because a share is data leaving the account. There is
no version of that which should be possible without a named owner, a
classification and an explicit distribution scope.

**CR-008** exists because an unroutable production incident is a specific,
recurring failure. `environment = PRD` with no `support_group` means the 3 a.m.
page has nowhere to go.

The validator refuses a rule that makes a tag mandatory on an object type the tag
cannot be set on — an unenforceable rule generates findings nobody can close,
which is how teams learn to ignore the findings report.

## 3.3b Contradiction rules

Conditional mandates fire on a tag being **absent**. Contradiction rules fire on
two tags being **present and mutually impossible** — the more dangerous class,
because nothing looks missing and coverage metrics read as green.

| Rule | Cannot both be true | Severity |
|---|---|---|
| XR-001 | regulated data (`PII`…`PCI`) **and** `data_classification_enterprise ∈ {NONE, PUBLIC}` | CRITICAL |
| XR-002 | `RESTRICTED` **and** `sharing_scope ∈ {PARTNER, PUBLIC_MARKETPLACE}` | CRITICAL |
| XR-003 | `PCI` **and** `environment ∈ {TRAINING, DEV}` | CRITICAL |
| XR-004 | `data_lifecycle ∈ {DEPRECATED, ARCHIVED, PENDING_PURGE}` **and** a live SLA tier | MEDIUM |

**XR-001 is the most important single check in the framework.** Splitting
classification into an enterprise level and a regulatory category — as the
published standard does, correctly — creates the possibility of an object marked
`PCI` and `PUBLIC` at the same time. Both mandatory tags are present, so every
coverage metric reports 100%. Meanwhile the masking policy reads the *enterprise*
classification, sees `PUBLIC`, and returns cardholder data in clear.

Nothing about that state looks broken from the outside, which is exactly why it
needs a rule rather than a reviewer.

XR-003 is the PCI scoping equivalent: cardholder data in a TRAINING account is
outside the assessed cardholder data environment, and an assessor will treat its
presence there as a scope failure regardless of how it is masked.

## 3.4 Column-level scoping

The matrix says `data_classification_regulatory` is mandatory on `COLUMN`. Taken
literally across a large estate that is hundreds of millions of decisions, and
demanding it would produce a backlog no organisation will ever clear — which
discredits the whole programme.

So the obligation is scoped. `VW_COLUMN_IN_SCOPE` limits column-level mandates to
columns in tables that already indicate regulated or sensitive content:

```sql
WHERE t.PII = 'YES'
   OR t.DATA_CLASSIFICATION IN ('RESTRICTED', 'RESTRICTED')
   OR COALESCE(t.REGULATION, 'NONE') <> 'NONE'
```

Everything else is covered by inheritance from the table. The scoping is
deliberately **conservative in the risky direction**: a table declaring itself
regulated pulls all of its columns into scope, and the way to reduce that scope is
to correct the table's own tags, not to argue about a column.

## 3.5 What is deliberately not mandatory

Worth stating explicitly, because each was considered and rejected:

- **`data_quality_tier`** — certification must be earned from measurements, not
  asserted. Mandating it guarantees everything is declared `GOLD`.
- **`APPLICATION`** — depends on CMDB coverage the data platform does not control.
  Mandating a tag whose reference data is incomplete produces findings a steward
  cannot close.
- **`rpo`/`rto`** — only meaningful for `CRITICALITY = CRITICAL` (CR-006).
- **`sub_domain`** — most domains do not need one. Mandating it produces
  `SUB_DOMAIN = GENERAL` across the estate, which is a column of noise.
- **`data_classification_regulatory` (PHI)/`data_classification_regulatory` (PCI) universally** — see §3.3.

The common thread: **do not mandate a tag whose correct value is unknowable,
unverifiable or almost always the same.** Each produces a compliance number that
looks good and means nothing.
