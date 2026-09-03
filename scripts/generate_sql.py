#!/usr/bin/env python3
"""Generate deployable Snowflake DDL from config/tag_catalog.yaml.

Emits into sql/_generated/:
    10_tag_ddl.sql             CREATE/ALTER TAG for every catalog tag
    11_catalog_seed.sql        full refresh of the CONTROL registry tables
    12_masking_tag_bindings.sql  ALTER TAG ... SET MASKING POLICY attachments

Why generate rather than hand-write
-----------------------------------
The taxonomy is reviewed as YAML by governance people and consumed as SQL by
Snowflake. Generating one from the other removes the whole class of defect where
the published matrix and the deployed tag disagree.
"""
from __future__ import annotations

import os
import sys

import catalog as C

OUT_DIR = os.path.join(C.REPO_ROOT, "sql", "_generated")


def _tag_fqn(cat: dict, name: str) -> str:
    """Fully qualified Snowflake identifier for a tag.

    Canonical keys are lowercase; Snowflake folds unquoted identifiers to upper
    case, so the DDL is emitted upper-cased to match what ACCOUNT_USAGE returns
    and what every policy body and join will reference.
    """
    d = cat["deployment"]
    return f"{d['governance_database']}.{d['tag_schema']}.{C.snowflake_name(name)}"


def gen_tag_ddl(cat: dict) -> str:
    d = cat["deployment"]
    out = [C.GENERATED_HEADER]
    out.append(f"""
-- -----------------------------------------------------------------------------
-- Enterprise tag object DDL
-- -----------------------------------------------------------------------------
-- WARNING: never use CREATE OR REPLACE TAG on a live account. Replacing a tag
-- DROPS every assignment of it across the estate, silently detaching any masking
-- policy bound to it. This file therefore only ever uses CREATE TAG IF NOT
-- EXISTS plus ALTER TAG, which are safe to re-run against a populated account.
--
-- Vocabulary changes: ADD ALLOWED_VALUES is additive and safe. REMOVING a value
-- is a breaking change - Snowflake rejects DROP ALLOWED_VALUES while any object
-- still carries that value, so run the retirement playbook first
-- (docs/08-enterprise-standards.md#tag-retirement-process).
-- -----------------------------------------------------------------------------

USE ROLE {d['roles']['admin']};
USE WAREHOUSE {d['warehouse']};
USE DATABASE {d['governance_database']};
USE SCHEMA {d['tag_schema']};
""".rstrip())

    for tier in (1, 2, 3):
        tier_tags = C.tags(cat, tier)
        if not tier_tags:
            continue
        label = {1: "TIER 1 - CORE MANDATORY", 2: "TIER 2 - GOVERNANCE",
                 3: "TIER 3 - OPTIONAL / DOMAIN"}[tier]
        out.append(f"\n\n-- ===========================================================================")
        out.append(f"-- {label}  ({len(tier_tags)} tags)")
        out.append(f"-- ===========================================================================")
        for t in tier_tags:
            out.append(_one_tag_ddl(cat, t))
    out.append("\nSELECT 'Tag DDL applied' AS status;\n")
    return "\n".join(out)


def _one_tag_ddl(cat: dict, t: dict) -> str:
    name = t["name"]
    fq = _tag_fqn(cat, name)
    comment = C.one_line(t["description"])
    lines = [
        f"\n-- {name}  ->  Snowflake identifier {C.snowflake_name(name)}",
        f"-- Tier {t['tier']} | {t['level']} | {t['category']} | "
        f"owner {t['owner_role']} | platforms: {', '.join(t.get('platforms', []))}",
    ]

    allowed = t.get("allowed_values")
    if allowed:
        values = ", ".join(C.sql_str(v) for v in allowed)
        lines.append(f"CREATE TAG IF NOT EXISTS {fq}")
        lines.append(f"    ALLOWED_VALUES {values}")
        lines.append(f"    COMMENT = {C.sql_str(comment)};")
        # Re-runs: additive, so a vocabulary extension deploys without a drop.
        lines.append(f"ALTER TAG {fq} ADD ALLOWED_VALUES {values};")
    else:
        src = t["value_source"]
        note = ("validated against CONTROL.REFERENCE_VALUE"
                if src == "reference_data" else "format-validated by SP_APPLY_TAG")
        lines.append(f"-- No ALLOWED_VALUES: {src}, {note}.")
        lines.append(f"CREATE TAG IF NOT EXISTS {fq}")
        lines.append(f"    COMMENT = {C.sql_str(comment)};")

    lines.append(f"ALTER TAG {fq} SET COMMENT = {C.sql_str(comment)};")
    return "\n".join(lines)


def _values_block(rows: list[tuple], cols: list[str], projections: list[str],
                  table: str) -> str:
    """Render INSERT ... SELECT ... FROM VALUES, which (unlike INSERT VALUES)
    permits PARSE_JSON and other expressions."""
    if not rows:
        return f"-- no rows for {table}\n"
    body = ",\n".join("    (" + ", ".join(r) + ")" for r in rows)
    alias_cols = ", ".join(f"c{i+1}" for i in range(len(cols)))
    return (
        f"INSERT INTO {table} ({', '.join(cols)})\n"
        f"SELECT {', '.join(projections)}\n"
        f"FROM VALUES\n{body}\n"
        f"AS v({alias_cols});\n"
    )


def gen_catalog_seed(cat: dict) -> str:
    d = cat["deployment"]
    db, ctl = d["governance_database"], d["control_schema"]
    out = [C.GENERATED_HEADER]
    out.append(f"""
-- -----------------------------------------------------------------------------
-- Full refresh of the tag registry from the catalog.
-- Wrapped in a transaction so the registry is never observed half-loaded by the
-- validation task, which reads these tables on a schedule.
-- -----------------------------------------------------------------------------

USE ROLE {d['roles']['admin']};
USE WAREHOUSE {d['warehouse']};
USE DATABASE {db};
USE SCHEMA {ctl};

BEGIN TRANSACTION;

DELETE FROM TAG_REQUIREMENT;
DELETE FROM TAG_ALLOWED_VALUE;
DELETE FROM TAG_POLICY_BINDING;
DELETE FROM TAG_CONDITIONAL_RULE;
DELETE FROM TAG_CONTRADICTION_RULE;
DELETE FROM VALUE_PRECEDENCE;
DELETE FROM TAG_CATALOG;
""".rstrip())

    cv = cat["metadata"]["catalog_version"]

    # --- TAG_CATALOG -------------------------------------------------------
    rows = []
    for t in cat["tags"]:
        ordinals = t.get("ordinal_values")
        rows.append((
            # Upper-cased: TAG_CATALOG is joined to ACCOUNT_USAGE.TAG_REFERENCES,
            # which reports the folded Snowflake identifier. Storing the
            # lowercase canonical key here would make every one of those joins
            # miss silently.
            C.sql_str(C.snowflake_name(t)),
            C.sql_str(t["name"]),
            C.sql_str(t.get("level")),
            C.sql_str(_json(t.get("platforms", []))),
            C.sql_str(t.get("hierarchy_requirement")),
            str(t["tier"]),
            C.sql_str(t["category"]),
            C.sql_str(C.one_line(t["description"])),
            C.sql_str(t["value_source"]),
            C.sql_str(C.resolve_format(cat, t)),
            C.sql_str(t.get("reference_table")),
            C.sql_str(t["inheritance"]),
            C.sql_str(t["override_rule"]),
            C.sql_str(_json(ordinals)) if ordinals else "NULL",
            C.sql_str(_json(t["drives"])),
            C.sql_str(t["owner_role"]),
            C.sql_str(t["version"]),
            C.sql_str(t.get("status", "ACTIVE")),
            C.sql_str(t.get("deprecates")),
            C.sql_str(cv),
        ))
    cols = ["TAG_NAME", "CANONICAL_KEY", "HIERARCHY_LEVEL", "PLATFORMS",
            "HIERARCHY_REQUIREMENT", "TIER", "CATEGORY", "DESCRIPTION",
            "VALUE_SOURCE", "VALUE_FORMAT_REGEX", "REFERENCE_SET",
            "INHERITANCE_MODE", "OVERRIDE_RULE", "ORDINAL_VALUES", "DRIVES",
            "OWNER_ROLE", "TAG_VERSION", "STATUS", "DEPRECATES", "CATALOG_VERSION"]
    proj = ["c1", "c2", "c3", "PARSE_JSON(c4)::ARRAY", "c5",
            "c6::NUMBER(1,0)", "c7", "c8", "c9", "c10", "c11", "c12", "c13",
            "PARSE_JSON(c14)::ARRAY", "PARSE_JSON(c15)::ARRAY", "c16", "c17",
            "c18", "c19", "c20"]
    out.append("\n-- TAG_CATALOG")
    out.append(_values_block(rows, cols, proj, "TAG_CATALOG"))

    # --- TAG_ALLOWED_VALUE -------------------------------------------------
    rows = []
    for t in cat["tags"]:
        allowed = t.get("allowed_values") or []
        ordinals = t.get("ordinal_values") or []
        for v in allowed:
            pos = ordinals.index(v) + 1 if v in ordinals else None
            rows.append((C.sql_str(C.snowflake_name(t)), C.sql_str(v),
                         str(pos) if pos else "NULL"))
    out.append("\n-- TAG_ALLOWED_VALUE")
    out.append(_values_block(
        rows, ["TAG_NAME", "TAG_VALUE", "ORDINAL_POSITION"],
        ["c1", "c2", "c3::NUMBER(5,0)"], "TAG_ALLOWED_VALUE"))

    # --- TAG_REQUIREMENT ---------------------------------------------------
    rows = []
    for t in cat["tags"]:
        for ot in cat["object_types"]["all"]:
            level = C.requirement(t, ot)
            if level == "NOT_APPLICABLE":
                continue  # keep the table to the meaningful surface
            rows.append((C.sql_str(C.snowflake_name(t)), C.sql_str(ot),
                         C.sql_str(level)))
    out.append("\n-- TAG_REQUIREMENT")
    out.append(_values_block(
        rows, ["TAG_NAME", "OBJECT_TYPE", "REQUIREMENT_LEVEL"],
        ["c1", "c2", "c3"], "TAG_REQUIREMENT"))

    # --- TAG_CONDITIONAL_RULE ---------------------------------------------
    rows = []
    for r in cat.get("conditional_rules", []):
        rows.append((
            C.sql_str(r["id"]),
            C.sql_str(C.one_line(r["description"])),
            C.sql_str(r["severity"]),
            C.sql_str(_json(r.get("object_types", []))),
            C.sql_str(_json({C.snowflake_name(k): v
                             for k, v in (r.get("when") or {}).items()})),
            C.sql_str(_json([C.snowflake_name(t)
                             for t in r.get("then_mandatory", [])])),
        ))
    out.append("\n-- TAG_CONDITIONAL_RULE")
    out.append(_values_block(
        rows,
        ["RULE_ID", "DESCRIPTION", "SEVERITY", "OBJECT_TYPES", "PREDICATE",
         "THEN_MANDATORY"],
        ["c1", "c2", "c3", "PARSE_JSON(c4)::ARRAY", "PARSE_JSON(c5)::OBJECT",
         "PARSE_JSON(c6)::ARRAY"],
        "TAG_CONDITIONAL_RULE"))

    # --- TAG_POLICY_BINDING ------------------------------------------------
    rows = []
    for b in cat.get("masking_bindings", []):
        for dt in b.get("data_types", []):
            policy = f"{b['policy_prefix']}_{dt}"
            rows.append((
                C.sql_str(C.snowflake_name(b["tag"])), "NULL", C.sql_str("MASKING"),
                C.sql_str(f"{db}.{d['policy_schema']}.{policy}"),
                C.sql_str(dt), C.sql_str("TAG_ATTACHED"),
                C.sql_str(C.one_line(b.get("note"))) if b.get("note") else "NULL",
            ))
    for b in cat.get("row_access_bindings", []):
        rows.append((
            C.sql_str(C.snowflake_name(b["tag"])), C.sql_str(b.get("value")),
            C.sql_str("ROW_ACCESS"),
            C.sql_str(f"{db}.{d['policy_schema']}.{b['policy']}"),
            "NULL", C.sql_str("RECONCILED"),
            C.sql_str(C.one_line(b.get("note"))) if b.get("note") else "NULL",
        ))
    out.append("\n-- TAG_POLICY_BINDING")
    out.append(_values_block(
        rows,
        ["TAG_NAME", "TAG_VALUE", "POLICY_KIND", "POLICY_NAME", "DATA_TYPE",
         "ATTACH_MODE", "NOTES"],
        ["c1", "c2", "c3", "c4", "c5", "c6", "c7"], "TAG_POLICY_BINDING"))

    # --- TAG_CONTRADICTION_RULE -------------------------------------------
    rows = []
    for r in cat.get("contradiction_rules", []):
        rows.append((
            C.sql_str(r["id"]),
            C.sql_str(C.one_line(r["description"])),
            C.sql_str(r["severity"]),
            C.sql_str(C.snowflake_name(r["if_tag"])),
            C.sql_str(_json(r["if_values"])),
            C.sql_str(C.snowflake_name(r["then_tag"])),
            C.sql_str(_json(r["forbidden_values"])),
        ))
    out.append("\n-- TAG_CONTRADICTION_RULE")
    out.append(_values_block(
        rows,
        ["RULE_ID", "DESCRIPTION", "SEVERITY", "IF_TAG", "IF_VALUES",
         "THEN_TAG", "FORBIDDEN_VALUES"],
        ["c1", "c2", "c3", "c4", "PARSE_JSON(c5)::ARRAY", "c6",
         "PARSE_JSON(c7)::ARRAY"],
        "TAG_CONTRADICTION_RULE"))

    # --- VALUE_PRECEDENCE -------------------------------------------------
    # One table for both precedence lists: the governing value of any
    # single-valued tag that can hold several truths at once resolves the same
    # way, so it is one mechanism rather than two.
    rows = []
    for tag_name, key in (("data_classification_regulatory",
                           "regulatory_category_precedence"),
                          ("regulation", "regulation_precedence")):
        for i, v in enumerate(cat.get(key, [])):
            rows.append((C.sql_str(C.snowflake_name(tag_name)), C.sql_str(v),
                         str(i + 1)))
    out.append("\n-- VALUE_PRECEDENCE")
    out.append(_values_block(
        rows, ["TAG_NAME", "TAG_VALUE", "PRECEDENCE_ORDER"],
        ["c1", "c2", "c3::NUMBER(3,0)"], "VALUE_PRECEDENCE"))

    out.append("COMMIT;\n")
    out.append("SELECT COUNT(*) AS tags_registered FROM TAG_CATALOG;\n")
    return "\n".join(out)


def gen_masking_bindings(cat: dict) -> str:
    d = cat["deployment"]
    db, pol = d["governance_database"], d["policy_schema"]
    out = [C.GENERATED_HEADER]
    out.append(f"""
-- -----------------------------------------------------------------------------
-- Tag-based masking policy attachment
-- -----------------------------------------------------------------------------
-- Run AFTER sql/20_policies/*.sql has created the policies themselves.
--
-- Snowflake permits at most ONE masking policy per data type per tag. Attaching
-- a policy to a tag makes every column that carries the tag masked, now and in
-- future, without touching the column - this is the single highest-leverage
-- control in the framework.
--
-- Row access policies CANNOT be attached to tags. They are applied by
-- AUTOMATION.SP_APPLY_ROW_ACCESS_POLICIES instead; see
-- docs/05-security-compliance-integration.md.
-- -----------------------------------------------------------------------------

USE ROLE {d['roles']['admin']};
USE WAREHOUSE {d['warehouse']};
USE DATABASE {db};
USE SCHEMA {d['tag_schema']};
""".rstrip())

    for b in cat.get("masking_bindings", []):
        tag_fq = _tag_fqn(cat, b["tag"])
        out.append(f"\n-- {b['tag']}")
        if b.get("note"):
            out.append(f"-- {C.one_line(b['note'])}")
        for dt in b["data_types"]:
            policy = f"{db}.{pol}.{b['policy_prefix']}_{dt}"
            out.append(f"ALTER TAG {tag_fq} SET MASKING POLICY {policy};")

    out.append("""
-- Verification: every attachment above should appear here.
SELECT tag_database, tag_schema, tag_name, policy_db, policy_schema, policy_name
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
        POLICY_KIND => 'MASKING_POLICY'))
WHERE tag_name IS NOT NULL
ORDER BY tag_name, policy_name;
""")
    return "\n".join(out)


def _json(value) -> str:
    import json
    return json.dumps(value)


def main() -> int:
    cat = C.load()
    os.makedirs(OUT_DIR, exist_ok=True)
    artifacts = {
        "10_tag_ddl.sql": gen_tag_ddl(cat),
        "11_catalog_seed.sql": gen_catalog_seed(cat),
        "12_masking_tag_bindings.sql": gen_masking_bindings(cat),
    }
    check = "--check" in sys.argv
    stale = []
    for fname, content in artifacts.items():
        path = os.path.join(OUT_DIR, fname)
        if check:
            existing = open(path).read() if os.path.exists(path) else None
            if existing != content:
                stale.append(fname)
        else:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(content)
            print(f"wrote {os.path.relpath(path, C.REPO_ROOT)} "
                  f"({len(content.splitlines())} lines)")
    if check:
        if stale:
            print("STALE generated SQL (run `make build` and commit): "
                  + ", ".join(stale))
            return 1
        print("OK: generated SQL is up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
