"""Structural guarantees the rest of the framework relies on.

These are not restatements of validate_catalog.py. Each one pins a property some
piece of SQL or policy code assumes to be true, so that a plausible-looking
catalog edit fails here rather than in a Snowflake account.
"""
import re
import sys

import pytest

import catalog as C
sys.path.insert(0, "scripts")


def test_tier_sizes_match_published_framework(cat):
    """The README and docs quote these counts; they must stay true."""
    assert len(C.tags(cat, 1)) == 17
    assert len(C.tags(cat, 2)) == 14
    assert len(C.tags(cat, 3)) == 11
    assert len(cat["tags"]) == 42


def test_every_tag_has_a_consumer(cat):
    """Principle P1. A tag nothing reads is metadata debt."""
    orphans = [t["name"] for t in cat["tags"] if not t.get("drives")]
    assert orphans == [], f"tags with no consumer: {orphans}"


def test_control_tags_use_most_restrictive_resolution(cat, by_name):
    """AP-09: nearest-wins on a control tag silently unmasks data."""
    controls = ["DATA_CLASSIFICATION", "PII", "PHI", "PCI", "SENSITIVE_DATA",
                "MASKING_REQUIRED", "ROW_ACCESS_REQUIRED", "ENCRYPTION_REQUIRED",
                "LEGAL_HOLD", "CRITICALITY"]
    for name in controls:
        tag = by_name[name]
        assert tag["override_rule"] == "more_restrictive_only", (
            f"{name} is a control tag and must resolve most-restrictive-wins")
        assert tag.get("ordinal_values"), (
            f"{name} needs ordinal_values for 'most restrictive' to be computable")


def test_ordinals_run_least_to_most_restrictive(by_name):
    """VW_EFFECTIVE_TAG ranks by ORDINAL_POSITION descending, so the ordering
    direction is load-bearing, not documentation."""
    assert by_name["DATA_CLASSIFICATION"]["ordinal_values"] == [
        "PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED", "HIGHLY_RESTRICTED"]
    assert by_name["PII"]["ordinal_values"] == ["NO", "YES"]
    assert by_name["CRITICALITY"]["ordinal_values"] == [
        "LOW", "MEDIUM", "HIGH", "CRITICAL"]


def test_environment_cannot_be_overridden(by_name):
    """Section 4.6: a schema inside a PROD database must not declare itself DEV."""
    assert by_name["ENVIRONMENT"]["override_rule"] == "none"
    assert by_name["DATA_PRODUCT"]["override_rule"] == "none"


def test_quality_tier_is_never_inherited(by_name):
    """Certification is measured, not inherited from a neighbour."""
    assert by_name["DATA_QUALITY_TIER"]["inheritance"] == "explicit_only"


def test_exactly_one_tag_carries_masking_attachments(cat):
    """Two attached tags means a column carrying both has two candidate policies
    and resolution depends on lineage proximity rather than on risk."""
    bound = {b["tag"] for b in cat["masking_bindings"]}
    assert bound == {"DATA_CLASSIFICATION"}


def test_masking_policy_signals_reach_columns(cat, by_name):
    """A signal the policy body reads must be settable on a column, or the
    branch never fires and the control degrades silently."""
    for b in cat["masking_bindings"]:
        for signal in b.get("policy_reads_tags", []):
            level = C.requirement(by_name[signal], "COLUMN")
            assert level in {"MANDATORY", "RECOMMENDED"}, (
                f"{signal} is {level} on COLUMN but MP_* branches on it")


def test_masking_data_types_are_unique_per_tag(cat):
    """Snowflake allows one masking policy per data type per tag."""
    for b in cat["masking_bindings"]:
        dts = b["data_types"]
        assert len(dts) == len(set(dts))


def test_row_access_binding_is_reconciled_not_attached(cat):
    """Snowflake cannot attach row access policies to tags. Any catalog change
    implying otherwise would produce SQL that fails at deploy time."""
    assert cat["row_access_bindings"], "row access binding must be declared"
    for b in cat["row_access_bindings"]:
        assert b["tag"] == "ROW_ACCESS_REQUIRED"
        assert b["value"] == "YES"
        assert isinstance(b["value"], str)


def test_regulation_precedence_is_total(by_name, cat):
    """An unresolvable regime is a silent gap in compliance reporting."""
    declared = set(by_name["REGULATION"]["allowed_values"]) - {"MULTI"}
    precedence = cat["regulation_precedence"]
    assert set(precedence) == declared
    assert len(precedence) == len(set(precedence))
    assert precedence[0] == "HIPAA", "most prescriptive regime must rank first"
    assert precedence[-1] == "NONE"


def test_mandatory_load_stays_within_budget(cat):
    """The number that decides whether the framework is adoptable."""
    budget = cat["platform_limits"]["max_tags_directly_set_per_object_target"]
    for ot in cat["object_types"]["all"]:
        n = sum(1 for t in C.tags(cat) if C.requirement(t, ot) == "MANDATORY")
        assert n <= budget, f"{ot} requires {n} directly-set tags (budget {budget})"


def test_expected_mandatory_counts(cat):
    """Pinned because docs/02 §2.4 publishes these figures."""
    expected = {"SCHEMA": 10, "DATABASE": 8, "TABLE": 6, "SHARE": 5,
                "WAREHOUSE": 4, "VIEW": 4, "COLUMN": 2}
    for ot, n in expected.items():
        actual = sum(1 for t in C.tags(cat) if C.requirement(t, ot) == "MANDATORY")
        assert actual == n, f"{ot}: expected {n} mandatory tags, found {actual}"


def test_tier1_tags_are_mandatory_somewhere(cat):
    for t in C.tags(cat, 1):
        assert any(C.requirement(t, ot) == "MANDATORY"
                   for ot in cat["object_types"]["all"]), \
            f"{t['name']} is Tier 1 but mandatory nowhere"


def test_controlled_values_are_strings_not_yaml_booleans(cat):
    """YAML 1.1 turns bare YES/NO/ON/OFF into booleans, which would emit
    ALLOWED_VALUES 'True' into the generated DDL."""
    for t in cat["tags"]:
        for v in t.get("allowed_values") or []:
            assert isinstance(v, str), f"{t['name']}: {v!r} is not a string"


def test_allowed_values_within_snowflake_limits(cat):
    limit = cat["platform_limits"]["max_allowed_values_per_tag"]
    max_len = cat["platform_limits"]["max_tag_value_length"]
    for t in cat["tags"]:
        values = t.get("allowed_values") or []
        assert len(values) <= limit
        for v in values:
            assert len(v) <= max_len


def test_tag_names_follow_the_convention(cat):
    for t in cat["tags"]:
        assert C.TAG_NAME_RE.match(t["name"])
        assert not re.match(r"^(TAG|ENT|CORP)_", t["name"]), \
            f"{t['name']}: prefixes add length and distinguish nothing"
        assert not re.match(r"^(IS|HAS)_", t["name"]), \
            f"{t['name']}: boolean tags are named for the positive assertion"


def test_conditional_rules_are_enforceable(cat, by_name):
    """A rule targeting an object type the tag cannot be set on generates
    findings nobody can close."""
    for rule in cat["conditional_rules"]:
        for tag_name in rule["then_mandatory"]:
            for ot in rule["object_types"]:
                assert C.requirement(by_name[tag_name], ot) != "NOT_APPLICABLE", \
                    f"{rule['id']}: {tag_name} cannot be set on {ot}"


def test_share_rule_is_unconditional(cat):
    """CR-007: data leaving the account always needs an owner, a classification
    and an explicit distribution scope."""
    rule = next(r for r in cat["conditional_rules"] if r["id"] == "CR-007")
    assert rule["when"] in ({}, None)
    assert rule["object_types"] == ["SHARE"]
    assert set(rule["then_mandatory"]) == {
        "SHARING_SCOPE", "DATA_CLASSIFICATION", "DATA_PRODUCT_OWNER"}
    assert rule["severity"] == "CRITICAL"


def test_reference_data_tags_declare_their_source(cat):
    for t in cat["tags"]:
        if t["value_source"] == "reference_data":
            assert t.get("reference_table"), f"{t['name']} has no reference_table"
        else:
            assert not t.get("reference_table")


def test_value_formats_compile_and_accept_their_own_values(cat):
    for t in cat["tags"]:
        pattern = C.resolve_format(cat, t)
        if not pattern:
            continue
        compiled = re.compile(pattern)
        for v in t.get("allowed_values") or []:
            assert compiled.match(v), f"{t['name']}: '{v}' fails its own format"


@pytest.mark.parametrize("sample,should_match", [
    ("jane.doe@example.com", True),
    ("GRP-DATA-PLATFORM", True),
    ("not an email", False),
    ("", False),
])
def test_principal_format(cat, sample, should_match):
    pattern = re.compile(cat["value_formats"]["principal"])
    assert bool(pattern.match(sample)) is should_match


@pytest.mark.parametrize("sample,should_match", [
    ("CC-004120", True), ("CC-1234", True),
    ("cc-004120", False), ("CC004120", False), ("004120", False),
])
def test_cost_center_format(cat, sample, should_match):
    pattern = re.compile(cat["value_formats"]["cost_center"])
    assert bool(pattern.match(sample)) is should_match
