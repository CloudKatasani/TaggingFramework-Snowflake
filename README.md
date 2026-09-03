# Enterprise Tagging Framework

A production-shaped tagging, governance and FinOps framework implementing the
enterprise **FinOps Tagging Strategy — Allocation Hierarchy** across AWS,
Snowflake, Denodo and Collibra.

Not a document describing a taxonomy. A **catalog that generates the deployable
artifacts**, the SQL that enforces it, and the CI that stops the two from
drifting apart.

```
config/tag_catalog.yaml          ← the single source of truth (40 tags)
        │
        ├─► sql/_generated/*.sql             tag DDL, registry seed, policy attachment
        ├─► docs/reference/*.md              requirement matrix, per-tag reference
        └─► terraform/**/*.auto.tfvars.json  Terraform inputs

CI fails if any generated artifact is stale.
```

---

## What it gives you

| | |
|---|---|
| **The published hierarchy, exactly** | Tier 1 *is* the ten-tag allocation hierarchy — a test fails if it drifts from the standard |
| **40 tags in 3 tiers** | 10 allocation, 15 conditional-governance, 15 optional/domain |
| **Four platforms, one vocabulary** | AWS SCPs, Snowflake object tags, Denodo properties, Collibra attributes — with the case-sensitivity trap handled |
| **Enforcement, not description** | Masking, row access, aggregation and projection policies driven by tags |
| **Scoped delegation** | `SP_APPLY_TAG` lends out the account-scoped `APPLY TAG` privilege under domain-ownership, value and override checks |
| **Compliance engine** | Seven-check scanner producing routed, ranked, self-closing findings — including contradiction rules, which catch what coverage metrics cannot |
| **Drift detection** | Hourly check that declared controls are still *attached* — the failure mode that keeps reports green while data is in clear |
| **FinOps** | Chargeback and showback by operating company, department and workload type, from warehouse metering, per-query attribution and storage metrics, with an explicit unallocated bucket |
| **Full lifecycle** | Approval workflow, deprecation, safe retirement, time-boxed exceptions |

## Repository map

```
config/tag_catalog.yaml              The taxonomy. Everything else follows from it.
scripts/
  validate_catalog.py                CI gate: structure, budgets, enforceability
  generate_sql.py                    → sql/_generated/
  generate_docs.py                   → docs/reference/
  generate_tfvars.py                 → terraform/envs/*/
  lint_sql.py                        Blocks destructive SQL patterns
  deploy.py                          Deployment order (--plan / --execute)
sql/
  00_bootstrap/                      Database, schemas, roles, warehouse, grants
  20_policies/                       Entitlement roles, masking, row access, aggregation
  30_control_plane/                  Registry, reference data, exceptions, audit trail
  40_procedures/                     SP_APPLY_TAG, compliance scan, reconciliation, lifecycle
  50_views/                          Inventory, effective tags, reporting, audit evidence
  60_automation/                     Tasks and alerts
  70_finops/                         Cost allocation and chargeback
  90_teardown/                       Sandbox teardown (destructive)
  _generated/                        Do not edit
terraform/                           Tag objects, roles, grants, warehouse
tests/                               82 tests over catalog semantics and generators
examples/                            Seed data, product onboarding, governance queries
docs/                                The framework, in eleven chapters
```

## Documentation

| | |
|---|---|
| [1. Tagging strategy](docs/01-tagging-strategy.md) | Principles, operating model, naming, vocabulary, lifecycle, approval, ownership, stewardship |
| [2. Tag taxonomy](docs/02-tag-taxonomy.md) | The 42 tags, ten categories, and the multi-valued-attribute problem |
| [3. Mandatory vs optional](docs/03-mandatory-vs-optional.md) | How requirement levels are chosen; conditional mandates |
| [4. Inheritance strategy](docs/04-inheritance-strategy.md) | Hierarchy, resolution modes, override rules, the clone problem |
| [5. Security & compliance](docs/05-security-compliance-integration.md) | Masking, row access, classification, audit evidence |
| [6. Automation](docs/06-automation-framework.md) | Tasks, alerts, classification, CI/CD, backfill sequence |
| [7. FinOps](docs/07-finops-framework.md) | Chargeback, showback, shared-warehouse attribution |
| [8. Enterprise standards](docs/08-enterprise-standards.md) | Naming, versioning, retirement, exception management |
| [9. Anti-patterns](docs/09-anti-patterns.md) | Fifteen failure modes and the mitigation for each |
| [10. Final recommendation](docs/10-final-recommendation.md) | Tier 1/2/3, hierarchy diagram, worked example |
| [11. Roadmap & RACI](docs/11-roadmap-maturity-raci.md) | Twelve-month plan, maturity model, RACI, team model |
| [12. Multi-platform enforcement](docs/12-multi-platform-enforcement.md) | AWS SCPs, Snowflake, Denodo, Collibra; the case-sensitivity trap; cross-platform cost reconciliation |
| [Requirement matrix](docs/reference/requirement-matrix.md) | *Generated* |
| [Tag catalog reference](docs/reference/tag-catalog.md) | *Generated* |

## Quick start

```bash
make validate       # check the catalog
make build          # regenerate SQL, docs and Terraform inputs
make test           # 82 unit tests
make check          # exactly what CI runs
make deploy-plan    # print the deployment order
```

Deploying to a Snowflake account (Enterprise Edition or higher — object tagging
is not available below it):

```bash
python3 scripts/deploy.py --plan                 # review the 18-script order
python3 scripts/deploy.py --execute <connection> # requires the Snowflake CLI
```

Then seed `CONTROL.REFERENCE_VALUE` and `CONTROL.RATE_CARD`
(see [`examples/01_seed_reference_data.sql`](examples/01_seed_reference_data.sql))
before enabling the tasks — reference-data validation and cost reporting both
depend on them.

## Adding a tag

```bash
$EDITOR config/tag_catalog.yaml   # add the definition
make build                        # regenerate SQL, docs, tfvars
make test
git commit -am "Add DATA_SENSITIVITY_REVIEW_DATE tag"
```

CI checks structure, the per-object mandatory budget, that the tag names a
consumer, that any conditional rule referencing it is enforceable, and that the
generated artifacts were committed. Tier 1 and Tier 2 changes additionally need
Data Governance Council approval — see
[strategy §1.7](docs/01-tagging-strategy.md#17-approval-workflow).

## The allocation hierarchy

```
  operating_company  →  department  →  domain  →  team  →  application
                     →  workload_type  →  owner_user

  alongside:  environment
              data_classification_enterprise    NONE ‹ PUBLIC ‹ INTERNAL ‹ CONFIDENTIAL ‹ RESTRICTED
              data_classification_regulatory    NONE ‹ PII ‹ SPII ‹ PHI ‹ PCI
```

Tier 1 is exactly these ten tags — no more, no less — and
`test_tier1_is_exactly_the_published_hierarchy` fails the build if that changes.
"Mandatory" means the same thing in this repository as it does on the slide every
team has been shown, including that `owner_user` is Recommended rather than
Mandatory.

## Six decisions worth knowing about

**Canonical keys are lowercase; Snowflake folds them.** AWS tag keys are
case-sensitive, Snowflake folds unquoted identifiers to upper case. So
`operating_company` on AWS is `OPERATING_COMPANY` in Snowflake, and
`CONTROL.TAG_CATALOG` stores both — a join to `ACCOUNT_USAGE.TAG_REFERENCES`
needs the folded name, a reconciliation against AWS cost data needs the canonical
one. Getting this wrong produces a cost report that is out by a third with no
error anywhere. → [§12.1](docs/12-multi-platform-enforcement.md#121-the-case-sensitivity-trap)

**Masking policies bind to exactly one tag.** `data_classification_enterprise`
carries all five attachments and the policy body branches on
`data_classification_regulatory`. If both carried policies, a column tagged
`RESTRICTED` and `PCI` would have two candidates for the same data type, and
which one applied would depend on tag-lineage proximity rather than on which
control is stronger. → [§5.2](docs/05-security-compliance-integration.md#52-dynamic-data-masking)

**Contradiction rules, not just coverage.** The two-tag classification split makes
`PCI` + `PUBLIC` possible: both mandatory tags present, coverage reports 100%, and
the masking policy returns cardholder data in clear. Conditional rules catch a tag
being *absent*; contradiction rules catch two tags being *present and mutually
impossible*. → [§3.3b](docs/03-mandatory-vs-optional.md#33b-contradiction-rules)

**Control tags resolve most-restrictive-wins.** Under nearest-wins, tagging a
column `NONE` inside a `PCI` table silently unmasks it — the most common way
tag-based masking is defeated. Enforced on both the write path and the read path.
→ [§4.3](docs/04-inheritance-strategy.md#43-two-resolution-modes)

**Row access enforcement is a reconciliation task, stated plainly.** Snowflake
supports tag-attached masking policies but *not* tag-attached row access policies.
A 15-minute task closes the gap, and the eventual-consistency window is documented
rather than discovered during an assessment.
→ [§5.3](docs/05-security-compliance-integration.md#53-row-access-policies)

**Stewards never hold `APPLY TAG`.** The privilege cannot be scoped below the
account, so granting it to stewards lets any of them retag any object. One role
holds it; `SP_APPLY_TAG` lends it out under conditions and logs every change with
a mandatory reason. → [AP-12](docs/09-anti-patterns.md#ap-12--granting-apply-tag-broadly)

## Requirements

- Snowflake **Enterprise Edition or higher** (object tagging)
- Python 3.9+ with `pyyaml` (`pytest` for the test suite)
- Terraform ≥ 1.5 with the `snowflakedb/snowflake` provider ~> 2.0 (optional)
- `ACCOUNTADMIN` for the initial bootstrap only; everything after runs as
  `TAG_ADMIN`

## Verification status

What is mechanically verified in this repository, and what is not — worth knowing
before you point it at an account.

**Verified here:** the catalog validates against 40+ structural and governance
rules; 61 unit tests cover resolution semantics, requirement levels, conditional
rules, SQL literal escaping and generator determinism; the SQL linter checks
every file for destructive patterns; generated artifacts are proven current;
Terraform is format- and validate-checked in CI.

**Not verified here:** the SQL has not been executed against a live Snowflake
account — this repository has no account to run it in. The DDL, policies,
procedures and views are written against documented Snowflake behaviour and
reviewed for it, but before a production deployment run them through a scratch
account and check in particular:

- `ACCOUNT_USAGE` column names in `VW_OBJECT_INVENTORY`, which vary a little by
  Snowflake release (`TASKS`, `STAGES`, `PIPES`, `WAREHOUSES`);
- the Snowflake Scripting cursor and `CALL` forms in `sql/40_procedures/`;
- `QUERY_ATTRIBUTION_HISTORY` availability, which depends on edition and region;
- aggregation and projection policy syntax, which is newer than the rest.

`scripts/deploy.py --plan` prints the order; every script is idempotent, so a
failure part-way through can be fixed and re-run from that point.

## Adapting it

This is a reference implementation with defensible defaults, not a drop-in
configuration. Before a real deployment, at minimum:

- replace the example reference data with feeds from your ERP, CMDB, HR and ITSM
  — note that only teams, applications, cost centres and data products are
  reference data; the operating company, department, domain, workload type and
  both classification vocabularies are enforced by Snowflake `ALLOWED_VALUES`;
- set `CONTROL.RATE_CARD` from your commercial agreement;
- replace the `example.com` addresses in the alerts and entitlement roles;
- review Tier 1 against your own regulatory footprint — the 17 are a considered
  starting point, not a universal truth;
- decide your own `DATA_CLASSIFICATION` levels if your enterprise already has a
  published information-classification standard. **Align to the existing standard
  rather than introducing a second one** — two classification schemes in one
  organisation is worse than either alone.
