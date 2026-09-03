# 12. Multi-Platform Enforcement

The allocation hierarchy is applied **at every resource** across AWS, Snowflake,
Denodo and Collibra. One vocabulary, four enforcement mechanisms — and the
differences between them are load-bearing, not cosmetic.

## 12.1 The case-sensitivity trap

This is the first thing to get right, and it is silent when you get it wrong.

| Platform | Identifier handling | Consequence |
|---|---|---|
| **AWS** | Tag keys are **case-sensitive** | `operating_company` and `Operating_Company` are two different tags on the same resource, and Cost Explorer will group by them separately |
| **Snowflake** | Unquoted identifiers **fold to upper case** | `operating_company` becomes `OPERATING_COMPANY`; `ACCOUNT_USAGE.TAG_REFERENCES` reports the folded name |
| **Denodo** | Custom properties, case-preserving | Matches AWS |
| **Collibra** | Attribute types, case-preserving | Matches AWS |

So a single canonical key has two written forms, and the framework carries both
rather than picking one and hoping:

```
canonical (AWS/Denodo/Collibra)   operating_company
Snowflake identifier              OPERATING_COMPANY
```

`CONTROL.TAG_CATALOG` stores both — `CANONICAL_KEY` and `TAG_NAME` — because a
join to `ACCOUNT_USAGE.TAG_REFERENCES` must match the folded name, while a
reconciliation against AWS Cost and Usage Report data must match the canonical
one. Storing only one means half your joins return nothing, and they return
nothing *quietly*.

Two safeguards make this structural rather than remembered:

- `validate_catalog.py` fails the build if two canonical keys fold to the same
  Snowflake identifier — that is two allocation buckets on AWS and one in
  Snowflake, which produces a cost report that does not reconcile and an
  investigation that takes a week.
- The Snowflake DDL is emitted **unquoted**, so it folds naturally. Quoting
  lowercase identifiers would work, and would then force every downstream query,
  policy body and join in the estate to quote them forever.

## 12.2 Enforcement by platform

```
                    ┌──────────────────────────────┐
                    │   config/tag_catalog.yaml    │
                    │   canonical keys + values    │
                    └───────────────┬──────────────┘
        ┌───────────────┬───────────┼───────────┬───────────────┐
        ▼               ▼           ▼           ▼               ▼
   ┌─────────┐   ┌────────────┐ ┌────────┐ ┌──────────┐  ┌────────────┐
   │   AWS   │   │ SNOWFLAKE  │ │ DENODO │ │ COLLIBRA │  │   CI/CD    │
   │         │   │            │ │        │ │          │  │            │
   │ SCP     │   │ ALLOWED_   │ │ custom │ │ attribute│  │ IaC        │
   │ deny on │   │ VALUES +   │ │ props  │ │ types    │  │ pre-deploy │
   │ missing │   │SP_APPLY_TAG│ │        │ │          │  │ linting    │
   │ keys    │   │ + masking  │ │        │ │          │  │            │
   └────┬────┘   └──────┬─────┘ └───┬────┘ └────┬─────┘  └─────┬──────┘
        │               │           │           │              │
        └───────────────┴─────┬─────┴───────────┴──────────────┘
                              ▼
                  ┌───────────────────────────┐
                  │  Daily drift report       │
                  │  Untagged PRD resources   │
                  │  blocked at CI/CD         │
                  └───────────────────────────┘
```

### AWS — Service Control Policies

SCPs are the strongest control available because they deny at the API, before a
resource exists. The pattern below refuses any RDS/S3/EC2 creation missing the
mandatory keys:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyCreateWithoutAllocationTags",
    "Effect": "Deny",
    "Action": ["rds:CreateDBInstance", "s3:CreateBucket", "ec2:RunInstances"],
    "Resource": "*",
    "Condition": {
      "Null": {
        "aws:RequestTag/operating_company": "true",
        "aws:RequestTag/department": "true",
        "aws:RequestTag/environment": "true",
        "aws:RequestTag/team": "true",
        "aws:RequestTag/application": "true"
      }
    }
  }]
}
```

Two limits worth stating plainly rather than discovering later:

- **`aws:RequestTag` only guards creation.** Someone can remove a tag afterwards,
  and the SCP will not stop them. AWS Config rules
  (`required-tags`) catch that after the fact; the daily drift report is what
  closes the loop.
- **Not every service supports tag-on-create for every resource.** The SCP must
  be scoped to actions that do, or it will block legitimate work. Roll it out in
  audit mode first.

Value validation is weaker on AWS than in Snowflake: `aws:RequestTag` can test a
key's presence and match specific values via `StringNotEquals`, but a nine-value
vocabulary written into an SCP condition is a policy edit every time the
vocabulary changes. The framework's answer is to enforce **presence** at the SCP
and **validity** in the pre-deploy linter, which reads the same catalog.

### Snowflake — the strongest value enforcement of the four

- `ALLOWED_VALUES` rejects an invalid value at `SET` time, in the engine.
- `SP_APPLY_TAG` validates reference data and free-text formats, which
  `ALLOWED_VALUES` cannot express.
- Tag-based masking makes classification *do* something rather than merely
  describe.
- The nightly scan finds anything applied around those paths.

This is why Snowflake is where the substantive controls live, and why the other
platforms' tags are primarily allocation and discovery metadata.

### Denodo and Collibra

Neither validates values natively in the way Snowflake does. Both are populated
from the same registry, and both are covered by the pre-deploy linter and the
drift report. Stated plainly: on these two platforms **the tag is validated
before deployment, not at write time** — a value changed directly in the tool is
caught by the daily report, not rejected on the spot.

Collibra is also the reverse direction: the catalog's attribute types are
synchronised *from* the tag registry, so the business glossary and the platforms
cannot disagree about which values are legal.

### CI/CD — the common gate

The pre-deploy linter reads `config/tag_catalog.yaml` and checks Terraform, dbt
and Denodo VQL for the mandatory keys and legal values before anything is
applied. It is the only enforcement point that covers all four platforms with one
implementation, which makes it the right place for value validation and the wrong
place to rely on alone — it only sees what goes through the pipeline.

## 12.3 What each platform can and cannot do

Being explicit about the gaps is the point; a matrix of ticks would be a
misrepresentation.

| Capability | AWS | Snowflake | Denodo | Collibra |
|---|---|---|---|---|
| Block creation without tags | **Yes** (SCP) | Via CI/CD gate | Via CI/CD gate | n/a |
| Reject an invalid value at write | Partial (SCP conditions) | **Yes** (`ALLOWED_VALUES`) | No | No |
| Validate reference data | No | Yes (`SP_APPLY_TAG`) | No | Yes (via sync) |
| Inherit down a hierarchy | No | **Yes** (tag lineage) | No | Partial |
| Drive data masking from a tag | No | **Yes** | No | No |
| Detect drift | Config rules | Nightly scan | Daily report | Daily report |

The asymmetry drives the architecture: **Snowflake is where controls are
enforced; AWS is where creation is blocked; CI/CD is where values are validated
uniformly; Collibra is where the vocabulary is published to people.**

## 12.4 Reconciling cost across platforms

The allocation hierarchy exists so that one cost report spans the estate. That
requires joining Snowflake credits to AWS spend on the same keys:

```sql
-- Snowflake side (canonical keys lower-cased for the join)
SELECT LOWER(OPERATING_COMPANY) AS operating_company,
       LOWER(DEPARTMENT)        AS department,
       'SNOWFLAKE'              AS platform,
       SUM(COST)                AS cost
FROM GOVERNANCE.REPORTING.VW_WAREHOUSE_COST_ALLOCATION
WHERE USAGE_DATE >= DATE_TRUNC('MONTH', CURRENT_DATE())
GROUP BY 1, 2

UNION ALL

-- AWS side, from the Cost and Usage Report landed in Snowflake. Keys arrive in
-- their canonical lowercase form, which is why the Snowflake side is lowered
-- rather than the AWS side upper-cased: the canonical form is the contract.
SELECT resource_tags_user_operating_company,
       resource_tags_user_department,
       'AWS',
       SUM(line_item_unblended_cost)
FROM FINOPS.AWS.COST_AND_USAGE_REPORT
WHERE line_item_usage_start_date >= DATE_TRUNC('MONTH', CURRENT_DATE())
GROUP BY 1, 2;
```

If that union does not reconcile to the invoices, the cause is almost always one
of three things, in this order of likelihood: a case mismatch on the join keys, a
resource created before the SCP was enforced, or a shared warehouse whose spend
needs query-level attribution
([FinOps §7.3](07-finops-framework.md#73-compute-allocation)).

## 12.5 Rollout order across platforms

Do not enable all four at once. Each platform's enforcement has a different blast
radius when it is wrong.

1. **Snowflake first.** Richest enforcement, and the estate where mis-tagging has
   governance consequences rather than only cost ones.
2. **CI/CD linting second**, in warn-only mode, across all platforms. This is
   what tells you how big the backlog actually is before you commit to a date.
3. **AWS SCPs third**, in audit mode, then enforcing. An SCP that denies
   legitimate work will be removed within a day and will cost the programme its
   credibility.
4. **Denodo and Collibra last**, once the vocabulary has stopped moving.

The sequencing rule: **enforce where you can already measure.** Blocking creation
before the drift report works produces incidents no one can diagnose.
