#!/usr/bin/env python3
"""Validate config/tag_catalog.yaml against structural and governance rules.

Run in CI as the first gate: a taxonomy change that breaches a platform limit,
loses its justification, or creates an unenforceable rule never reaches a
Snowflake account.

Exit code 0 = clean, 1 = errors found. Warnings never fail the build.
"""
from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict

import catalog as C

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def check_structure(cat: dict) -> None:
    for key in ("metadata", "deployment", "object_types", "platform_limits", "tags"):
        if key not in cat:
            err(f"catalog is missing required top-level key '{key}'")


def check_tags(cat: dict) -> None:
    limits = cat["platform_limits"]
    valid_objects = set(cat["object_types"]["all"])
    valid_platforms = {p["id"] for p in cat.get("platforms", [])}
    seen: Counter[str] = Counter()

    for tag in cat["tags"]:
        name = tag.get("name", "<unnamed>")
        seen[name] += 1

        if not C.TAG_NAME_RE.match(name):
            err(f"{name}: tag key must be lowercase snake_case, 2-64 chars. "
                f"AWS tag keys are case-sensitive, so the canonical form has to "
                f"be exact; Snowflake folds it to upper case on its own.")
        if not tag.get("level"):
            err(f"{name}: 'level' is mandatory - every tag states which level of "
                f"the allocation hierarchy it expresses")
        for plat in tag.get("platforms") or []:
            if plat not in valid_platforms:
                err(f"{name}: unknown platform '{plat}'")
        if not tag.get("platforms"):
            err(f"{name}: 'platforms' must name at least one platform the tag is "
                f"applied on")
        if len(name) > 64:
            err(f"{name}: tag identifier exceeds 64 characters")
        if tag.get("tier") not in (1, 2, 3):
            err(f"{name}: tier must be 1, 2 or 3 (got {tag.get('tier')!r})")
        if not C.one_line(tag.get("description")):
            err(f"{name}: description is mandatory (becomes the Snowflake COMMENT)")
        if tag.get("status", "ACTIVE") not in C.STATUSES:
            err(f"{name}: status must be one of {sorted(C.STATUSES)}")
        if tag.get("inheritance") not in C.INHERITANCE_MODES:
            err(f"{name}: inheritance must be one of {sorted(C.INHERITANCE_MODES)}")
        if tag.get("override_rule") not in C.OVERRIDE_RULES:
            err(f"{name}: override_rule must be one of {sorted(C.OVERRIDE_RULES)}")
        if not re.match(r"^\d+\.\d+\.\d+$", str(tag.get("version", ""))):
            err(f"{name}: version must be semver (e.g. 1.0.0)")
        if not tag.get("owner_role"):
            err(f"{name}: owner_role is mandatory - every tag needs an accountable owner")

        # --- Anti-proliferation gate ------------------------------------
        # A tag nobody consumes is metadata debt. This is the mechanical
        # expression of the "no orphan tags" principle.
        if not tag.get("drives"):
            err(f"{name}: 'drives' is empty - a tag with no consumer must not exist "
                f"(see docs/09-anti-patterns.md AP-01)")

        # --- Value source ------------------------------------------------
        vs = tag.get("value_source")
        if vs not in C.VALUE_SOURCES:
            err(f"{name}: value_source must be one of {sorted(C.VALUE_SOURCES)}")
        if vs == "controlled_vocabulary":
            av = tag.get("allowed_values") or []
            if not av:
                err(f"{name}: controlled_vocabulary requires allowed_values")
            # YAML 1.1 coerces bare YES/NO/ON/OFF/TRUE to booleans, which would
            # emit ALLOWED_VALUES 'True' into the DDL. Force explicit quoting.
            for v in av:
                if not isinstance(v, str):
                    err(f"{name}: allowed value {v!r} is a {type(v).__name__}, not a "
                        f"string - quote it in YAML (YES/NO/ON/OFF are booleans in "
                        f"YAML 1.1)")
            if len(av) > limits["max_allowed_values_per_tag"]:
                err(f"{name}: {len(av)} allowed values exceeds Snowflake limit "
                    f"{limits['max_allowed_values_per_tag']}")
            for v in av:
                if len(str(v)) > limits["max_tag_value_length"]:
                    err(f"{name}: allowed value '{v}' exceeds "
                        f"{limits['max_tag_value_length']} characters")
            if len(set(av)) != len(av):
                err(f"{name}: allowed_values contains duplicates")
        else:
            if tag.get("allowed_values"):
                err(f"{name}: allowed_values is only valid for controlled_vocabulary "
                    f"(Snowflake would reject values outside the list)")
        if vs == "reference_data" and not tag.get("reference_table"):
            err(f"{name}: reference_data requires a reference_table")

        # --- Ordinals / override semantics -------------------------------
        ordinals = tag.get("ordinal_values")
        if tag.get("override_rule") == "more_restrictive_only" and not ordinals:
            err(f"{name}: override_rule=more_restrictive_only requires ordinal_values "
                f"so 'most restrictive' is computable")
        if ordinals:
            if vs != "controlled_vocabulary":
                err(f"{name}: ordinal_values requires a controlled vocabulary")
            elif set(ordinals) != set(tag.get("allowed_values") or []):
                err(f"{name}: ordinal_values must be a permutation of allowed_values")

        # --- Assignment surface ------------------------------------------
        applies = tag.get("applies_to") or []
        if not applies:
            err(f"{name}: applies_to must not be empty")
        for ot in applies:
            if ot not in valid_objects:
                err(f"{name}: applies_to references unknown object type '{ot}'")
        if len(set(applies)) != len(applies):
            err(f"{name}: applies_to contains duplicates")

        for ot, level in (tag.get("requirement") or {}).items():
            if ot not in valid_objects:
                err(f"{name}: requirement references unknown object type '{ot}'")
            if level not in C.REQUIREMENT_LEVELS:
                err(f"{name}: requirement[{ot}]='{level}' is not a valid level")
            if level != "NOT_APPLICABLE" and ot not in applies:
                err(f"{name}: requirement[{ot}]='{level}' but '{ot}' is not in applies_to")

        # --- Regex sanity -------------------------------------------------
        pattern = C.resolve_format(cat, tag)
        if pattern:
            try:
                re.compile(pattern)
            except re.error as exc:
                err(f"{name}: value_format is not a valid regex ({exc})")
            if vs == "controlled_vocabulary":
                for v in tag.get("allowed_values") or []:
                    if not re.match(pattern, str(v)):
                        err(f"{name}: allowed value '{v}' fails its own value_format")

        if tag.get("deprecates") and tag["deprecates"] not in {t["name"] for t in cat["tags"]}:
            warn(f"{name}: deprecates '{tag['deprecates']}' which is absent from the catalog")

    for dupe, n in seen.items():
        if n > 1:
            err(f"{dupe}: defined {n} times - tag names must be unique")

    # A tag key that folds to the same Snowflake identifier as another is two
    # keys on AWS and one in Snowflake, which silently merges two allocation
    # buckets on one platform and not the other.
    folded: dict[str, list[str]] = {}
    for tag in cat["tags"]:
        folded.setdefault(C.snowflake_name(tag), []).append(tag["name"])
    for sf_name, originals in folded.items():
        if len(originals) > 1:
            err(f"{', '.join(originals)} all fold to the Snowflake identifier "
                f"{sf_name}. They are distinct keys on AWS and one key in "
                f"Snowflake.")

    # Per-platform key-length ceilings.
    plat_limits = {p["id"]: p for p in cat.get("platforms", [])}
    for tag in cat["tags"]:
        for plat in tag.get("platforms") or []:
            cap = plat_limits.get(plat, {}).get("max_key_length")
            if cap and len(tag["name"]) > cap:
                err(f"{tag['name']}: key exceeds the {plat} limit of {cap} chars")


def check_object_budget(cat: dict) -> None:
    """No object type may be pushed past the framework's direct-set budget."""
    limits = cat["platform_limits"]
    budget = limits["max_tags_directly_set_per_object_target"]
    hard = limits["max_tags_per_object"]

    per_object: dict[str, list[str]] = defaultdict(list)
    for ot in cat["object_types"]["all"]:
        for tag in C.tags(cat):
            if C.requirement(tag, ot) == "MANDATORY":
                per_object[ot].append(tag["name"])

    for ot, names in sorted(per_object.items()):
        if len(names) > hard:
            err(f"{ot}: {len(names)} mandatory tags exceeds the Snowflake hard limit "
                f"of {hard} tags per object")
        elif len(names) > budget:
            err(f"{ot}: {len(names)} mandatory tags exceeds the framework budget of "
                f"{budget} (raise the budget deliberately or demote a tag): "
                f"{', '.join(sorted(names))}")


def check_conditional_rules(cat: dict) -> None:
    by_name = C.tag_by_name(cat)
    valid_objects = set(cat["object_types"]["all"])
    seen_ids: set[str] = set()

    for rule in cat.get("conditional_rules", []):
        rid = rule.get("id", "<no id>")
        if rid in seen_ids:
            err(f"conditional rule id '{rid}' is duplicated")
        seen_ids.add(rid)
        if not rule.get("description"):
            err(f"{rid}: conditional rule needs a description")
        if rule.get("severity") not in {"LOW", "MEDIUM", "HIGH", "CRITICAL"}:
            err(f"{rid}: severity must be LOW/MEDIUM/HIGH/CRITICAL")

        for ot in rule.get("object_types", []):
            if ot not in valid_objects:
                err(f"{rid}: unknown object type '{ot}'")

        for tag_name, values in (rule.get("when") or {}).items():
            tag = by_name.get(tag_name)
            if not tag:
                err(f"{rid}: predicate references unknown tag '{tag_name}'")
                continue
            allowed = tag.get("allowed_values")
            if allowed:
                for v in values:
                    if not isinstance(v, str):
                        err(f"{rid}: predicate value {v!r} must be a quoted string")
                    elif v not in allowed:
                        err(f"{rid}: predicate value '{v}' is not an allowed value of "
                            f"{tag_name}")

        for tag_name in rule.get("then_mandatory", []):
            tag = by_name.get(tag_name)
            if not tag:
                err(f"{rid}: then_mandatory references unknown tag '{tag_name}'")
                continue
            for ot in rule.get("object_types", []):
                if C.requirement(tag, ot) == "NOT_APPLICABLE":
                    err(f"{rid}: makes {tag_name} mandatory on {ot}, but the tag does "
                        f"not apply to {ot} - the rule is unenforceable")


def check_contradiction_rules(cat: dict) -> None:
    """A contradiction rule that cannot fire is worse than none: it reports a
    control as covered when nothing is checking it."""
    by_name = C.tag_by_name(cat)
    seen_ids: set[str] = set()

    for rule in cat.get("contradiction_rules", []):
        rid = rule.get("id", "<no id>")
        if rid in seen_ids:
            err(f"contradiction rule id '{rid}' is duplicated")
        seen_ids.add(rid)
        if rule.get("severity") not in {"LOW", "MEDIUM", "HIGH", "CRITICAL"}:
            err(f"{rid}: severity must be LOW/MEDIUM/HIGH/CRITICAL")

        for field, values_field in (("if_tag", "if_values"),
                                    ("then_tag", "forbidden_values")):
            tag_name = rule.get(field)
            tag = by_name.get(tag_name)
            if not tag:
                err(f"{rid}: {field} references unknown tag '{tag_name}'")
                continue
            allowed = tag.get("allowed_values")
            if not allowed:
                err(f"{rid}: {field} '{tag_name}' has no controlled vocabulary, so "
                    f"a forbidden-value rule over it cannot be evaluated")
                continue
            for v in rule.get(values_field, []):
                if v not in allowed:
                    err(f"{rid}: '{v}' is not an allowed value of {tag_name}")

        if rule.get("if_tag") == rule.get("then_tag"):
            err(f"{rid}: if_tag and then_tag are the same tag")


def check_bindings(cat: dict) -> None:
    by_name = C.tag_by_name(cat)

    for b in cat.get("masking_bindings", []):
        tag = by_name.get(b["tag"])
        if not tag:
            err(f"masking_bindings: unknown tag '{b['tag']}'")
            continue
        if "COLUMN" not in tag.get("applies_to", []):
            err(f"masking_bindings: {b['tag']} is bound to a masking policy but is not "
                f"applicable to COLUMN - tag-based masking would never fire")
        if len(b.get("data_types", [])) != len(set(b.get("data_types", []))):
            err(f"masking_bindings: {b['tag']} lists a data type twice - Snowflake "
                f"allows only one masking policy per data type per tag")

        # Tags read inside the policy body must actually reach columns, or the
        # branch never fires and the control degrades silently.
        for read_tag in b.get("policy_reads_tags", []):
            rt = by_name.get(read_tag)
            if not rt:
                err(f"masking_bindings: {b['tag']} policy body reads unknown tag "
                    f"'{read_tag}'")
                continue
            level = C.requirement(rt, "COLUMN")
            if level not in {"MANDATORY", "RECOMMENDED"}:
                err(f"masking_bindings: {b['tag']} policy body reads {read_tag}, but "
                    f"{read_tag} is {level} on COLUMN - the branch would never fire")

    # Exactly one tag may own masking attachments, otherwise two policies can
    # compete for the same column and resolution depends on lineage proximity.
    bound = {b["tag"] for b in cat.get("masking_bindings", [])}
    if len(bound) > 1:
        err(f"masking_bindings: {len(bound)} tags carry masking attachments "
            f"({', '.join(sorted(bound))}). Bind exactly one tag and branch inside "
            f"the policy body - see docs/05-security-compliance-integration.md.")

    for b in cat.get("row_access_bindings", []):
        tag = by_name.get(b["tag"])
        if not tag:
            err(f"row_access_bindings: unknown tag '{b['tag']}'")
            continue
        allowed = tag.get("allowed_values") or []
        if allowed and b.get("value") not in allowed:
            err(f"row_access_bindings: value '{b.get('value')}' is not an allowed value "
                f"of {b['tag']}")


def check_precedence(cat: dict) -> None:
    by_name = C.tag_by_name(cat)

    # Each single-valued tag that can legitimately hold several truths at once
    # needs a total order, or the governing value is undefined and compliance
    # reporting has a silent gap.
    for tag_name, prec_key in (
        ("data_classification_regulatory", "regulatory_category_precedence"),
        ("regulation", "regulation_precedence"),
    ):
        tag = by_name.get(tag_name)
        if not tag:
            err(f"{prec_key} refers to missing tag {tag_name}")
            continue
        declared = set(tag.get("allowed_values", [])) - {"MULTI"}
        order = cat.get(prec_key, [])
        prec = set(order)
        missing = declared - prec
        extra = prec - declared
        if missing:
            err(f"{prec_key} is missing {sorted(missing)} - the governing value "
                f"would be unresolvable for those")
        if extra:
            err(f"{prec_key} contains values {tag_name} does not allow: "
                f"{sorted(extra)}")
        if len(order) != len(prec):
            err(f"{prec_key} contains duplicates")

    order = cat.get("inheritance_precedence", [])
    valid_objects = set(cat["object_types"]["all"])
    for ot in order:
        if ot not in valid_objects:
            err(f"inheritance_precedence references unknown object type '{ot}'")


def check_tier_sizes(cat: dict) -> None:
    """Tier 1 IS the published allocation hierarchy - no more, no less.

    Tier 1 is not a place to park a tag someone would like to be important. It
    is exactly the set named in the enterprise FinOps Tagging Strategy, so that
    "mandatory" means the same thing in this repository as it does on the slide
    every team has been shown.
    """
    t1 = len(C.tags(cat, 1))
    t2 = len(C.tags(cat, 2))
    if not 8 <= t1 <= 12:
        err(f"Tier 1 has {t1} tags; it must remain the published allocation "
            f"hierarchy (8-12). Promoting a tag into Tier 1 is a Data Governance "
            f"Council decision that also updates the published standard.")
    if not 10 <= t2 <= 18:
        err(f"Tier 2 has {t2} tags; the framework commits to 10-18 governance tags")
    total_keys = len(cat["tags"])
    if total_keys > cat["platform_limits"]["max_unique_tag_keys_per_account"]:
        err("catalog exceeds the Snowflake per-account unique tag key limit")


def check_coverage(cat: dict) -> None:
    """Warn on taxonomy gaps that are legal but usually a mistake."""
    object_types = cat["object_types"]["all"]

    for tag in C.tags(cat):
        if tag["tier"] == 1:
            # Tier 1 mirrors the published standard's "Mandatory" column, so the
            # slide and the catalog cannot say different things about a tag.
            hier = tag.get("hierarchy_requirement")
            if hier not in {"MANDATORY", "RECOMMENDED"}:
                err(f"{tag['name']}: Tier 1 tags must declare hierarchy_requirement "
                    f"as MANDATORY or RECOMMENDED, matching the published standard")
                continue

            levels = {C.requirement(tag, ot) for ot in object_types}
            if hier == "MANDATORY" and "MANDATORY" not in levels:
                err(f"{tag['name']}: declared MANDATORY in the allocation hierarchy "
                    f"but not MANDATORY on any object type")
            if hier == "RECOMMENDED":
                if "MANDATORY" in levels:
                    err(f"{tag['name']}: declared RECOMMENDED in the allocation "
                        f"hierarchy but MANDATORY on an object type - the "
                        f"repository would be stricter than the published standard")
                if "RECOMMENDED" not in levels:
                    err(f"{tag['name']}: declared RECOMMENDED but not RECOMMENDED "
                        f"on any object type")
        elif tag.get("hierarchy_requirement"):
            err(f"{tag['name']}: hierarchy_requirement applies to Tier 1 only")
        if tag["tier"] == 3 and any(
            C.requirement(tag, ot) == "MANDATORY" for ot in cat["object_types"]["all"]
        ):
            warn(f"{tag['name']}: Tier 3 tag is MANDATORY somewhere - consider promoting "
                 f"it to Tier 2")


def main() -> int:
    cat = C.load()
    check_structure(cat)
    if errors:
        report()
        return 1
    check_tags(cat)
    check_object_budget(cat)
    check_conditional_rules(cat)
    check_contradiction_rules(cat)
    check_bindings(cat)
    check_precedence(cat)
    check_tier_sizes(cat)
    check_coverage(cat)
    return report()


def report() -> int:
    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")
    if errors:
        print(f"\nFAILED: {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1
    print(f"OK: catalog valid ({len(warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
