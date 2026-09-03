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


# The ten tags of the published FinOps Tagging Strategy, and their Mandatory
# column. This is the contract between the slide every team has been shown and
# what this repository actually deploys.
PUBLISHED_HIERARCHY = {
    "operating_company": "MANDATORY",
    "department": "MANDATORY",
    "domain": "MANDATORY",
    "team": "MANDATORY",
    "application": "MANDATORY",
    "workload_type": "MANDATORY",
    "owner_user": "RECOMMENDED",
    "environment": "MANDATORY",
    "data_classification_enterprise": "MANDATORY",
    "data_classification_regulatory": "MANDATORY",
}


def test_tier1_is_exactly_the_published_hierarchy(cat, by_name):
    """Tier 1 is not a place to park a tag someone would like to be important."""
    tier1 = {t["name"] for t in C.tags(cat, 1)}
    assert tier1 == set(PUBLISHED_HIERARCHY), (
        f"Tier 1 has drifted from the published standard. "
        f"Extra: {sorted(tier1 - set(PUBLISHED_HIERARCHY))}; "
        f"missing: {sorted(set(PUBLISHED_HIERARCHY) - tier1)}")


def test_mandatory_column_matches_the_published_standard(by_name):
    """A tag the slide calls Recommended must not be enforced as Mandatory."""
    for name, expected in PUBLISHED_HIERARCHY.items():
        assert by_name[name]["hierarchy_requirement"] == expected


def test_reference_allowed_values_are_reproduced_exactly(by_name):
    """The vocabularies come from the enterprise standard, not from taste."""
    assert by_name["operating_company"]["allowed_values"] == [
        "OPCO_AEP_OHIO", "OPCO_AEP_TEXAS", "OPCO_APPALACHIAN",
        "OPCO_AEP_INDIANA_MICHIGAN", "OPCO_KENTUCKY_POWER",
        "OPCO_PSC_OKLAHOMA", "OPCO_SEPC", "SHARED"]
    assert by_name["environment"]["allowed_values"] == [
        "PRD", "UAT", "TST", "DEV", "TRAINING", "BACKUP"]
    assert by_name["data_classification_enterprise"]["allowed_values"] == [
        "NONE", "PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"]
    assert by_name["data_classification_regulatory"]["allowed_values"] == [
        "NONE", "PII", "SPII", "PHI", "PCI"]
    assert by_name["workload_type"]["allowed_values"] == [
        "INGEST", "TRANSFORM", "ANALYTICS", "ML_TRAIN", "ML_SERVE", "BI",
        "GOVERNANCE", "PLATFORM_OPS"]
    assert set(by_name["department"]["allowed_values"]) == {
        "FINANCE", "HR", "MARKETING", "DISTRIBUTION", "GENERATION", "COMOPS",
        "GIS", "CORPORATE", "CUSTOMER", "SHARED_SERVICES"}
    assert set(by_name["domain"]["allowed_values"]) == {
        "CUSTOMER", "LOCATION", "METER", "FINANCE", "SUPPLY_CHAIN",
        "MARKETING", "RISK", "TELEMETRY"}


def test_tier_sizes(cat):
    assert len(C.tags(cat, 1)) == 10
    assert len(C.tags(cat, 2)) == 15
    assert len(C.tags(cat, 3)) == 15
    assert len(cat["tags"]) == 40


def test_every_tag_has_a_consumer(cat):
    """Principle P1. A tag nothing reads is metadata debt."""
    orphans = [t["name"] for t in cat["tags"] if not t.get("drives")]
    assert orphans == [], f"tags with no consumer: {orphans}"


def test_control_tags_use_most_restrictive_resolution(cat, by_name):
    """AP-09: nearest-wins on a control tag silently unmasks data."""
    controls = ["data_classification_enterprise", "data_classification_regulatory",
                "masking_required", "row_access_required", "encryption_required",
                "legal_hold", "criticality"]
    for name in controls:
        tag = by_name[name]
        assert tag["override_rule"] == "more_restrictive_only", (
            f"{name} is a control tag and must resolve most-restrictive-wins")
        assert tag.get("ordinal_values"), (
            f"{name} needs ordinal_values for 'most restrictive' to be computable")


def test_ordinals_run_least_to_most_restrictive(by_name):
    """VW_EFFECTIVE_TAG ranks by ORDINAL_POSITION descending, so the ordering
    direction is load-bearing, not documentation."""
    assert by_name["data_classification_enterprise"]["ordinal_values"] == [
        "NONE", "PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"]
    # Ordered by how prescriptive the mandated technical control is. A column
    # that is both PII and PCI carries PCI, and PCI handling is a superset.
    assert by_name["data_classification_regulatory"]["ordinal_values"] == [
        "NONE", "PII", "SPII", "PHI", "PCI"]
    assert by_name["criticality"]["ordinal_values"] == [
        "LOW", "MEDIUM", "HIGH", "CRITICAL"]


def test_environment_cannot_be_overridden(by_name):
    """Section 4.6: a schema inside a PRD database must not declare itself DEV."""
    assert by_name["environment"]["override_rule"] == "none"
    assert by_name["data_product"]["override_rule"] == "none"


def test_quality_tier_is_never_inherited(by_name):
    """Certification is measured, not inherited from a neighbour."""
    assert by_name["data_quality_tier"]["inheritance"] == "explicit_only"


def test_exactly_one_tag_carries_masking_attachments(cat):
    """Two attached tags means a column carrying both has two candidate policies
    and resolution depends on lineage proximity rather than on risk."""
    bound = {b["tag"] for b in cat["masking_bindings"]}
    assert bound == {"data_classification_enterprise"}


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
        assert b["tag"] == "row_access_required"
        assert b["value"] == "YES"
        assert isinstance(b["value"], str)


def test_precedence_lists_are_total(by_name, cat):
    """An unresolvable governing value is a silent gap in compliance reporting."""
    for tag_name, key in (("data_classification_regulatory",
                           "regulatory_category_precedence"),
                          ("regulation", "regulation_precedence")):
        declared = set(by_name[tag_name]["allowed_values"]) - {"MULTI"}
        precedence = cat[key]
        assert set(precedence) == declared
        assert len(precedence) == len(set(precedence))
        assert precedence[-1] == "NONE", f"{key} must end at NONE"

    # PCI-DSS dictates specific handling of specific fields; a privacy regime
    # mandates outcomes. The most prescriptive control ranks first.
    assert cat["regulatory_category_precedence"][0] == "PCI"
    assert cat["regulation_precedence"][0] == "HIPAA"


def test_mandatory_load_stays_within_budget(cat):
    """The number that decides whether the framework is adoptable."""
    budget = cat["platform_limits"]["max_tags_directly_set_per_object_target"]
    for ot in cat["object_types"]["all"]:
        n = sum(1 for t in C.tags(cat) if C.requirement(t, ot) == "MANDATORY")
        assert n <= budget, f"{ot} requires {n} directly-set tags (budget {budget})"


def test_expected_mandatory_counts(cat):
    """Pinned because docs/02 publishes these figures as the adoption argument."""
    expected = {"DATABASE": 6, "SCHEMA": 5, "WAREHOUSE": 6, "TABLE": 2,
                "VIEW": 2, "COLUMN": 1, "TASK": 3, "PIPE": 3, "SHARE": 5}
    for ot, n in expected.items():
        actual = sum(1 for t in C.tags(cat) if C.requirement(t, ot) == "MANDATORY")
        assert actual == n, f"{ot}: expected {n} mandatory tags, found {actual}"


def test_tier1_tags_are_enforced_at_their_declared_level(cat, by_name):
    for t in C.tags(cat, 1):
        levels = {C.requirement(t, ot) for ot in cat["object_types"]["all"]}
        if t["hierarchy_requirement"] == "MANDATORY":
            assert "MANDATORY" in levels, f"{t['name']} is mandatory nowhere"
        else:
            assert "MANDATORY" not in levels, (
                f"{t['name']} is Recommended in the standard but enforced as "
                f"mandatory here")


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
    """Lowercase snake_case: AWS tag keys are case-sensitive, so the canonical
    form has to be exact."""
    for t in cat["tags"]:
        assert C.TAG_NAME_RE.match(t["name"]), t["name"]
        assert t["name"] == t["name"].lower()
        assert not re.match(r"^(tag|ent|corp)_", t["name"]), \
            f"{t['name']}: prefixes add length and distinguish nothing"
        assert not re.match(r"^(is|has)_", t["name"]), \
            f"{t['name']}: boolean tags are named for the positive assertion"


def test_snowflake_identifiers_do_not_collide(cat):
    """Two keys that fold to one Snowflake identifier are two allocation buckets
    on AWS and one in Snowflake."""
    folded = [C.snowflake_name(t) for t in cat["tags"]]
    assert len(folded) == len(set(folded))


def test_every_tag_declares_its_platforms(cat):
    valid = {p["id"] for p in cat["platforms"]}
    for t in cat["tags"]:
        assert t.get("platforms"), f"{t['name']} names no platform"
        assert set(t["platforms"]) <= valid, t["name"]


def test_every_tag_declares_a_hierarchy_level(cat):
    for t in cat["tags"]:
        assert t.get("level"), f"{t['name']} has no hierarchy level"


def test_contradiction_rules_are_evaluable(cat, by_name):
    """A contradiction rule over a free-text tag cannot fire, which would report
    a control as covered while nothing checks it."""
    assert cat["contradiction_rules"], "the contradiction rule set must not be empty"
    for rule in cat["contradiction_rules"]:
        for field, values in (("if_tag", "if_values"),
                              ("then_tag", "forbidden_values")):
            tag = by_name[rule[field]]
            assert tag.get("allowed_values"), f"{rule['id']}: {field} has no vocabulary"
            for v in rule[values]:
                assert v in tag["allowed_values"], f"{rule['id']}: bad value {v}"
        assert rule["if_tag"] != rule["then_tag"]


def test_regulated_data_cannot_be_public(cat):
    """XR-001 is the rule that catches the one state scoring 100% on coverage
    while leaving data in clear. It must exist."""
    rule = next(r for r in cat["contradiction_rules"] if r["id"] == "XR-001")
    assert rule["if_tag"] == "data_classification_regulatory"
    assert set(rule["if_values"]) == {"PII", "SPII", "PHI", "PCI"}
    assert rule["then_tag"] == "data_classification_enterprise"
    assert set(rule["forbidden_values"]) == {"NONE", "PUBLIC"}
    assert rule["severity"] == "CRITICAL"


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
        "sharing_scope", "data_classification_enterprise", "data_owner",
        "data_product"}
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
    ("abc.xyz@aep.com", True),
    ("service-account-ingest", True),
    ("the platform team", False),
    ("", False),
])
def test_owner_principal_format(cat, sample, should_match):
    pattern = re.compile(cat["value_formats"]["owner_principal"])
    assert bool(pattern.match(sample)) is should_match


@pytest.mark.parametrize("sample,should_match", [
    ("team-customer-360", True), ("team-revenue-platform", True),
    ("team-mlops-core", True),
    ("Team-Customer", False), ("customer-360", False), ("team-", False),
])
def test_team_slug_format(cat, sample, should_match):
    pattern = re.compile(cat["value_formats"]["team_slug"])
    assert bool(pattern.match(sample)) is should_match


@pytest.mark.parametrize("sample,should_match", [
    ("app-cust360-api", True), ("app-finmart-dbt", True),
    ("app-pricing-ml", True), ("app-collibra-conn", True),
    ("APP-10457", False), ("cust360-api", False),
])
def test_application_slug_format(cat, sample, should_match):
    pattern = re.compile(cat["value_formats"]["application_slug"])
    assert bool(pattern.match(sample)) is should_match


@pytest.mark.parametrize("sample,should_match", [
    ("CC-004120", True), ("CC-1234", True),
    ("cc-004120", False), ("CC004120", False), ("004120", False),
])
def test_cost_center_format(cat, sample, should_match):
    pattern = re.compile(cat["value_formats"]["cost_center"])
    assert bool(pattern.match(sample)) is should_match
