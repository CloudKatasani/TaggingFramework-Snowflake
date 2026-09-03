# 6. Automation Framework

Manual tagging fails at enterprise scale. Not slowly — a taxonomy applied by hand
is roughly 60% covered at go-live and degrading from that day, because object
creation outpaces stewardship in every organisation.

## 6.1 The control loop

```
   ┌────────────┐   deploy    ┌────────────┐   apply    ┌────────────┐
   │  CATALOG   │────────────►│   CI/CD    │───────────►│  SNOWFLAKE │
   │   (YAML)   │  generated  │  pipeline  │ SP_APPLY_  │   ESTATE   │
   └─────▲──────┘     SQL     └────────────┘    TAG     └──────┬─────┘
         │                                                     │
         │ quarterly review                                    │ observe
         │                                                     ▼
   ┌─────┴──────┐   findings  ┌────────────┐  scan     ┌────────────┐
   │  GOVERNANCE│◄────────────│  STEWARD   │◄──────────│ VALIDATION │
   │   COUNCIL  │             │  WORKLIST  │           │   ENGINE   │
   └────────────┘             └────────────┘           └────────────┘
                                     │                        ▲
                                     │ remediate              │
                                     └────────────────────────┘
```

Four properties this loop is designed to have:

- **The catalog is upstream of everything.** SQL, Terraform variables and docs are
  generated; CI fails if any is stale. There is no path by which a deployed tag
  and its published definition can disagree.
- **Findings close themselves.** Each scan marks prior open findings remediated
  and re-raises whatever is still wrong. An open finding always means "still
  broken today", which is the only way a findings report retains credibility.
- **Nothing depends on a human noticing.** The scan runs whether or not anyone
  logs in.
- **Every automated change is auditable.** `TAG_CHANGE_LOG.SOURCE` distinguishes
  `CICD`, `AUTO_CLASSIFY`, `REMEDIATION`, `INHERITANCE`, `BACKFILL` and `MANUAL`.

## 6.2 Snowflake capabilities used

| Capability | Used for | Note |
|---|---|---|
| Object tagging | The taxonomy | Enterprise Edition or higher |
| `ALLOWED_VALUES` | Vocabulary enforcement at `SET` time | Max 300 values per tag |
| Tag-based masking policies | Automatic column protection through lineage | One policy per data type per tag |
| `SYSTEM$GET_TAG` | Immediate parent lookup in `SP_APPLY_TAG` | No `ACCOUNT_USAGE` latency |
| `SYSTEM$GET_TAG_ON_CURRENT_COLUMN` | In-policy branching | Cheap; metadata read |
| `INFORMATION_SCHEMA.TAG_REFERENCES` | Deployment gates | Immediate |
| `ACCOUNT_USAGE.TAG_REFERENCES` | Estate-wide reporting | ≤ ~2 h latency |
| `ACCOUNT_USAGE.POLICY_REFERENCES` | Drift detection | The declared-vs-actual comparison |
| Auto-classification (`SNOWFLAKE.CORE`) | PII proposals | Proposal, not decision |
| Tasks | Scheduled control loop | DAG + independent high-frequency tasks |
| Alerts + notification integration | Escalation | Email; extend to PagerDuty via external function |
| `QUERY_ATTRIBUTION_HISTORY` | Per-query cost attribution | The key to shared-warehouse chargeback |

## 6.3 Scheduled workload

| Object | Cadence | Purpose |
|---|---|---|
| `TASK_APPLY_ROW_ACCESS` | 15 min | Closes the only real exposure window in the design |
| `TASK_DETECT_POLICY_DRIFT` | 60 min | Detached masking policy = live incident |
| `TASK_VALIDATE_COMPLIANCE` | daily 02:00 | Full estate scan |
| `TASK_RECONCILE_CLASSIFICATION` | after scan | Classifier ↔ enterprise `PII` |
| `TASK_SNAPSHOT_COMPLIANCE` | after reconcile | Scorecard trend |
| `ALERT_POLICY_DRIFT` | 30 min | The one alert that should page someone |
| `ALERT_CRITICAL_FINDINGS` | daily 06:00 | Digest |
| `ALERT_EXPIRING_EXCEPTIONS` | weekly Mon | 14-day warning |

Cadence follows exposure, not convenience. Row access reconciliation runs 96×
more often than the compliance scan because it is the only control with a genuine
gap between declaration and enforcement.

`TASK_APPLY_ROW_ACCESS` and `TASK_DETECT_POLICY_DRIFT` are deliberately *not* part
of the nightly DAG: a failure in the compliance scan must never stop row access
policies being applied to new tables.

### Cost

The whole loop runs on an `XSMALL` warehouse with 60-second auto-suspend. The
scans are metadata queries against `ACCOUNT_USAGE`, not data scans. Expect
single-digit credits per month for the governance workload. A governance framework
that costs more than a rounding error on the platform bill will be challenged in
its first budget review, and correctly so.

## 6.4 Classification integration

```sql
-- One-off: define what the classifier looks for and where.
CREATE OR REPLACE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
    GOVERNANCE.CONTROL.ENTERPRISE_CLASSIFICATION_PROFILE(
        {'minimum_object_age_for_classification_days': 0,
         'maximum_classification_validity_days': 30,
         'auto_tag': true});

-- Then per schema:
CALL GOVERNANCE.CONTROL.ENTERPRISE_CLASSIFICATION_PROFILE!SET_SCHEMA(
        'CUSTOMER_PROD.CORE');
```

Snowflake writes `SEMANTIC_CATEGORY` and `PRIVACY_CATEGORY` into `SNOWFLAKE.CORE`.
`SP_RECONCILE_CLASSIFICATION` then maps that into the enterprise `PII` decision:

| Classifier | Enterprise `PII` | State | Action |
|---|---|---|---|
| IDENTIFIER | (unset) | `AUTO_APPLIED` | `PII = YES` set, steward notified |
| IDENTIFIER | `YES` | `AGREED` | none |
| IDENTIFIER | `NO` | `HUMAN_OVERRIDE` | surfaced for review; **never overwritten** |
| none | `YES` | `HUMAN_OVERRIDE` | none — humans see context the classifier cannot |

The asymmetry is intentional. The classifier may *add* a `PII` flag where nobody
has ruled; it may never *remove* one, and it may never revert a human decision.
Classifiers produce false negatives on encoded identifiers, free-text notes and
composite keys, and a job that silently downgrades human judgement overnight is a
job that will eventually unmask something.

## 6.5 Infrastructure as code

```
config/tag_catalog.yaml
        │
        ├── generate_sql.py     ──► sql/_generated/*.sql  ──► snowsql / Snowflake CLI
        ├── generate_docs.py    ──► docs/reference/*.md
        └── generate_tfvars.py  ──► terraform/*.auto.tfvars.json ──► terraform apply
```

**Both Terraform and SQL, on purpose.** They are good at different things:

- *Terraform* — tag objects, allowed values, roles, warehouses, grants. Long-lived
  declarative resources where drift detection and a plan/apply review are worth
  having.
- *SQL* — policies, procedures, tasks, views. Terraform's Snowflake provider
  models these poorly, and a masking policy body is code that belongs in a
  reviewed `.sql` file, not in a heredoc inside HCL.

The dividing line: **Terraform owns what exists; SQL owns what it does.**

`terraform/` uses `for_each` over the generated variables so a new tag is a
catalog change, never an HCL change.

## 6.6 CI/CD

`.github/workflows/tag-framework.yml` runs on every PR:

| Stage | Gate |
|---|---|
| `validate` | Catalog schema, budgets, `drives` non-empty, vocabulary limits |
| `generated-sync` | Generated SQL/docs/tfvars match the catalog |
| `sql-lint` | No `CREATE OR REPLACE TAG`; no `DROP TAG`; no hard-coded credentials |
| `unit-tests` | Resolution logic, requirement matrix, conditional rules |
| `terraform-validate` | HCL is valid and formatted |
| `plan` | `terraform plan` against non-production |

### The lint rule that matters most

```
CREATE OR REPLACE TAG   →  build fails
```

`CREATE OR REPLACE TAG` on a populated account **drops every assignment of that
tag across the estate** and detaches any masking policy attached to it. Both
succeed silently and both leave the estate unprotected. It is an easy thing to
write, it looks idiomatic, and it is catastrophic — so it is blocked
mechanically rather than left to code review. `sql/_generated/10_tag_ddl.sql`
therefore only ever emits `CREATE TAG IF NOT EXISTS` plus `ALTER TAG`.

### Deployment gate

Promotion to production requires Tier 1 tags on every object being deployed. The
gate queries `INFORMATION_SCHEMA.TAG_REFERENCES`, not `ACCOUNT_USAGE`, because a
gate with two hours of latency approves objects on the basis of yesterday's state:

```sql
SELECT OBJECT_NAME, TAG_NAME
FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES('CUSTOMER_PROD.CORE.ORDERS', 'TABLE'))
WHERE TAG_NAME IN ('DATA_CLASSIFICATION', 'PII', 'DATA_LIFECYCLE',
                   'RETENTION_CLASS', 'REGULATION', 'ROW_ACCESS_REQUIRED');
```

## 6.7 Backfilling an existing estate

The order matters. Tagging top-down means inheritance does most of the work before
anyone touches a table.

1. **Inventory and prioritise.** `VW_OBJECT_INVENTORY` ranked by storage and query
   volume. Typically 5% of schemas carry 80% of consumption — start there and the
   coverage metric moves visibly in week one, which is what sustains sponsorship.
2. **Databases first.** `BUSINESS_UNIT`, `ENVIRONMENT`, `COST_CENTER`, `DOMAIN`,
   `SUPPORT_GROUP`, `DATA_OWNER`, `CRITICALITY`. A few hundred assignments cover
   the whole estate by inheritance and immediately fix FinOps allocation.
3. **Run the classifier** across the prioritised schemas to propose `PII`.
4. **Schemas.** `DATA_PRODUCT`, `DATA_STEWARD`, `SLA_TIER`, `RETENTION_CLASS`,
   `REGULATION`.
5. **Attach masking policies.** Only now — with classification in place, so the
   policies protect something on day one rather than being attached to an empty
   taxonomy.
6. **Tables and columns**, worked from `VW_STEWARD_WORKLIST` by blast radius.
7. **Enable the deployment gate** for new objects, so the backlog stops growing
   while it is being cleared.

Attaching masking policies before classification (a common instinct, since it is
the visible security control) protects nothing and creates a false assurance
signal for however long the backfill takes.
