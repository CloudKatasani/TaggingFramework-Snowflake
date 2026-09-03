# 2. Enterprise Tag Taxonomy

40 tags in three tiers, anchored on the ten-tag allocation hierarchy published in
the enterprise FinOps Tagging Strategy. The authoritative, always-current
definition is [`config/tag_catalog.yaml`](../config/tag_catalog.yaml); the
generated per-tag reference is
[`reference/tag-catalog.md`](reference/tag-catalog.md). This document explains
the *shape* of the taxonomy and the modelling decisions inside it.

## 2.1 Structure

```
                    ENTERPRISE TAG TAXONOMY (40)
                                │
   ┌────────────────────────────┼────────────────────────────┐
   ▼                            ▼                            ▼
┌──────────────────┐   ┌────────────────┐        ┌──────────────────┐
│     TIER 1       │   │    TIER 2      │        │     TIER 3       │
│ Allocation       │   │ Governance     │        │ Domain (15)      │
│ hierarchy (10)   │   │ (15)           │        │                  │
│                  │   │                │        │ Never enterprise │
│ THE published    │   │ Mandatory when │        │ mandatory. A     │
│ standard. Applied│   │ a condition    │        │ domain may make  │
│ at every resource│   │ holds, else    │        │ one locally      │
│ on all four      │   │ recommended.   │        │ mandatory - only │
│ platforms.       │   │                │        │ ever tightening. │
└──────────────────┘   └────────────────┘        └──────────────────┘
```

### The hierarchy, top-down

```
  operating_company    OPCO_AEP_OHIO         legal / financial entity
        │
        ▼
  department           CUSTOMER              budget owner
        │
        ▼
  domain               CUSTOMER              mesh governance unit
        │
        ▼
  team                 team-customer-360     accountable engineers
        │
        ▼
  application          app-cust360-api       CMDB-aligned system
        │
        ▼
  workload_type        ANALYTICS             resource-pattern rollup
        │
        ▼
  owner_user           abc.xyz@aep.com       accountable individual

  applied alongside, at every level:
      environment                      PRD | UAT | TST | DEV | TRAINING | BACKUP
      data_classification_enterprise   NONE ‹ PUBLIC ‹ INTERNAL ‹ CONFIDENTIAL ‹ RESTRICTED
      data_classification_regulatory   NONE ‹ PII ‹ SPII ‹ PHI ‹ PCI
```

Tier 1 **is** the published standard — no more, no less. That is enforced
mechanically: `validate_catalog.py` and `test_tier1_is_exactly_the_published_
hierarchy` both fail if a tag is promoted into Tier 1 without the standard being
updated too. Tier 1 is not a place to park a tag someone would like to be
important; it is a contract with every team that has been shown the slide.

The `hierarchy_requirement` field mirrors the standard's **Mandatory** column
exactly, which is why `owner_user` is Tier 1 and yet enforced only as
RECOMMENDED. The repository is never stricter than the published standard, and a
test asserts it.

### Why `department` and `domain` are separate

They look redundant and are not. `department` is the budget owner — who pays.
`domain` is the mesh governance unit — who decides what the data means. One
domain routinely serves several departments: CUSTOMER data is owned by the
Customer domain and consumed by Marketing, Distribution and Finance, each paying
for their own consumption. Collapsing them forces a choice between correct
chargeback and correct governance, and whichever you pick, the other is wrong.

The same applies to `team` and `application`: a team runs several applications,
and an application outlives the team that built it.

## 2.2 Categories
## 2.2 Categories

### Business (5 tags)
`operating_company` · `domain` · `data_product` · `sub_domain` · `APPLICATION`
(+ Tier 3 `capability`, `source_system`)

Answer *whose is this and what is it part of*. `operating_company` is the legal and
financial entity; `domain` is the mesh governance unit. They are deliberately
separate: a single domain such as CUSTOMER routinely serves several business
units, and collapsing them forces a choice between correct chargeback and correct
governance.

### Ownership (5 tags)
`data_owner` · `data_steward` · `support_group` · `application_owner` ·
`platform_owner` (+ `product_owner`)

Four accountabilities that are frequently four different people — see
[strategy §1.8](01-tagging-strategy.md#18-ownership-model). `support_group` is
Tier 1 because incident routing is the one governance metadata use case that is
exercised at 3 a.m., and a wrong value is discovered immediately. That feedback
loop makes it the most reliably accurate tag in the estate, which is a good
argument for putting more automation on top of it.

### Classification (1 tag)
`data_classification_enterprise` — `PUBLIC ‹ INTERNAL ‹ CONFIDENTIAL ‹ RESTRICTED ‹
RESTRICTED`

One tag, five ordered values, and the anchor of the entire security model: it is
the only tag that carries masking policy attachments. Five levels is a deliberate
count. Three cannot separate "commercially sensitive" from "regulated"; seven
produces boundary arguments that never resolve and inconsistent application
across domains.

### Privacy (5 tags)
`data_classification_regulatory` (PII) · `data_classification_regulatory` (PHI) · `data_classification_regulatory` (PCI) · `data_classification_regulatory` (SPII) (+ conditional use)

Separate from classification because they answer a different question.
Classification asks *how much damage does disclosure do*; privacy asks *whose
rights attach to it*. A customer email is CONFIDENTIAL and PII; an unreleased
earnings figure is RESTRICTED and not PII at all. Their obligations differ
completely — one needs DSAR fulfilment and erasure, the other needs insider-
trading controls.

### Compliance (4 tags)
`regulation` · `retention_class` · `legal_hold` · `data_residency`

`legal_hold` overrides `retention_class` unconditionally — the purge pipeline
checks it first, and no retention class can cause deletion while a hold is on.

### Security (4 tags)
`masking_required` · `row_access_required` · `encryption_required` ·
`sharing_scope`

These express **declared intent**, not enforcement. `MASKING_REQUIRED = YES` does
not mask anything; the tag-attached policy does. The gap between the two is the
most valuable signal in the framework, and `SP_DETECT_POLICY_DRIFT` exists to
find it. A control that is declared and not enforced is more dangerous than one
that was never declared, because it reports as green.

### Lifecycle (3 tags)
`environment` · `data_lifecycle` · `criticality`

`environment` has `override_rule: none` for a specific reason — see
[inheritance §4.6](04-inheritance-strategy.md#46-the-clone-problem).

### Financial (5 tags)
`cost_center` · `project_code` · `program` · `product_code` ·
`cost_allocation_model`

Only `cost_center` is Tier 1. Finance needs exactly one dimension that always
resolves; the others refine it. Making all five mandatory would produce four
mostly-empty tags and one that people fill in with `UNKNOWN`.

### Data quality (1 tag)
`data_quality_tier` — `BRONZE ‹ SILVER ‹ GOLD ‹ PLATINUM`

`inheritance: explicit_only`, unlike almost everything else. Quality is measured,
never assumed: a table in a GOLD schema is not GOLD until its own data metric
functions say so. Inheriting a certification would let one certified table launder
its status onto everything beside it.

### Operational (4 tags)
`sla_tier` · `refresh_type` · `rpo` · `rto`

### Data mesh (3 tags)
`domain_owner` · `data_product_owner` · `data_product_type`

## 2.3 Multi-valued attributes

**This is the hardest modelling problem in the whole taxonomy, and it lands
squarely on `data_classification_regulatory`.**

A Snowflake tag holds exactly one value per object. Reality does not comply: a
payments record is simultaneously PII and PCI; a claims table is PII and PHI.
There are three ways to model that, and the two obvious ones are both bad.

| Option | How | Why it fails |
|---|---|---|
| A boolean tag per category | `pii`, `spii`, `phi`, `pci`, … | Linear tag growth with no ceiling, each mandatory somewhere, each in the matrix and every report. This is how tag estates reach 400 tags. It is also what the published standard deliberately avoided by using one key. |
| A delimited value | `PII\|PCI` | `ALLOWED_VALUES` cannot validate combinations, so the vocabulary becomes free text. Every consumer must parse it, ordering variants (`PCI\|PII`) become distinct values, and Snowflake's own enforcement is lost. |
| **Governing value + scope table** ← chosen | the tag holds the most stringent category; `CONTROL.REGULATORY_SCOPE` holds the full set | Two places to look, and precedence must be defined and maintained. |

The third wins because it is the only one where **the tag drives the control
correctly**. Masking needs *one* answer, and the right one is the most stringent
category — satisfying PCI-DSS field handling also satisfies what a privacy regime
asks of the same column. Reporting needs *all* of them, which a relational table
gives you with a join.

Precedence, most prescriptive first:

```
PCI ▸ PHI ▸ SPII ▸ PII ▸ NONE
```

Ordered by how prescriptive the mandated technical control is, **not** by penalty
size. PCI-DSS dictates specific handling of specific fields. A privacy regime
mandates outcomes and leaves the mechanism open. If a column is both, satisfying
PCI satisfies the privacy obligation on that column; the reverse is not true.

`validate_catalog.py` enforces that every allowed value appears exactly once in
the precedence list — an unresolvable category is a silent gap in both masking
and compliance reporting.

The `regulation` tag (Tier 2) resolves the same way for regulatory *regimes*,
which are a different question: `data_classification_regulatory` says what the
data **is**; `regulation` says which law **applies**. A financial ledger with no
personal data at all is still in SOX scope.

### The state this design creates, and the check that catches it

Splitting classification across two tags introduces a failure mode worth naming:
an object can be tagged `data_classification_regulatory = PCI` and
`data_classification_enterprise = PUBLIC`. It scores as fully covered on every
coverage metric — both mandatory tags are present — while the masking policy,
which reads the enterprise classification, passes the data through in clear.

That is what the **contradiction rules** exist for (`XR-001`). They are the
mirror image of the conditional mandates: conditional rules fire on a tag being
*absent*, contradiction rules fire on two tags being *present and mutually
impossible*. The second is the more dangerous class, precisely because nothing
looks missing.

## 2.4 The number that decides adoption

Snowflake permits 10,000 tag keys per account and 50 tags per object. Neither is
the real constraint. The real constraint is that **every mandatory tag is a
question a human has to answer, multiplied by the number of objects**.

The framework's budget is 12 directly-set tags per object, checked in CI. The
actual figures:

| Object type | Mandatory (direct) | What they are |
|---|---|---|
| `DATABASE` | 6 | operating_company, department, domain, team, environment, classification |
| `WAREHOUSE` | 6 | the allocation hierarchy — nothing is inherited, a warehouse has no parent |
| `SCHEMA` | 5 | domain, team, application, both classifications |
| `SHARE` | 5 | both classifications, owner, product, regulation |
| `TASK` / `PIPE` | 3 | team, application, workload_type |
| `TABLE` / `VIEW` | 2 | both classifications |
| `COLUMN` | 1 | regulatory classification, and only on regulated tables |

A team onboarding a workload answers six questions once at the database, five at
the schema, six on each warehouse, and two per table. Everything else inherits.

**Warehouses are the expensive row in that table** and the one to watch: a
warehouse belongs to no database, so nothing is inherited and all six allocation
tags must be set directly. That is also exactly where unallocated spend comes
from, which is why `VW_UNALLOCATED_SPEND` names the missing keys per warehouse.

## 2.5 Snowflake system tags

Snowflake's classifier writes into `SNOWFLAKE.CORE`:

| System tag | Values | Relationship to this framework |
|---|---|---|
| `SNOWFLAKE.CORE.SEMANTIC_CATEGORY` | `EMAIL`, `PHONE_NUMBER`, `NAME`… | Input. Reconciled into `CLASSIFICATION_RECONCILIATION`. |
| `SNOWFLAKE.CORE.PRIVACY_CATEGORY` | `IDENTIFIER`, `QUASI_IDENTIFIER`, `SENSITIVE` | Input. Proposes `PII = YES`. |

They are **not** replacements for the enterprise tags, for one reason that
matters in an audit: nobody is accountable for them.
`data_classification_regulatory` is a decision with a named owner, a reason and
an audit trail. `PRIVACY_CATEGORY` is a probabilistic inference by a classifier
that has never seen the business context.

The mapping is deliberately conservative — the classifier proposes `PII`, or
`SPII` when it reports `SENSITIVE`, and never `PHI` or `PCI`. Those two carry
scoping consequences (HIPAA boundaries, the PCI cardholder data environment) that
a pattern match must not be allowed to assert on the enterprise's behalf.

The framework treats classifier output as a **proposal**, auto-applies it where no
human has ruled, and — importantly — never overwrites a considered human decision
on a later run. A framework whose nightly job silently reverts human judgement
teaches people to stop exercising it. See
[automation §6.4](06-automation-framework.md#64-classification-integration).
