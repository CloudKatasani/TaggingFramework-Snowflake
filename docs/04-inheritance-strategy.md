# 4. Tag Inheritance Strategy

## 4.1 What Snowflake gives you

Snowflake implements tag lineage natively: a tag set on a database is visible on
its schemas, tables and columns, and `TAG_REFERENCES_WITH_LINEAGE` resolves it.
Critically, **tag-based masking policies propagate through lineage too** — a
masking policy attached to a tag set on a table protects every column of the
matching data type in that table. That single behaviour is the highest-leverage
control in Snowflake governance.

What Snowflake does *not* give you is a resolution rule when values exist at
several levels, or any notion that some tags should resolve differently from
others. That is what this chapter defines and `VW_EFFECTIVE_TAG` implements.

## 4.2 The hierarchy

```
  ACCOUNT ─────────────────────────── enterprise defaults (rare; a floor)
     │
     ▼
  DATABASE ────────────────────────── operating_company, department, domain,
     │                                team, environment,
     │                                data_classification_enterprise
     ▼
  SCHEMA ──────────────────────────── application, domain, team,
     │                                both classification tags,
     │                                data_product, retention_class, sla_tier
     ▼
  TABLE / VIEW ────────────────────── classification escalations,
     │                                row_access_required
     ▼
  COLUMN ──────────────────────────── data_classification_regulatory,
                                      masking_required    (the enforcement point)
```

### Objects outside the chain

Warehouses, stages, pipes, tasks and streams sit outside this hierarchy. A
warehouse belongs to no database, so **nothing is inherited** — all six
allocation tags must be set directly:

```
  WAREHOUSE ───── operating_company, department, team, application,
                  workload_type, environment          (6 direct assignments)
```

This is the single most common source of unallocated spend in a Snowflake
estate, and it is worth stating plainly: databases get their tags once and
inherit them across ten thousand objects; every warehouse is six separate
decisions that nothing corrects for you. `VW_UNALLOCATED_SPEND` therefore names
the specific missing keys per warehouse rather than reporting a total.

## 4.3 Two resolution modes

Not every tag should resolve the same way. Getting this wrong is the most
consequential modelling error available here, because **it is invisible until an
audit**.

### Nearest-wins (`override_rule: any`)

The value set closest to the object applies. Correct for *descriptive* facts,
where a more specific statement is simply better information.

```
DATABASE  CUSTOMER_DB      DATA_OWNER = vp.customer@example.com
  SCHEMA  CUSTOMER_DB.EU   DATA_OWNER = eu.lead@example.com     ← wins for EU
   TABLE  ...EU.CONTACTS   (not set)                → eu.lead@example.com
   TABLE  ...US.CONTACTS   (not set)                → vp.customer@example.com
```

### Most-restrictive-wins (`override_rule: more_restrictive_only`)

The strongest value anywhere in the lineage applies, **regardless of depth**.
Correct for *controls*.

```
DATABASE  HR_DB            DATA_CLASSIFICATION = CONFIDENTIAL
  SCHEMA  HR_DB.PAYROLL    DATA_CLASSIFICATION = RESTRICTED
   TABLE  ...PAYROLL.COMP  DATA_CLASSIFICATION = CONFIDENTIAL  ← rejected
                                                 effective: RESTRICTED
```

Two things happen there, and both matter:

1. `SP_APPLY_TAG` **rejects the assignment at write time** with an explanation.
2. Even if a value were weakened by some path around the procedure,
   `VW_EFFECTIVE_TAG` still resolves `RESTRICTED`, because it ranks by ordinal
   severity before proximity. The read path does not trust the write path.

Applied to: `data_classification_enterprise`, `data_classification_regulatory`,
`criticality`, `masking_required`, `row_access_required`, `encryption_required`,
`legal_hold`.

**Why depth does not win for controls.** Under nearest-wins, a steward tagging a
column `PII = NO` inside a table marked `PII = YES` silently unmasks it. That is
not a hypothetical: it is the single most common way tag-based masking is
defeated in practice, usually by someone fixing a false positive on one column
without realising the blast radius. Most-restrictive-wins makes it impossible.

### No-override (`override_rule: none`)

`environment` and `data_product`. A schema inside `CUSTOMER_PRD` cannot declare
itself `DEV`; a table cannot belong to a different data product than its schema.
These are structural facts about where the object lives, not judgements about it.

## 4.4 Resolution algorithm

Implemented in `VW_EFFECTIVE_TAG` (`sql/50_views/00_inventory_and_effective_tags.sql`):

1. Build every (object, ancestor-assignment) candidate pair, each labelled with
   its distance: 0 = the object itself, 1 = its table, 2 = its schema, 3 = its
   database.
2. Join to `TAG_CATALOG` for the override rule and to `TAG_ALLOWED_VALUE` for the
   ordinal position.
3. Rank within each (object, tag):
   - `more_restrictive_only` → highest ordinal first, ties broken by proximity;
   - everything else → nearest first.
4. Take rank 1.

The output names both the value and where it came from
(`INHERITED_FROM`, `INHERITANCE_DISTANCE`, `IS_DIRECTLY_ASSIGNED`), which is what
makes a finding actionable: "missing" and "inherited from a database three levels
up that is about to be retired" need different responses.

## 4.5 What inheritance does *not* do

Two boundaries that cause real incidents when assumed away.

**Views do not inherit from their base tables.** A view over a table containing
PII is a separate object with its own tags. Nothing in Snowflake or in this
framework propagates a base table's classification to a view built on it — and a
view is precisely how masked data gets re-exposed. Both classification tags are therefore mandatory on `VIEW`, not inherited, and
CR-003 applies to views.
Where a view's own tags are weaker than its sources', that is a finding, not an
inference the platform can safely make for you.

**`CREATE TABLE AS SELECT` does not carry tags.** A CTAS produces a new,
untagged table containing the source's data. This is the largest routine leak of
regulated data out of the governed perimeter in any Snowflake estate. Mitigations,
in order of effectiveness: the nightly scan finds it within 24 hours; the
classification job re-detects the PII within 24 hours; CI/CD tags objects at
creation for anything deployed through the pipeline. Ad-hoc CTAS in a personal
schema remains a genuine residual risk, which is why `environment ∈ (DEV, TST, TRAINING)`
databases are excluded from sharing eligibility altogether.

## 4.6 The clone problem

`CREATE DATABASE ... CLONE` copies tags with the objects. That is usually
desirable and for `environment` it is exactly wrong.

Cloning `CUSTOMER_PRD` to refresh `CUSTOMER_UAT` produces a UAT database whose
every object insists it is `PRD`. The consequences are quiet and expensive:

- UAT compute bills to the production cost centre — a real misstatement in the
  chargeback report, not a rounding error;
- the promotion gate believes UAT objects have already passed production review;
- production-strength masking applies in UAT, so testers report "the data is
  broken" and someone is asked to make an exception;
- DR and criticality reporting counts the estate twice.

Nothing about it looks broken, which is why it survives for months.

`SP_REMEDIATE_CLONE_TAGS` is the fix and must run as the final step of every clone
operation:

```sql
CALL GOVERNANCE.AUTOMATION.SP_REMEDIATE_CLONE_TAGS('CUSTOMER_UAT', 'UAT', FALSE);
```

It rewrites `environment` on every directly-tagged object in the clone, and raises
a finding for any `data_quality_tier` carried in — a clone is not a certified data
product, and certification must be re-earned rather than copied.

## 4.7 Practical guidance by level

| Level | Set here | Never set here |
|---|---|---|
| **Database** | `operating_company`, `department`, `domain`, `team`, `environment`, baseline `data_classification_enterprise` | `data_classification_regulatory` — no database is uniformly PCI, and asserting it makes the tag meaningless |
| **Schema** | `application`, `data_product`, `data_steward`, `sla_tier`, `retention_class`, `data_lifecycle`, both classifications | `masking_required` — it is a column-level assertion |
| **Table/View** | classification *escalations*, `row_access_required` | `operating_company`, `department`, `cost_center` — inherit them; per-table finance tags are unmaintainable |
| **Column** | `data_classification_regulatory`, `masking_required` | Anything descriptive — 200 million rows of `domain` help nobody |

The single most useful heuristic: **if you find yourself setting the same tag
value on every object in a schema, it belonged on the schema.**
