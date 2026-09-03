"""Tests for the code generators and the SQL linter.

The generators are the reason the published taxonomy and the deployed tags
cannot diverge, so their output properties are worth pinning.
"""
import os
import re
import subprocess
import sys

import pytest

import catalog as C
import generate_sql
import lint_sql

REPO = C.REPO_ROOT
GEN_DIR = os.path.join(REPO, "sql", "_generated")


@pytest.fixture(scope="module")
def tag_ddl(cat):
    return generate_sql.gen_tag_ddl(cat)


@pytest.fixture(scope="module")
def seed(cat):
    return generate_sql.gen_catalog_seed(cat)


# ---------------------------------------------------------------------------
# Destructive-DDL guarantees
# ---------------------------------------------------------------------------

def _executable(sql: str) -> str:
    """Strip comment lines. The file's own header explains why CREATE OR REPLACE
    TAG is forbidden, so a naive scan of the whole text matches the warning."""
    return "\n".join(l for l in sql.splitlines() if not l.lstrip().startswith("--"))


def test_generated_ddl_never_replaces_a_tag(tag_ddl):
    """CREATE OR REPLACE TAG drops every assignment across the account."""
    body = _executable(tag_ddl)
    assert not re.search(r"CREATE\s+OR\s+REPLACE\s+TAG", body, re.I)
    assert not re.search(r"^\s*DROP\s+TAG", body, re.I | re.M)


def test_generated_ddl_is_idempotent_in_shape(tag_ddl, cat):
    """Every tag is created with IF NOT EXISTS and updated with ALTER, so the
    file is safe to re-run against a populated account."""
    for t in cat["tags"]:
        fq = f"GOVERNANCE.TAGS.{t['name']}"
        assert f"CREATE TAG IF NOT EXISTS {fq}" in tag_ddl
        assert f"ALTER TAG {fq} SET COMMENT" in tag_ddl


def test_vocabulary_changes_deploy_additively(tag_ddl, cat):
    for t in cat["tags"]:
        if t.get("allowed_values"):
            assert f"ALTER TAG GOVERNANCE.TAGS.{t['name']} ADD ALLOWED_VALUES" in tag_ddl


# ---------------------------------------------------------------------------
# SQL literal escaping
# ---------------------------------------------------------------------------

def test_backslashes_are_doubled_for_snowflake():
    """Snowflake processes backslash escapes inside single-quoted literals, so
    a regex \\. would arrive as a bare . and match any character."""
    out = C.sql_str(r"^[a-z]+@[a-z]+\.[a-z]{2,}$")
    assert r"\\." in out
    assert out.startswith("'") and out.endswith("'")


def test_single_quotes_are_doubled():
    assert C.sql_str("O'Brien") == "'O''Brien'"


def test_none_becomes_null():
    assert C.sql_str(None) == "NULL"


def test_seed_preserves_regex_semantics(seed, cat):
    """The email/principal regex must survive the round trip into SQL intact."""
    principal = cat["value_formats"]["principal"]
    assert principal.replace("\\", "\\\\") in seed


def test_descriptions_with_apostrophes_are_escaped(seed):
    """Several descriptions contain RACI 'A' / 'R'."""
    for line in seed.splitlines():
        if line.strip().startswith("('"):
            # A correctly escaped row has an even number of quotes.
            assert line.count("'") % 2 == 0, f"unbalanced quoting: {line[:80]}"


# ---------------------------------------------------------------------------
# Registry seed completeness
# ---------------------------------------------------------------------------

def test_seed_loads_every_tag(seed, cat):
    for t in cat["tags"]:
        assert f"'{t['name']}'" in seed


def test_seed_is_transactional(seed):
    """The validation task reads these tables on a schedule and must never see
    the registry half-loaded."""
    assert "BEGIN TRANSACTION;" in seed
    assert "COMMIT;" in seed
    assert seed.index("BEGIN TRANSACTION;") < seed.index("DELETE FROM TAG_CATALOG;")
    assert seed.rindex("INSERT INTO") < seed.rindex("COMMIT;")


def test_seed_deletes_children_before_parents(seed):
    """TAG_CATALOG is the FK parent of TAG_REQUIREMENT and TAG_ALLOWED_VALUE."""
    order = [seed.index(f"DELETE FROM {t};") for t in
             ("TAG_REQUIREMENT", "TAG_ALLOWED_VALUE", "TAG_CATALOG")]
    assert order == sorted(order)


def test_seed_omits_not_applicable_rows(seed, cat):
    assert "'NOT_APPLICABLE'" not in seed


def test_seed_uses_insert_select_for_variant_columns(seed):
    """INSERT ... VALUES cannot carry PARSE_JSON in Snowflake."""
    assert "PARSE_JSON(" in seed
    assert "FROM VALUES" in seed


# ---------------------------------------------------------------------------
# Masking attachment generation
# ---------------------------------------------------------------------------

def test_masking_bindings_emit_one_alter_per_data_type(cat):
    out = generate_sql.gen_masking_bindings(cat)
    for b in cat["masking_bindings"]:
        for dt in b["data_types"]:
            assert (f"ALTER TAG GOVERNANCE.TAGS.{b['tag']} SET MASKING POLICY "
                    f"GOVERNANCE.POLICIES.{b['policy_prefix']}_{dt};") in out


def test_no_masking_attachment_for_privacy_tags(cat):
    """PII/PHI/PCI are read inside the policy body, never attached."""
    out = generate_sql.gen_masking_bindings(cat)
    for tag in ("PII", "PHI", "PCI", "SENSITIVE_DATA"):
        assert f"ALTER TAG GOVERNANCE.TAGS.{tag} SET MASKING POLICY" not in out


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("fn", ["gen_tag_ddl", "gen_catalog_seed",
                                "gen_masking_bindings"])
def test_generation_is_deterministic(cat, fn):
    """Non-deterministic output would make the CI staleness check flap."""
    f = getattr(generate_sql, fn)
    assert f(cat) == f(cat)


def test_committed_artifacts_are_current():
    """Same check CI runs: generated files must match a fresh generation."""
    result = subprocess.run(
        [sys.executable, "generate_sql.py", "--check"],
        cwd=os.path.join(REPO, "scripts"), capture_output=True, text=True)
    assert result.returncode == 0, result.stdout


def test_generated_files_carry_the_do_not_edit_banner():
    for fname in os.listdir(GEN_DIR):
        if fname.endswith(".sql"):
            with open(os.path.join(GEN_DIR, fname)) as fh:
                assert "GENERATED FILE - DO NOT EDIT" in fh.read(600)


# ---------------------------------------------------------------------------
# Linter
# ---------------------------------------------------------------------------

def _rule(rule_id):
    return next(r for r in lint_sql.RULES if r[0] == rule_id)


@pytest.mark.parametrize("rule_id,sample", [
    ("SQL001", "CREATE OR REPLACE TAG GOVERNANCE.TAGS.PII;"),
    ("SQL002", "DROP TAG GOVERNANCE.TAGS.PII;"),
    ("SQL003", "DROP MASKING POLICY MP_ENTERPRISE_STRING;"),
    ("SQL005", "CREATE USER x PASSWORD = 'hunter2secret';"),
    ("SQL006", "GRANT APPLY TAG ON ACCOUNT TO ROLE DATA_ENGINEER;"),
    ("SQL007", "WHERE CURRENT_ROLE() = 'PII_UNMASKED'"),
])
def test_linter_catches_unsafe_sql(rule_id, sample):
    assert _rule(rule_id)[1].search(sample), f"{rule_id} missed: {sample}"


@pytest.mark.parametrize("rule_id,sample", [
    ("SQL001", "CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PII;"),
    ("SQL002", "ALTER TAG GOVERNANCE.TAGS.PII UNSET ALLOWED_VALUES;"),
    ("SQL006", "GRANT APPLY TAG ON ACCOUNT TO ROLE TAG_ADMIN;"),
    ("SQL007", "WHERE IS_ROLE_IN_SESSION('PII_UNMASKED')"),
])
def test_linter_allows_the_safe_form(rule_id, sample):
    assert not _rule(rule_id)[1].search(sample), f"{rule_id} false positive"


def test_repository_sql_passes_the_linter():
    result = subprocess.run(
        [sys.executable, "lint_sql.py"],
        cwd=os.path.join(REPO, "scripts"), capture_output=True, text=True)
    assert result.returncode == 0, result.stdout
