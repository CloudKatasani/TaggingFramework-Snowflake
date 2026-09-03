# 8. Enterprise Standards

## 8.1 Naming convention

Summarised from [strategy §1.4](01-tagging-strategy.md#14-naming-standards);
the rules exist as machine checks in `scripts/validate_catalog.py`.

**Identifiers** — `^[A-Z][A-Z0-9_]{1,63}$`, singular nouns, no prefixes, no
abbreviations beyond enterprise terms of art, no environment/region/team names,
boolean tags named for the positive assertion.

**Values** — `UPPER_SNAKE_CASE`; ordinal vocabularies ordered least → most severe;
thresholds carried in the value (`PLATINUM_15M`, `EXTENDED_7Y`); reference values
keep the source system's prefixed format.

**Namespace** — `GOVERNANCE.TAGS` only, enforced by granting `CREATE TAG` on
exactly one schema to exactly one role.

Two conventions that are easy to get wrong and expensive to fix later:

| Wrong | Right | Why |
|---|---|---|
| `IS_PII` / `HAS_PII` / `PII_FLAG` | `PII` | Three names for one concept is the origin of every duplicated tag |
| `PROD_DATA_OWNER` | `DATA_OWNER` + `ENVIRONMENT` | Encoding a dimension in the name guarantees one tag per value of that dimension |
| `NO_LEGAL_HOLD` | `LEGAL_HOLD` | Negative names produce double negatives in policy predicates |
| `DATA_CLASSIFICATION_V2` | version the definition, not the name | Consumers must not be broken by a versioning scheme |

## 8.2 Allowed-values strategy

| Source | Criteria | Enforcement | Change cost |
|---|---|---|---|
| `controlled_vocabulary` | ≤ ~30 values, stable, enterprise-owned | Snowflake `ALLOWED_VALUES`, at `SET` time | Catalog PR + deploy |
| `reference_data` | Large or volatile, owned elsewhere | `SP_APPLY_TAG` + nightly re-validation | Data load |
| `free_text` | Genuinely open | Regex in `SP_APPLY_TAG` | None |

**Adding a value** to a controlled vocabulary is additive and safe:
`ALTER TAG ... ADD ALLOWED_VALUES`. It is the preferred answer to most "we need a
new tag" requests (principle P7).

**Removing a value** is a breaking change. Snowflake rejects
`DROP ALLOWED_VALUES` while any object still carries the value, which is helpful
— it forces the migration to happen first:

1. Announce; 90-day notice.
2. Add the replacement value.
3. Migrate assignments with `SP_APPLY_TAG`, reason `Value migration <old> → <new>`.
4. Confirm zero assignments via `VW_TAG_ADOPTION`.
5. `ALTER TAG ... DROP ALLOWED_VALUES '<old>'`.
6. Update the catalog and regenerate.

**The ordering trap.** For an ordinal vocabulary, inserting a value in the middle
changes every ordinal position after it. `TAG_ALLOWED_VALUE.ORDINAL_POSITION` is
what "most restrictive wins" compares, so an insertion silently changes the
resolution of every affected object. Ordinal changes require an explicit
re-evaluation of affected objects and a council decision — never a routine catalog
edit.

## 8.3 Versioning

Two independently versioned things, deliberately separated:

**Catalog version** (`metadata.catalog_version`) — SemVer for the taxonomy as a
whole. Recorded on every registry row so a finding can be traced to the catalog
that produced it.

| Change | Bump |
|---|---|
| New Tier 3 tag; new allowed value; description edit | PATCH |
| New Tier 1/2 tag; requirement level raised; new conditional rule | MINOR |
| Tag retired; value removed; ordinal reordered; override rule changed | MAJOR |

**Tag version** (`version` per tag) — SemVer for one tag's definition, so a change
to `PII` does not imply a change to `COST_CENTER`.

**Tag identifiers are never versioned.** No `DATA_CLASSIFICATION_V2`. A tag whose
meaning changes so much that consumers must be rewritten is a new tag with a new
name and a deprecation path for the old one — which is the honest description of
what has happened, and it lets the two coexist during migration.

## 8.4 Tag retirement

`DROP TAG` succeeds even when thousands of objects carry the tag. It silently
removes every assignment and detaches any masking policy attached to it. Nothing
warns you, and the estate is unprotected from that moment.

`SP_RETIRE_TAG` therefore **never drops anything**:

```sql
-- 1. What would this destroy?
CALL GOVERNANCE.AUTOMATION.SP_RETIRE_TAG('CAPABILITY', FALSE);
--    "DRY RUN: retiring CAPABILITY would unset 1,247 assignment(s)."

-- 2. Execute the sweep. Blocked outright if any policy binding is still active.
CALL GOVERNANCE.AUTOMATION.SP_RETIRE_TAG('CAPABILITY', TRUE);
```

Full process:

| Step | Action | Gate |
|---|---|---|
| 1 | Adoption review identifies the candidate | `VW_TAG_ADOPTION` verdict |
| 2 | Council approves retirement | Minuted |
| 3 | Status → `DEPRECATED`; 90-day notice | `SP_APPLY_TAG` now refuses new `SET`, still allows `UNSET` |
| 4 | Consumers migrated | `drives` list emptied |
| 5 | Policy bindings detached | `SP_RETIRE_TAG` blocks while any remain |
| 6 | Assignments swept | Every removal logged |
| 7 | Status → `RETIRED` | 180-day grace |
| 8 | `DROP TAG` — optional, after audit retention | Separate, deliberate act |

Step 8 is usually skipped. The Snowflake tag object costs nothing, and keeping it
means historical `ACCOUNT_USAGE` queries an auditor may run still resolve the
name. There is no benefit to the drop that outweighs that.

## 8.5 Exception management

Every framework meets an object that legitimately cannot comply — a vendor-managed
schema that rejects DDL, a legacy table whose owner left, a migration in flight.
Without a formal path, teams either stall or quietly disable the control. The
second is worse and far more common.

`CONTROL.TAG_EXCEPTION` requires, structurally:

| Field | Why it is mandatory |
|---|---|
| `JUSTIFICATION` | Free text, but reviewed |
| `COMPENSATING_CONTROL` | **What protects the data meanwhile.** An exception with no compensating control is not an exception, it is an accepted breach |
| `APPROVED_BY` | A named person |
| `RISK_ACCEPTED_BY` | Required for CRITICAL severity — a risk owner, not a governance team |
| `EXPIRES_AT` | `NOT NULL`. There are no permanent exceptions |

```sql
INSERT INTO GOVERNANCE.CONTROL.TAG_EXCEPTION
    (OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, OBJECT_TYPE, TAG_NAME,
     EXCEPTION_TYPE, JUSTIFICATION, COMPENSATING_CONTROL,
     REQUESTED_BY, APPROVED_BY, EXPIRES_AT)
SELECT 'VENDOR_DB', 'SAAS_EXPORT', 'RAW_EVENTS', 'TABLE', 'DATA_CLASSIFICATION',
       'MISSING_TAG',
       'Vendor-managed schema; DDL is rejected by the vendor pipeline. '
       || 'Vendor remediation ticket VEN-4417, committed for Q3.',
       'Schema is accessible only to VENDOR_INGEST_ROLE; a downstream governed '
       || 'copy carries full classification and is the only consumer surface.',
       CURRENT_USER(), 'jane.doe@example.com',
       DATEADD('day', 90, CURRENT_TIMESTAMP());
```

Lifecycle:

- `SP_VALIDATE_COMPLIANCE` suppresses findings covered by a live exception —
  suppresses, not deletes: the finding exists with status `EXCEPTED`, so the
  exception's blast radius is always visible.
- On expiry, status flips to `EXPIRED` and the underlying finding is **re-raised at
  HIGH severity**. Lapsing is not a quiet way out.
- `ALERT_EXPIRING_EXCEPTIONS` warns 14 days ahead.
- Renewal requires fresh justification, not a date extension. If the compensating
  control has held for 90 days and the fix is no closer, that is a decision to
  escalate rather than a form to re-file.

**Exception debt is a governance KPI.** `OPEN_EXCEPTIONS` is on the executive
dashboard beside compliance percentage, because a 99% compliance score with 400
open exceptions is not a 99% compliance score.

## 8.6 Change management summary

| Change | Approver | Notice | Automation |
|---|---|---|---|
| New Tier 3 tag | Domain owner | — | Catalog PR |
| New Tier 1/2 tag | Council | — | Catalog PR + soak |
| Add allowed value | EDGO | — | `ALTER TAG ADD ALLOWED_VALUES` |
| Remove allowed value | Council | 90 days | Migration then `DROP ALLOWED_VALUES` |
| Reorder ordinals | Council | 90 days | Re-evaluate affected objects |
| Raise requirement level | Council | 30 days | Findings appear at next scan |
| Retire a tag | Council | 90 + 180 days | `SP_RETIRE_TAG` |
| Grant exception | EDGO + tag owner | — | `TAG_EXCEPTION` insert |
| Change a policy body | CISO + Council | — | SQL PR + review |
