#!/usr/bin/env python3
"""Print (or execute) the deployment order for the framework.

Ordering is not cosmetic. Policies must exist before they are attached to tags;
tags must exist before the registry references them; the registry must be loaded
before any procedure reads it. Getting the order wrong produces partial
deployments that are awkward to unwind on a live account.

`--plan` prints the order. `--execute` requires the Snowflake CLI (`snow`) and a
configured connection; it is deliberately not the default.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

import catalog as C

# (path, description, run-as role)
ORDER = [
    ("sql/00_bootstrap/00_governance_foundation.sql",
     "Database, schemas, roles, warehouse, privileges", "ACCOUNTADMIN"),
    ("sql/30_control_plane/00_registry_tables.sql",
     "Tag registry tables", "TAG_ADMIN"),
    ("sql/30_control_plane/01_reference_data.sql",
     "Reference data model and REF_* views", "TAG_ADMIN"),
    ("sql/30_control_plane/02_operational_tables.sql",
     "Exceptions, findings, audit trail, entitlements", "TAG_ADMIN"),
    ("sql/_generated/10_tag_ddl.sql",
     "Enterprise tag objects (generated)", "TAG_ADMIN"),
    ("sql/_generated/11_catalog_seed.sql",
     "Registry load from the catalog (generated)", "TAG_ADMIN"),
    ("sql/20_policies/00_entitlement_roles.sql",
     "Unmasking entitlement roles", "ACCOUNTADMIN"),
    ("sql/20_policies/10_masking_policies.sql",
     "Masking policies (must exist before attachment)", "TAG_ADMIN"),
    ("sql/20_policies/20_row_access_policies.sql",
     "Row access, aggregation and projection policies", "TAG_ADMIN"),
    ("sql/50_views/00_inventory_and_effective_tags.sql",
     "Inventory and effective-tag resolution", "TAG_ADMIN"),
    ("sql/40_procedures/00_apply_tag.sql",
     "SP_APPLY_TAG", "TAG_ADMIN"),
    ("sql/40_procedures/10_validate_compliance.sql",
     "SP_VALIDATE_COMPLIANCE and column scoping view", "TAG_ADMIN"),
    ("sql/40_procedures/20_reconciliation.sql",
     "Row access, classification and drift reconciliation", "TAG_ADMIN"),
    ("sql/40_procedures/30_lifecycle_and_scoring.sql",
     "Clone remediation, scorecard, tag retirement", "TAG_ADMIN"),
    ("sql/50_views/10_governance_reporting.sql",
     "Governance, catalogue and evidence views", "TAG_ADMIN"),
    ("sql/70_finops/00_cost_allocation.sql",
     "Rate card and FinOps allocation views", "TAG_ADMIN"),
    ("sql/_generated/12_masking_tag_bindings.sql",
     "Attach masking policies to the tag (generated)", "TAG_ADMIN"),
    ("sql/60_automation/00_tasks_and_alerts.sql",
     "Tasks and alerts - enable last, once everything else is verified",
     "TAG_ADMIN"),
]


def plan() -> int:
    print("Deployment order\n" + "=" * 78)
    missing = []
    for i, (path, desc, role) in enumerate(ORDER, 1):
        full = os.path.join(C.REPO_ROOT, path)
        ok = os.path.exists(full)
        if not ok:
            missing.append(path)
        mark = " " if ok else "!"
        print(f"{mark}{i:>3}. [{role:<13}] {path}")
        print(f"      {desc}")
    print("=" * 78)
    if missing:
        print(f"MISSING {len(missing)} file(s): " + ", ".join(missing))
        return 1
    print(f"{len(ORDER)} scripts, all present.")
    print("\nSeed CONTROL.REFERENCE_VALUE and CONTROL.RATE_CARD before enabling "
          "tasks:\n  reference data validation and cost reporting both depend "
          "on them.")
    return 0


def execute(connection: str) -> int:
    for i, (path, desc, role) in enumerate(ORDER, 1):
        full = os.path.join(C.REPO_ROOT, path)
        print(f"[{i}/{len(ORDER)}] {path} ({desc})")
        result = subprocess.run(
            ["snow", "sql", "-c", connection, "-f", full],
            capture_output=True, text=True)
        if result.returncode != 0:
            print(f"FAILED at {path}:\n{result.stderr}")
            print("The account is now partially deployed. Fix the error and "
                  "re-run from this script onward - every script is idempotent.")
            return 1
    print("Deployment complete.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--plan", action="store_true", help="print the order (default)")
    ap.add_argument("--execute", metavar="CONNECTION",
                    help="run via the Snowflake CLI using this connection name")
    args = ap.parse_args()
    if args.execute:
        return execute(args.execute)
    return plan()


if __name__ == "__main__":
    sys.exit(main())
