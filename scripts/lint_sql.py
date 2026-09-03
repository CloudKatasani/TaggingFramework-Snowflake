#!/usr/bin/env python3
"""Lint the SQL in this repository for destructive and unsafe patterns.

These are not style rules. Each one below has, in some Snowflake estate,
silently removed a control from production.
"""
from __future__ import annotations

import os
import re
import sys

import catalog as C

SQL_ROOT = os.path.join(C.REPO_ROOT, "sql")

# (id, compiled pattern, severity, explanation)
RULES = [
    (
        "SQL001",
        re.compile(r"\bCREATE\s+OR\s+REPLACE\s+TAG\b", re.I),
        "ERROR",
        "CREATE OR REPLACE TAG drops every assignment of the tag across the "
        "account and detaches any masking policy bound to it. Both succeed "
        "silently. Use CREATE TAG IF NOT EXISTS + ALTER TAG.",
    ),
    (
        "SQL002",
        re.compile(r"\bDROP\s+TAG\b", re.I),
        "ERROR",
        "DROP TAG removes every assignment with no warning. Use "
        "AUTOMATION.SP_RETIRE_TAG, which sweeps assignments in a logged, "
        "reversible way and refuses while a policy binding is active.",
    ),
    (
        "SQL003",
        re.compile(r"\bDROP\s+(MASKING|ROW\s+ACCESS)\s+POLICY\b", re.I),
        "ERROR",
        "Dropping a policy unprotects every object referencing it. Detach it "
        "from the tag first, verify zero references, then drop in a separate "
        "change.",
    ),
    (
        "SQL004",
        re.compile(r"\bCREATE\s+OR\s+REPLACE\s+(MASKING|ROW\s+ACCESS)\s+POLICY\b", re.I),
        "WARN",
        "CREATE OR REPLACE on a policy is permitted by Snowflake only when the "
        "signature is unchanged; a signature change fails mid-deployment and "
        "leaves the estate half-migrated. Prefer IF NOT EXISTS + ALTER.",
    ),
    (
        "SQL005",
        re.compile(r"(PASSWORD|PRIVATE_KEY|SECRET|TOKEN)\s*=\s*'[^']{4,}'", re.I),
        "ERROR",
        "Hard-coded credential. Use a Snowflake SECRET object or the CI secret "
        "store.",
    ),
    (
        "SQL006",
        re.compile(r"\bGRANT\s+APPLY\s+TAG\s+ON\s+ACCOUNT\s+TO\s+ROLE\s+(?!TAG_ADMIN\b)",
                   re.I),
        "ERROR",
        "APPLY TAG is account-scoped and must be held by TAG_ADMIN only. "
        "Stewards tag through SP_APPLY_TAG, which enforces domain ownership.",
    ),
    (
        "SQL007",
        re.compile(r"CURRENT_ROLE\(\)\s*(=|IN)\s*", re.I),
        "WARN",
        "CURRENT_ROLE() ignores the role hierarchy and secondary roles, so a "
        "user holding the entitlement indirectly is wrongly denied. Use "
        "IS_ROLE_IN_SESSION().",
    ),
]

# Files that legitimately contain a pattern (the teardown script must drop
# things; the linter's own docs quote the forbidden syntax).
ALLOWLIST = {
    "sql/90_teardown/00_teardown.sql",
}


def main() -> int:
    errors = warns = 0
    for dirpath, _dirs, files in os.walk(SQL_ROOT):
        for fname in sorted(files):
            if not fname.endswith(".sql"):
                continue
            path = os.path.join(dirpath, fname)
            rel = os.path.relpath(path, C.REPO_ROOT)
            if rel in ALLOWLIST:
                continue
            with open(path, encoding="utf-8") as fh:
                for lineno, line in enumerate(fh, 1):
                    # Skip comment lines: the rules are widely discussed in the
                    # explanatory headers of these files.
                    stripped = line.lstrip()
                    if stripped.startswith("--"):
                        continue
                    for rule_id, pattern, severity, msg in RULES:
                        if pattern.search(line):
                            print(f"{severity} {rule_id} {rel}:{lineno}\n"
                                  f"        {line.strip()[:100]}\n"
                                  f"        {msg}")
                            if severity == "ERROR":
                                errors += 1
                            else:
                                warns += 1
    if errors:
        print(f"\nFAILED: {errors} error(s), {warns} warning(s)")
        return 1
    print(f"OK: SQL lint clean ({warns} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
