#!/usr/bin/env python3
"""Generate Terraform variables from the tag catalog.

Terraform owns *what exists* (tag objects, allowed values, roles, grants); SQL
owns *what it does* (policy bodies, procedures, tasks). Feeding Terraform from
the same catalog keeps a new tag a one-file change rather than an HCL edit.
"""
from __future__ import annotations

import json
import os
import sys

import catalog as C

OUT_PATH = os.path.join(C.REPO_ROOT, "terraform", "envs", "prod",
                        "tags.auto.tfvars.json")


def build(cat: dict) -> str:
    d = cat["deployment"]
    tags = {}
    for t in C.tags(cat):
        if t.get("status") == "RETIRED":
            continue
        tags[t["name"]] = {
            "comment": C.one_line(t["description"]),
            "allowed_values": t.get("allowed_values") or [],
            "tier": t["tier"],
            "category": t["category"],
            "owner_role": t["owner_role"],
        }

    payload = {
        "governance_database": d["governance_database"],
        "tag_schema": d["tag_schema"],
        "policy_schema": d["policy_schema"],
        "warehouse": d["warehouse"],
        "catalog_version": cat["metadata"]["catalog_version"],
        "tags": tags,
    }
    # Declared as a real variable in variables.tf: Terraform warns about any
    # key in an .auto.tfvars file that the root module does not declare, and a
    # build that emits warnings trains people to ignore warnings.
    header = {
        "generator_note": (
            "GENERATED FILE - DO NOT EDIT. Source: config/tag_catalog.yaml. "
            "Rebuild with `make build`."
        )
    }
    return json.dumps({**header, **payload}, indent=2, sort_keys=False) + "\n"


def main() -> int:
    cat = C.load()
    content = build(cat)
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    if "--check" in sys.argv:
        existing = open(OUT_PATH).read() if os.path.exists(OUT_PATH) else None
        if existing != content:
            print("STALE terraform tfvars (run `make build` and commit)")
            return 1
        print("OK: terraform tfvars up to date")
        return 0
    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        fh.write(content)
    print(f"wrote {os.path.relpath(OUT_PATH, C.REPO_ROOT)} "
          f"({len(cat['tags'])} tags)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
