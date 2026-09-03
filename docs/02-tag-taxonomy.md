# 2. Enterprise Tag Taxonomy

42 tags in three tiers. The authoritative, always-current definition is
[`config/tag_catalog.yaml`](../config/tag_catalog.yaml); the generated
per-tag reference is [`reference/tag-catalog.md`](reference/tag-catalog.md).
This document explains the *shape* of the taxonomy and the modelling decisions
inside it.

## 2.1 Structure

```
                        ENTERPRISE TAG TAXONOMY (42)
                                    │
      ┌─────────────────────────────┼─────────────────────────────┐
      ▼                             ▼                             ▼
┌───────────────┐          ┌────────────────┐          ┌──────────────────┐
│    TIER 1     │          │     TIER 2     │          │      TIER 3      │
│  Core (17)    │          │ Governance (14)│          │  Domain (11)     │
│               │          │                │          │                  │
│ Mandatory     │          │ Mandatory when │          │ Never enterprise │
│ enterprise-   │          │ a condition    │          │ mandatory; a     │
│ wide. Blocks  │          │ holds, else    │          │ domain may make  │
│ promotion to  │          │ recommended.   │          │ them locally     │
│ production.   │          │                │          │ mandatory.       │
└───────────────┘          └────────────────┘          └──────────────────┘
      │                             │                             │
      └─────────────────────────────┼─────────────────────────────┘
                                    ▼
                    ┌───────────────────────────────┐
                    │      TEN CATEGORIES           │
                    │  business · ownership         │
                    │  classification · privacy     │
                    │  compliance · security        │
                    │  lifecycle · financial        │
                    │  data_quality · operational   │
                    │  (+ data_mesh)                │
                    └───────────────────────────────┘
```

Tier is about **obligation**. Category is about **subject matter**. They are
independent: `PII` is Tier 1 privacy, `PHI` is Tier 2 privacy, `SENSITIVE_DATA`
is Tier 3 privacy — same subject, three different levels of enterprise demand.

## 2.2 Categories

### Business (5 tags)
`BUSINESS_UNIT` · `DOMAIN` · `DATA_PRODUCT` · `SUB_DOMAIN` · `APPLICATION`
(+ Tier 3 `CAPABILITY`, `SOURCE_SYSTEM`)

Answer *whose is this and what is it part of*. `BUSINESS_UNIT` is the legal and
financial entity; `DOMAIN` is the mesh governance unit. They are deliberately
separate: a single domain such as CUSTOMER routinely serves several business
units, and collapsing them forces a choice between correct chargeback and correct
governance.

### Ownership (5 tags)
`DATA_OWNER` · `DATA_STEWARD` · `SUPPORT_GROUP` · `APPLICATION_OWNER` ·
`PLATFORM_OWNER` (+ `PRODUCT_OWNER`)

Four accountabilities that are frequently four different people — see
[strategy §1.8](01-tagging-strategy.md#18-ownership-model). `SUPPORT_GROUP` is
Tier 1 because incident routing is the one governance metadata use case that is
exercised at 3 a.m., and a wrong value is discovered immediately. That feedback
loop makes it the most reliably accurate tag in the estate, which is a good
argument for putting more automation on top of it.

### Classification (1 tag)
`DATA_CLASSIFICATION` — `PUBLIC ‹ INTERNAL ‹ CONFIDENTIAL ‹ RESTRICTED ‹
HIGHLY_RESTRICTED`

One tag, five ordered values, and the anchor of the entire security model: it is
the only tag that carries masking policy attachments. Five levels is a deliberate
count. Three cannot separate "commercially sensitive" from "regulated"; seven
produces boundary arguments that never resolve and inconsistent application
across domains.

### Privacy (5 tags)
`PII` · `PHI` · `PCI` · `SENSITIVE_DATA` (+ conditional use)

Separate from classification because they answer a different question.
Classification asks *how much damage does disclosure do*; privacy asks *whose
rights attach to it*. A customer email is CONFIDENTIAL and PII; an unreleased
earnings figure is HIGHLY_RESTRICTED and not PII at all. Their obligations differ
completely — one needs DSAR fulfilment and erasure, the other needs insider-
trading controls.

### Compliance (4 tags)
`REGULATION` · `RETENTION_CLASS` · `LEGAL_HOLD` · `DATA_RESIDENCY`

`LEGAL_HOLD` overrides `RETENTION_CLASS` unconditionally — the purge pipeline
checks it first, and no retention class can cause deletion while a hold is on.

### Security (4 tags)
`MASKING_REQUIRED` · `ROW_ACCESS_REQUIRED` · `ENCRYPTION_REQUIRED` ·
`SHARING_SCOPE`

These express **declared intent**, not enforcement. `MASKING_REQUIRED = YES` does
not mask anything; the tag-attached policy does. The gap between the two is the
most valuable signal in the framework, and `SP_DETECT_POLICY_DRIFT` exists to
find it. A control that is declared and not enforced is more dangerous than one
that was never declared, because it reports as green.

### Lifecycle (3 tags)
`ENVIRONMENT` · `DATA_LIFECYCLE` · `CRITICALITY`

`ENVIRONMENT` has `override_rule: none` for a specific reason — see
[inheritance §4.6](04-inheritance-strategy.md#46-the-clone-problem).

### Financial (5 tags)
`COST_CENTER` · `PROJECT_CODE` · `PROGRAM` · `PRODUCT_CODE` ·
`COST_ALLOCATION_MODEL`

Only `COST_CENTER` is Tier 1. Finance needs exactly one dimension that always
resolves; the others refine it. Making all five mandatory would produce four
mostly-empty tags and one that people fill in with `UNKNOWN`.

### Data quality (1 tag)
`DATA_QUALITY_TIER` — `BRONZE ‹ SILVER ‹ GOLD ‹ PLATINUM`

`inheritance: explicit_only`, unlike almost everything else. Quality is measured,
never assumed: a table in a GOLD schema is not GOLD until its own data metric
functions say so. Inheriting a certification would let one certified table launder
its status onto everything beside it.

### Operational (4 tags)
`SLA_TIER` · `REFRESH_TYPE` · `RPO` · `RTO`

### Data mesh (3 tags)
`DOMAIN_OWNER` · `DATA_PRODUCT_OWNER` · `DATA_PRODUCT_TYPE`

## 2.3 Multi-valued attributes

**This is the single hardest modelling problem in Snowflake tagging, and most
frameworks get it wrong.**

A Snowflake tag holds exactly one value per object. Reality does not comply: a
payments table is simultaneously in scope for PCI-DSS, SOX and GDPR. There are
three ways to model that, and the two obvious ones are both bad.

| Option | How | Why it fails |
|---|---|---|
| A boolean tag per regime | `GDPR_DATA`, `CCPA_DATA`, `HIPAA_DATA`, `SOX_DATA`, `LGPD_DATA`… | Linear tag growth with no ceiling. Twelve regimes is twelve tags, each mandatory somewhere, each in the matrix, each in every report. This is how tag estates reach 400 tags. |
| A delimited value | `REGULATION = 'GDPR\|SOX\|PCI_DSS'` | `ALLOWED_VALUES` cannot validate combinations, so the vocabulary is effectively free text. Every consumer must parse. Ordering variants (`SOX\|GDPR`) become distinct values. Breaks the 256-char limit at the extreme. |
| **Governing value + scope table** ← chosen | `REGULATION` holds the single most stringent regime (or `MULTI`); `CONTROL.REGULATORY_SCOPE` holds the full set | Two places to look. Requires precedence to be defined and maintained. |

The third wins because it is the only one where **the tag drives automation
correctly**. Policy selection, masking strictness and residency checks all need
*one* answer — "which rules apply here" is answered by the strictest regime — and
reporting needs *all* of them, which a relational table gives you with a join.

Precedence, highest first:

```
HIPAA ▸ PCI_DSS ▸ GLBA ▸ SOX ▸ GDPR ▸ LGPD ▸ PIPEDA ▸ PDPA ▸ CCPA ▸ FERPA ▸ NONE
```

Ordered by how prescriptive the technical control requirement is, not by penalty
size. HIPAA and PCI-DSS mandate specific handling of specific fields; GDPR
mandates outcomes and leaves the mechanism open. If an object is governed by both,
satisfying HIPAA's field-level rules satisfies GDPR's data-minimisation
expectation, but not the reverse.

`validate_catalog.py` enforces that every allowed `REGULATION` value except
`MULTI` appears exactly once in the precedence list — an unresolvable regime is a
silent gap in compliance reporting.

The same pattern applies anywhere else a genuine multi-value need appears. It has
been used once, deliberately. A second use should prompt the question of whether
the estate is being modelled at the wrong grain.

## 2.4 Why 42 and not 400

Snowflake permits 10,000 tag keys per account and 50 tags per object. Neither is
the real constraint. The real constraint is that **every mandatory tag is a
question a human has to answer, multiplied by the number of objects**.

The framework's own budget is 12 directly-set tags per object, checked in CI. The
actual figures:

| Object type | Mandatory (direct) |
|---|---|
| `SCHEMA` | 10 |
| `DATABASE` | 8 |
| `TABLE` | 6 |
| `SHARE` | 5 |
| `WAREHOUSE` | 4 |
| `VIEW` | 4 |
| `COLUMN` | 2 |

A team onboarding a new data product answers ten questions once at the schema, six
per table, and two per column *only for columns in regulated tables*. Everything
else inherits. That is a workload a team will actually sustain — and it is the
number, not the tag count, that determines whether a framework is adopted.

## 2.5 Snowflake system tags

Snowflake's classifier writes into `SNOWFLAKE.CORE`:

| System tag | Values | Relationship to this framework |
|---|---|---|
| `SNOWFLAKE.CORE.SEMANTIC_CATEGORY` | `EMAIL`, `PHONE_NUMBER`, `NAME`… | Input. Reconciled into `CLASSIFICATION_RECONCILIATION`. |
| `SNOWFLAKE.CORE.PRIVACY_CATEGORY` | `IDENTIFIER`, `QUASI_IDENTIFIER`, `SENSITIVE` | Input. Proposes `PII = YES`. |

They are **not** replacements for the enterprise tags, for one reason that matters
in an audit: nobody is accountable for them. `PII` is a decision with a named
owner, a reason and an audit trail. `PRIVACY_CATEGORY` is a probabilistic
inference by a classifier that has never seen the business context.

The framework treats classifier output as a **proposal**, auto-applies it where no
human has ruled, and — importantly — never overwrites a considered human decision
on a later run. A framework whose nightly job silently reverts human judgement
teaches people to stop exercising it. See
[automation §6.4](06-automation-framework.md#64-classification-integration).
