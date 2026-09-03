"""Shared loader + helpers for the enterprise tag catalog.

Every generator and validator imports from here so that the interpretation of
config/tag_catalog.yaml is defined in exactly one place.
"""
from __future__ import annotations

import os
import re
from typing import Any

import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(REPO_ROOT, "config", "tag_catalog.yaml")

REQUIREMENT_LEVELS = {
    "MANDATORY",
    "RECOMMENDED",
    "OPTIONAL",
    "INHERITED",
    "NOT_APPLICABLE",
}
VALUE_SOURCES = {"controlled_vocabulary", "reference_data", "free_text"}
OVERRIDE_RULES = {"none", "more_restrictive_only", "any"}
INHERITANCE_MODES = {"inherit", "explicit_only"}
STATUSES = {"ACTIVE", "DEPRECATED", "RETIRED"}

TAG_NAME_RE = re.compile(r"^[A-Z][A-Z0-9_]{1,63}$")

# Object types that can never carry a tag whose value is a lineage-inherited
# fact rather than an intrinsic one. Used by the matrix generator only.
GENERATED_HEADER = (
    "-- =========================================================================\n"
    "-- GENERATED FILE - DO NOT EDIT.\n"
    "-- Source : config/tag_catalog.yaml\n"
    "-- Rebuild: make build   (scripts/generate_sql.py)\n"
    "-- CI fails if this file differs from a fresh generation.\n"
    "-- =========================================================================\n"
)


def load(path: str = CATALOG_PATH) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def tags(cat: dict[str, Any], tier: int | None = None) -> list[dict[str, Any]]:
    out = [t for t in cat["tags"] if t.get("status", "ACTIVE") != "RETIRED"]
    if tier is not None:
        out = [t for t in out if t["tier"] == tier]
    return out


def tag_by_name(cat: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {t["name"]: t for t in cat["tags"]}


def requirement(tag: dict[str, Any], object_type: str) -> str:
    """Effective requirement level of `tag` on `object_type`."""
    explicit = (tag.get("requirement") or {}).get(object_type)
    if explicit:
        return explicit
    if object_type not in tag.get("applies_to", []):
        return "NOT_APPLICABLE"
    return tag.get("default_requirement", "OPTIONAL")


def resolve_format(cat: dict[str, Any], tag: dict[str, Any]) -> str | None:
    """Return the concrete regex for a tag, resolving named format references."""
    fmt = tag.get("value_format")
    if not fmt:
        return None
    return cat.get("value_formats", {}).get(fmt, fmt)


def fqn(cat: dict[str, Any], schema_key: str, obj: str) -> str:
    d = cat["deployment"]
    return f"{d['governance_database']}.{d[schema_key]}.{obj}"


def sql_str(value: Any) -> str:
    """Render a Python value as a single-quoted Snowflake SQL literal.

    Snowflake interprets backslash escape sequences inside single-quoted string
    literals, so a regex such as ``\\.`` would arrive at the server as a bare
    ``.`` and silently match any character. Backslashes are therefore doubled as
    well as quotes.
    """
    if value is None:
        return "NULL"
    escaped = str(value).replace("\\", "\\\\").replace("'", "''")
    return "'" + escaped + "'"


def one_line(text: str | None) -> str:
    return " ".join((text or "").split())
