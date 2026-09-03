# 1. Tagging Strategy

## 1.1 Why this framework exists

Every large Snowflake estate arrives at the same place. Two years in, there are
four thousand databases, nobody can say which of them hold personal data, the
finance team allocates 40% of the bill to a bucket called "shared platform", and
the answer to "who owns this table?" is a Slack thread.

Tagging is the mechanism that prevents that, but only if it is treated as a
**product with an operating model**, not a metadata convention. A convention
decays. A product has an owner, a backlog, a release process, adoption metrics
and a retirement policy.

That framing drives every decision in this repository, and the decisions worth
arguing about are called out where they occur.

## 1.2 Principles

These are ordered. Where two conflict, the earlier wins.

**P1 — Every tag must have a consumer.**
A tag exists because something automated reads it: a masking policy, a chargeback
report, an alert, a retention job. If no system consumes it, it is documentation
pretending to be governance, and it will be wrong within a quarter because
nothing breaks when it drifts. This is mechanically enforced: `drives` is a
required field, and `validate_catalog.py` fails the build if it is empty.

**P2 — Tag the highest object that makes the statement true.**
`BUSINESS_UNIT` belongs on the database. `DATA_PRODUCT` belongs on the schema.
`PII` belongs on the column. Tagging lower than necessary multiplies the
maintenance surface by thousands with no gain in meaning. Tagging higher than the
truth makes the tag a lie.

**P3 — Inheritance is the default; direct assignment is the exception.**
The framework mandates 17 core tags but expects roughly six direct assignments on
a typical table. The rest are inherited. Any design where mandatory tag count and
per-object effort are the same number will not be adopted.

**P4 — Controls fail closed.**
An absent, unreadable or ambiguous classification results in masked data, not
clear data. A framework that fails open is worse than no framework, because it
also carries an assurance claim.

**P5 — Enumerate values wherever the list is stable.**
Free text is the enemy of automation: `CC-1234`, `cc1234` and `1234` become three
cost centres in the chargeback report. Use `ALLOWED_VALUES` where the list is
small and stable, control-table validation where it is large or volatile, and
free text only for genuinely open values such as an owner's email.

**P6 — The taxonomy is closed.**
`CREATE TAG` is granted on exactly one schema to exactly one role. A team that
wants a new enterprise tag goes through the approval workflow. A local
`MYDB.UTIL.PII` tag masks nothing and reports nowhere, so the framework detects
and reports it rather than tolerating it.

**P7 — Prefer fewer tags with richer values.**
Adding a value to a controlled vocabulary is a one-line change. Adding a tag is a
permanent increase in the governance surface, in the mandatory matrix, in every
report and in every steward's workload. The default answer to "can we add a tag?"
is "can we add a value instead?".

**P8 — Automate assignment before demanding it.**
Ask humans only for what only humans know. Ownership, classification and business
context need people. Environment, lifecycle state and quality tier can be derived
from deployment metadata, classification services and quality pipelines. Every
tag the platform can set is a tag no steward has to.

**P9 — Measure adoption, and act on the measurement.**
`VW_TAG_ADOPTION` reports assignment counts, value spread and staleness per tag.
Tags with near-zero adoption are retired at quarterly review. A taxonomy that only
ever grows is a taxonomy nobody trusts.

**P10 — Exceptions are time-boxed, never permanent.**
`EXPIRES_AT` is `NOT NULL` on the exception table. A permanent exception is a
standard that was wrong, and should be fixed in the standard.

## 1.3 Governance operating model

The model is **federated with a central spine** — the only shape that works at
this scale. Full centralisation makes the governance team a bottleneck on
thousands of teams. Full federation produces thirty incompatible taxonomies.

```
                    ┌────────────────────────────────────────────┐
                    │        DATA GOVERNANCE COUNCIL             │
                    │  CDO (chair) · CISO · DPO · Finance · Legal │
                    │  Domain owner representatives              │
                    │                                            │
                    │  Owns: taxonomy, Tier 1/2, policy, appeals │
                    │  Cadence: monthly; quarterly full review   │
                    └─────────────────────┬──────────────────────┘
                                          │ sets standard
                    ┌─────────────────────▼──────────────────────┐
                    │   ENTERPRISE DATA GOVERNANCE OFFICE (EDGO) │
                    │   Runs the framework as a product          │
                    │                                            │
                    │   Owns: catalog, automation, reporting,    │
                    │         exception register, enablement     │
                    └─────────────────────┬──────────────────────┘
                       ┌──────────────────┼──────────────────┐
                       ▼                  ▼                  ▼
              ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
              │ DOMAIN: Finance│ │DOMAIN: Customer│ │ DOMAIN: Supply │
              │ Domain owner   │ │ Domain owner   │ │ Domain owner   │
              │ Data stewards  │ │ Data stewards  │ │ Data stewards  │
              │                │ │                │ │                │
              │ Owns: Tier 3   │ │ Owns: Tier 3   │ │ Owns: Tier 3   │
              │ tags, values,  │ │ tags, values,  │ │ tags, values,  │
              │ assignments    │ │ assignments    │ │ assignments    │
              └────────────────┘ └────────────────┘ └────────────────┘
                       │                  │                  │
                       └──────────────────┼──────────────────┘
                                          ▼
                    ┌────────────────────────────────────────────┐
                    │      PLATFORM ENGINEERING                  │
                    │  Deploys tags/policies via CI/CD, runs the  │
                    │  automation, owns Snowflake RBAC            │
                    └────────────────────────────────────────────┘
```

The division that matters: **the centre owns the vocabulary, the domains own the
facts.** The centre never decides that a given table is CONFIDENTIAL — it decides
that CONFIDENTIAL is one of five permitted values, what it obliges, and how
compliance is measured.

### Decision rights

| Decision | Who decides | Who is consulted |
|---|---|---|
| Add / change / retire a Tier 1 or Tier 2 tag | Data Governance Council | EDGO, domain owners, Platform |
| Add a value to a controlled vocabulary | EDGO | Tag owner role, affected domains |
| Add a Tier 3 domain tag | Domain owner | EDGO (registration only) |
| Make a Tier 2/3 tag mandatory within a domain | Domain owner | EDGO |
| Relax an enterprise mandatory tag | **Nobody.** Not delegable. | — |
| Assign a tag to an object | Data steward for that domain | Data owner |
| Grant a time-boxed exception | EDGO + tag owner role | Risk (CRITICAL severity only) |
| Classification of a specific dataset | Data owner | Steward, Privacy, Security |

## 1.4 Naming standards

**Tag identifiers**

- `UPPER_SNAKE_CASE`, 2–64 characters, matching `^[A-Z][A-Z0-9_]{1,63}$`.
- Singular nouns: `REGULATION`, not `REGULATIONS`.
- No prefixes. `TAG_`, `ENT_`, `CORP_` prefixes add length to every reference and
  distinguish nothing — the namespace `GOVERNANCE.TAGS` already does that.
- No abbreviations unless they are the enterprise's own term of art: `PII`, `PHI`
  and `PCI` are universally understood; `BUS_UN` is not.
- No environment, region or team names in the identifier. `PROD_DATA_OWNER`
  guarantees a second tag for every other environment. Environment is a *value*
  of `ENVIRONMENT`, not part of a name.
- Boolean-style tags are named for the positive assertion and take `YES`/`NO`:
  `LEGAL_HOLD`, not `IS_LEGAL_HOLD` or `NO_LEGAL_HOLD`. Double negatives in
  policy predicates are a reliable source of production incidents.

**Tag values**

- Controlled vocabularies are `UPPER_SNAKE_CASE`.
- Ordinal vocabularies are ordered least → most severe in `ordinal_values`, and
  that ordering is what "most restrictive wins" actually means at runtime.
- Values encoding a threshold carry it: `PLATINUM_15M`, `EXTENDED_7Y`. A steward
  choosing `GOLD` over `SILVER` should not have to look up what either promises.
- Reference-data values keep the source system's own format, prefixed for
  legibility: `CC-004120`, `APP-10457`, `GRP-DATA-PLATFORM`.
- Values are case-sensitive in Snowflake. `Yes` and `YES` are different values and
  `ALLOWED_VALUES` will reject the former — this is a feature, and the reason
  everything here is upper case.

**Namespace**

All enterprise tags live in `GOVERNANCE.TAGS`. There is no second location, and
the privilege model makes that structurally true rather than a rule people are
asked to remember (see `sql/00_bootstrap/00_governance_foundation.sql`, §6).

## 1.5 Controlled vocabulary approach

Three value sources, chosen by how the list behaves — not by how important it is.

| Source | When | Enforced by | Cost of change |
|---|---|---|---|
| `controlled_vocabulary` | Small, stable, enterprise-owned (≤ ~30 values) | Snowflake `ALLOWED_VALUES` — rejected at `SET` time | Catalog change + deploy |
| `reference_data` | Large or volatile, owned by another system (cost centres, apps, cost of a change is a business-as-usual ERP event) | `SP_APPLY_TAG` + nightly re-validation | Data load only |
| `free_text` | Genuinely open (email addresses) | Regex in `SP_APPLY_TAG` | None |

The distinction is operational, not philosophical. `ALLOWED_VALUES` is enforced by
Snowflake at assignment time and is therefore the strongest control available —
but every change to it is a deployment, and Snowflake caps a tag at 300 allowed
values. A global enterprise has more cost centres than that, and opens new ones
weekly. Putting them in `ALLOWED_VALUES` would mean a release per cost centre.

Reference data buys back that flexibility at a real cost: **Snowflake will accept
any string**. Enforcement moves entirely into `SP_APPLY_TAG`, which is why raw
`APPLY TAG` is granted to exactly one role. Anyone who can bypass the procedure
can write `cost_centre_tbd` into the chargeback pipeline.

Reference data also decays in a way vocabularies do not: a cost centre valid on
the day it was set can be closed a year later, and Snowflake never re-checks.
Check 3 in `SP_VALIDATE_COMPLIANCE` exists solely for that.

## 1.6 Tag lifecycle management

```
  PROPOSED ──review──► APPROVED ──deploy──► ACTIVE ──notice──► DEPRECATED ──sweep──► RETIRED
      │                    │                   │                    │                   │
      │ rejected           │ withdrawn         │ ◄──── reinstated ──┘                   │
      ▼                    ▼                   │                                        ▼
   CLOSED               CLOSED                 └──── quarterly adoption review    tag object kept
                                                                                  for audit history
```

| State | Meaning | Can be assigned? |
|---|---|---|
| `PROPOSED` | Submitted, under review | No — does not exist in Snowflake yet |
| `APPROVED` | Council approved, not yet deployed | No |
| `ACTIVE` | Deployed and in service | Yes |
| `DEPRECATED` | Superseded; 90-day notice running | **Unset only.** `SP_APPLY_TAG` refuses new `SET` |
| `RETIRED` | Withdrawn from the estate | No |

Two deliberate choices in that table:

**A deprecated tag can still be removed but not applied.** Migration off a tag
requires unsetting it thousands of times; blocking that would make deprecation
impossible.

**A retired tag's Snowflake object is not dropped.** `DROP TAG` succeeds even when
thousands of objects carry it, silently removing every assignment and detaching
any masking policy attached to it. It also breaks historical `ACCOUNT_USAGE`
queries an auditor may need. `SP_RETIRE_TAG` therefore refuses to drop anything:
it unsets assignments in a logged sweep and marks the definition `RETIRED`,
leaving the drop as a separate, deliberate act after the audit retention window.

## 1.7 Approval workflow

```
 Requester                EDGO                  Tag owner role         Council
     │                      │                          │                  │
     │ 1. PR to             │                          │                  │
     │    tag_catalog.yaml  │                          │                  │
     ├─────────────────────►│                          │                  │
     │                      │ 2. CI: schema, budget,   │                  │
     │                      │    consumer, collision   │                  │
     │                      │    checks                │                  │
     │                      ├─────────────────────────►│                  │
     │                      │            3. Does this  │                  │
     │                      │               duplicate  │                  │
     │                      │               an existing│                  │
     │                      │               tag/value? │                  │
     │                      │◄─────────────────────────┤                  │
     │                      │                          │                  │
     │                      │ 4. Tier 1/2 only ────────┼─────────────────►│
     │                      │                          │   5. Approve /   │
     │                      │◄─────────────────────────┼──── reject ──────┤
     │                      │                          │                  │
     │                      │ 6. Merge → CI deploys to non-prod           │
     │                      │ 7. Soak 2 weeks → deploy to prod            │
     │◄─────────────────────┤ 8. Announce, update enablement material     │
```

CI does the mechanical review before a human reads the request, which is what
keeps the council's agenda about substance:

- schema and referential integrity of the catalog;
- the mandatory-load budget per object type is not breached;
- `drives` is non-empty (P1);
- controlled vocabularies are within Snowflake's 300-value ceiling;
- generated SQL and docs are in sync with the catalog.

**The question the council actually asks** is not "is this tag useful?" — every
proposed tag is useful to somebody. It is: *what breaks if we don't have it, and
can an existing tag carry a new value instead?* (P7). Most proposals fail that
question, which is the point.

## 1.8 Ownership model

Four distinct accountabilities, deliberately not collapsed — they routinely sit
with different people, and merging them is how ownership becomes nobody's job.

| Role | Tag | Accountable for | Typically |
|---|---|---|---|
| **Data owner** | `DATA_OWNER` | The data: access approval, classification, retention | Business executive |
| **Data steward** | `DATA_STEWARD` | Day-to-day governance execution | Analyst / lead in the domain |
| **Data product owner** | `DATA_PRODUCT_OWNER` | Roadmap, SLA and consumer contract | Product manager |
| **Support group** | `SUPPORT_GROUP` | Break/fix, on-call | Engineering team |

`DATA_OWNER` is accountable, `DATA_STEWARD` is responsible: the owner decides that
a dataset is RESTRICTED, the steward makes the estate reflect that. The tag
`owner_role` field in the catalog is a fifth, different thing — who owns the
*definition* of the tag, e.g. the Privacy Office owns what `PII` means, not any
particular assignment of it.

## 1.9 Stewardship responsibilities

| Cadence | Activity | Evidence |
|---|---|---|
| Continuous | Tag new objects at creation via CI/CD | `TAG_CHANGE_LOG.SOURCE = 'CICD'` |
| Daily | Work the top of `VW_STEWARD_WORKLIST` | Findings closed |
| Weekly | Review auto-classification proposals | `CLASSIFICATION_RECONCILIATION` state moves off `UNREVIEWED` |
| Monthly | Confirm ownership tags still name real people | Attestation record |
| Quarterly | Re-attest RESTRICTED / HIGHLY_RESTRICTED classifications and open exceptions | Signed attestation |
| Quarterly | Domain input to taxonomy review | Council minutes |
| Annually | Full domain metadata review | Domain governance report |

### Making stewardship possible

Stewardship fails when it is a list of obligations with no support. Three things
carry more weight than any policy document:

1. **The worklist is ranked, not dumped.** `VW_STEWARD_WORKLIST` orders by
   severity and then by blast radius, so a single database-level fix that clears
   four thousand child findings appears above a single column.
2. **Tagging is one procedure call, not a DDL exercise.** `SP_APPLY_TAG` validates,
   applies and audits in one step and returns a plain-language rejection when it
   refuses.
3. **The centre owns the first 80%.** Automation sets `ENVIRONMENT`,
   `DATA_LIFECYCLE`, `PII` (proposed) and `DATA_QUALITY_TIER`. Stewards are asked
   for judgement, not data entry (P8).
