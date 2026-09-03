# 5. Security and Compliance Integration

How tags become enforcement rather than description.

## 5.1 Architecture

```
   ┌──────────────────────────────────────────────────────────────────────┐
   │                          DECLARATION                                 │
   │  DATA_CLASSIFICATION · PII · PHI · PCI · SENSITIVE_DATA              │
   │  MASKING_REQUIRED · ROW_ACCESS_REQUIRED · SHARING_SCOPE              │
   └───────────────┬──────────────────────────────────┬───────────────────┘
                   │                                  │
        TAG ATTACHMENT (immediate)          RECONCILIATION (≤15 min)
                   │                                  │
                   ▼                                  ▼
   ┌───────────────────────────────┐   ┌──────────────────────────────────┐
   │  ALTER TAG DATA_CLASSIFICATION│   │  SP_APPLY_ROW_ACCESS_POLICIES    │
   │  SET MASKING POLICY MP_...    │   │  reads ROW_ACCESS_REQUIRED,      │
   │                               │   │  issues ALTER TABLE ADD ROW      │
   │  Propagates through lineage   │   │  ACCESS POLICY                   │
   │  to every column of matching  │   │                                  │
   │  data type, now and future    │   │  Needed because Snowflake has no │
   └───────────────┬───────────────┘   │  tag attachment for row policies │
                   │                   └──────────────┬───────────────────┘
                   ▼                                  ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │                          ENFORCEMENT                                 │
   │  MP_ENTERPRISE_{STRING,NUMBER,DATE,TIMESTAMP_NTZ,VARIANT}            │
   │  RAP_BUSINESS_UNIT_SCOPE · RAP_DOMAIN_SCOPE · RAP_DATA_RESIDENCY     │
   │  AGG_HIGHLY_RESTRICTED · PROJ_PCI_NO_OUTPUT                          │
   └───────────────┬──────────────────────────────────────────────────────┘
                   │
                   ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │                          ASSURANCE                                   │
   │  SP_DETECT_POLICY_DRIFT (hourly) · VW_COMPLIANCE_EVIDENCE            │
   │  ALERT_POLICY_DRIFT · TAG_CHANGE_LOG                                 │
   │  Declared ≠ enforced is itself a CRITICAL finding                    │
   └──────────────────────────────────────────────────────────────────────┘
```

The layer people skip is **assurance**. Declaration and enforcement are the
obvious parts; the failure mode that actually causes breaches is a control that
was enforced and quietly stopped being enforced, while every report stayed green.

## 5.2 Dynamic data masking

### One tag carries the attachments

`DATA_CLASSIFICATION` — and only `DATA_CLASSIFICATION` — has masking policies
attached to it. The policy body branches on `PII`, `PHI`, `PCI` and
`SENSITIVE_DATA` via `SYSTEM$GET_TAG_ON_CURRENT_COLUMN`.

This is the most important structural decision in the security model, and the
reasoning is worth being explicit about. Snowflake allows one masking policy per
data type per tag, and a column can only ever carry one masking policy. If `PII`,
`PHI`, `PCI` and `DATA_CLASSIFICATION` each had their own `STRING` policy, then a
column tagged both `PII = YES` and `DATA_CLASSIFICATION = RESTRICTED` would have
two candidate policies, and which one applied would depend on **tag-lineage
proximity rather than on which control is stronger**. That is an unacceptable
property for a privacy control — the answer to "is this column masked, and by
what rule" must not depend on the order somebody happened to tag things.

Binding a single tag gives:

- deterministic resolution, always;
- five policies instead of fifteen;
- a new privacy signal is a change to a policy body, not to the attachment graph;
- `DATA_CLASSIFICATION` is mandatory on every table and view, so lineage
  propagation reaches every column of a matching type in the estate.

`validate_catalog.py` enforces the invariant: more than one tag carrying masking
attachments fails the build, and any tag the policy body reads must be at least
`RECOMMENDED` on `COLUMN` — otherwise the branch silently never fires.

### Masking behaviour

| Signal | Privileged role | Analyst (`PSEUDONYM_ANALYST`) | Everyone else |
|---|---|---|---|
| `PCI = YES` | clear | last 4 digits | last 4 digits |
| `PHI = YES` | clear | `PHI#<sha256>` | `***PHI REDACTED***` |
| `SENSITIVE_DATA = YES` | clear (two roles required) | redacted | `***SPECIAL CATEGORY***` |
| `PII = YES` | clear | `PID#<sha256[:16]>` | `***MASKED***` |
| `HIGHLY_RESTRICTED` | clear | redacted | `***HIGHLY RESTRICTED***` |
| `RESTRICTED` | clear | redacted | `***RESTRICTED***` |

Three choices in there that are not cosmetic:

**Pseudonymisation, not redaction, for analysts.** `PID#<hash>` is deterministic,
so joins and cohort analysis still work while the value is no longer identifying.
A control that makes legitimate analysis impossible gets routed around — someone
extracts to a spreadsheet, and the data leaves the platform entirely. This is the
difference between a control that holds and one that is technically present.

**Numbers mask to `NULL`, never to `0`.** A masked `0` is indistinguishable from a
real `0` and corrupts every `SUM` and `AVG` built on the column. `NULL` propagates
honestly through aggregates.

**Dates generalise rather than null.** `DATE_TRUNC('YEAR', dob)` remains
analytically useful and is no longer a HIPAA Safe Harbor identifier for the great
majority of the population.

### Fail-closed

Every branch defaults to masked:

```sql
COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.DATA_CLASSIFICATION'),
         'RESTRICTED')   -- absent or unreadable tag ⇒ masked
```

An unclassified column is treated as `RESTRICTED`, not as `PUBLIC`.

### Role membership, not role equality

Policies use `IS_ROLE_IN_SESSION('PII_UNMASKED')`, never
`CURRENT_ROLE() = 'PII_UNMASKED'`. `CURRENT_ROLE()` compares one string and masks
data for every user who holds the entitlement *through* a business role or as a
secondary role — which is nearly all of them in a real RBAC hierarchy. The symptom
is "masking works but the wrong people are blocked", and the usual fix people
reach for is to grant the entitlement role directly to more users, which flattens
the hierarchy the RBAC model depends on.

### Environments

The same policy code deploys everywhere. Unmask roles are granted **only in
production**, so non-production is unmasked-by-nobody without a single environment
branch in any policy body. Fewer branches, nothing to misconfigure per account.

## 5.3 Row access policies

**Snowflake does not support attaching row access policies to tags.** Any design
claiming "tags drive row-level security" has to close that gap somewhere; this
framework closes it explicitly rather than implying a capability that does not
exist.

`SP_APPLY_ROW_ACCESS_POLICIES` reads `ROW_ACCESS_REQUIRED = YES` and issues the
`ALTER TABLE ... ADD ROW ACCESS POLICY` statements, every 15 minutes.

The honest consequence: **row access enforcement is eventually consistent**, while
masking is immediate on tag assignment. A table created, tagged and populated
between two task runs is unprotected for up to 15 minutes. Mitigations:

1. 15-minute cadence, not nightly;
2. CI/CD applies the policy in the same deployment that creates the table, so
   anything shipped through the pipeline is never in the window;
3. the window is documented rather than discovered during an assessment.

A table declaring `ROW_ACCESS_REQUIRED = YES` without the `BUSINESS_UNIT` column
the policy binds to is **reported as a CRITICAL finding, not skipped**. A silently
skipped table is an unprotected table with a compliant-looking tag — the worst
available outcome.

Entitlements live in one table, `CONTROL.ROW_ACCESS_ENTITLEMENT`, so an access
review is a single query rather than a policy-by-policy audit. `DATA_RESIDENCY`
deliberately does not honour the `'*'` wildcard: "this role may read data from
every jurisdiction" is not a statement one grant should be able to make.

## 5.4 Beyond masking

| Policy | Tag driver | Why masking is insufficient |
|---|---|---|
| `AGG_HIGHLY_RESTRICTED` | `DATA_CLASSIFICATION = HIGHLY_RESTRICTED` | Forces `MIN_GROUP_SIZE => 25`. Salary bands are analysable in aggregate but must never be resolvable to an individual — a masking policy cannot express a group-size floor. |
| `PROJ_PCI_NO_OUTPUT` | `PCI = YES` | Blocks the column from appearing in output at all while still allowing joins and predicates. PCI-DSS assessors ask for this specifically. |

## 5.5 Column-level governance and classification

```
  Snowflake classifier ──► SNOWFLAKE.CORE.PRIVACY_CATEGORY / SEMANTIC_CATEGORY
            │                                │
            │                                ▼
            │                  CONTROL.CLASSIFICATION_RECONCILIATION
            │                                │
            │              ┌─────────────────┼─────────────────┐
            ▼              ▼                 ▼                 ▼
       (proposal)      AGREED          AUTO_APPLIED      HUMAN_OVERRIDE
                    classifier and   no human ruling;   human decided
                    human agree      PII=YES applied,   otherwise; reason
                                     steward notified   required; NEVER
                                                        overwritten
```

The classifier is treated as a proposal, never as the decision. A nightly job that
silently reverts a considered human judgement trains people to stop making
considered judgements — and the human is the one who is accountable in an audit.
Human overrides lacking a recorded reason are reported for steward review, which
is the pressure that keeps overrides honest.

## 5.6 Compliance reporting

`VW_COMPLIANCE_EVIDENCE` is written to be handed to an assessor unmodified. Each
row states the object, its governing regime, the full multi-regime scope, its
classification, the controls declared and — the only question that matters —
whether those controls are actually attached:

```
CONTROL_STATE
  'GAP: row access declared but not enforced'
  'GAP: PII present but no column carries a masking policy'
  'GAP: object is unclassified'
  'CONTROLS ALIGNED'
```

| Regime | What the framework provides |
|---|---|
| **GDPR / CCPA / LGPD** | `PII` + `SENSITIVE_DATA` locate personal data for DSAR and erasure; `DATA_RESIDENCY` governs transfer; `RETENTION_CLASS` evidences storage limitation; `TAG_CHANGE_LOG` evidences accountability (Art. 5(2)) |
| **HIPAA** | `PHI` scopes ePHI; masking policies implement minimum-necessary; `PHI_UNMASKED` grants are the access log |
| **PCI-DSS** | `PCI` scopes the CDE; masking + projection policies implement Req. 3.4; `SP_DETECT_POLICY_DRIFT` evidences Req. 10 monitoring |
| **SOX** | `CRITICALITY` + `DATA_OWNER` establish control ownership; `TAG_CHANGE_LOG` gives immutable change evidence |
| **Internal** | `COMPLIANCE_SCORE_HISTORY` gives the trend; `TAG_EXCEPTION` gives the risk-acceptance register |

The framework's strongest compliance claim is not coverage — it is that
**declared-but-not-enforced is detected within the hour and reported as
CRITICAL**. Most estates cannot answer that question at all.
