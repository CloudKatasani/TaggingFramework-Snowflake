#!/usr/bin/env python3
"""Generate the reference documentation from config/tag_catalog.yaml.

    docs/reference/requirement-matrix.md   the Mandatory/Recommended/Optional matrix
    docs/reference/tag-catalog.md          full per-tag reference

Hand-maintaining these was the original defect this framework is meant to avoid:
a published matrix that disagrees with the deployed tags is worse than no matrix,
because people plan against it.
"""
from __future__ import annotations

import os
import sys

import catalog as C

OUT_DIR = os.path.join(C.REPO_ROOT, "docs", "reference")

BANNER = (
    "<!-- GENERATED FILE - DO NOT EDIT. Source: config/tag_catalog.yaml. "
    "Rebuild with `make build`. -->\n\n"
)

SYMBOL = {
    "MANDATORY": "**M**",
    "RECOMMENDED": "R",
    "OPTIONAL": "O",
    "INHERITED": "_i_",
    "NOT_APPLICABLE": "–",
}

TIER_LABEL = {
    1: "Tier 1 — Core Mandatory",
    2: "Tier 2 — Governance",
    3: "Tier 3 — Optional / Domain",
}


def gen_matrix(cat: dict) -> str:
    cols = cat["object_types"]["matrix_columns"]
    out = [BANNER, "# Tag Requirement Matrix\n"]
    out.append(
        "Requirement level of every enterprise tag against the six object types "
        "that carry the bulk of the estate.\n"
    )
    out.append("| Symbol | Meaning |")
    out.append("|---|---|")
    out.append("| **M** | Mandatory — the object is non-compliant without it. |")
    out.append("| R | Recommended — expected unless there is a reason not to. |")
    out.append("| O | Optional — available, never demanded. |")
    out.append("| _i_ | Inherited — satisfied by an ancestor; setting it directly is an override. |")
    out.append("| – | Not applicable — the tag cannot be set on this object type. |")
    out.append("")
    out.append(
        "> **Read the _i_ column carefully.** Most Tier 1 tags are mandatory on "
        "databases and schemas and merely *inherited* on tables and columns. That "
        "is the whole reason a 17-tag mandatory taxonomy costs a team roughly six "
        "direct assignments per table rather than seventeen.\n"
    )

    for tier in (1, 2, 3):
        tier_tags = C.tags(cat, tier)
        if not tier_tags:
            continue
        out.append(f"\n## {TIER_LABEL[tier]} ({len(tier_tags)} tags)\n")
        out.append("| Tag | " + " | ".join(c.title() for c in cols) + " | Drives |")
        out.append("|---" * (len(cols) + 2) + "|")
        for t in tier_tags:
            cells = [SYMBOL[C.requirement(t, c)] for c in cols]
            drives = ", ".join(t.get("drives", [])[:3])
            if len(t.get("drives", [])) > 3:
                drives += ", …"
            out.append(f"| `{t['name']}` | " + " | ".join(cells) + f" | {drives} |")

    # Direct-set budget per object type: the number that decides whether the
    # framework is workable in practice.
    out.append("\n## Mandatory load per object type\n")
    out.append(
        "The count of tags a team must set *directly* on each object type. The "
        "framework budget is "
        f"{cat['platform_limits']['max_tags_directly_set_per_object_target']}; "
        f"Snowflake's hard ceiling is {cat['platform_limits']['max_tags_per_object']}.\n"
    )
    out.append("| Object type | Mandatory tags | Tags |")
    out.append("|---|---|---|")
    for ot in cat["object_types"]["all"]:
        names = [t["name"] for t in C.tags(cat)
                 if C.requirement(t, ot) == "MANDATORY"]
        if names:
            out.append(f"| `{ot}` | {len(names)} | "
                       + ", ".join(f"`{n}`" for n in sorted(names)) + " |")
    return "\n".join(out) + "\n"


def gen_catalog_doc(cat: dict) -> str:
    out = [BANNER, "# Enterprise Tag Catalog\n"]
    m = cat["metadata"]
    out.append(f"- **Catalog version:** {m['catalog_version']}")
    out.append(f"- **Framework version:** {m['framework_version']}")
    out.append(f"- **Owner:** {m['owner']}")
    out.append(f"- **Review cadence:** {m['review_cadence']}")
    out.append(f"- **Total tags:** {len(cat['tags'])} "
               f"({len(C.tags(cat,1))} Tier 1, {len(C.tags(cat,2))} Tier 2, "
               f"{len(C.tags(cat,3))} Tier 3)\n")

    for tier in (1, 2, 3):
        out.append(f"\n## {TIER_LABEL[tier]}\n")
        for t in C.tags(cat, tier):
            out.append(f"### `{t['name']}`\n")
            out.append(f"{C.one_line(t['description'])}\n")
            out.append("| Property | Value |")
            out.append("|---|---|")
            out.append(f"| Category | {t['category']} |")
            out.append(f"| Value source | `{t['value_source']}` |")
            if t.get("allowed_values"):
                out.append("| Allowed values | "
                           + ", ".join(f"`{v}`" for v in t["allowed_values"]) + " |")
            if t.get("ordinal_values"):
                out.append("| Severity order | "
                           + " ‹ ".join(f"`{v}`" for v in t["ordinal_values"]) + " |")
            if t.get("reference_table"):
                out.append(f"| Reference set | `{t['reference_table']}` |")
            fmt = C.resolve_format(cat, t)
            if fmt:
                out.append(f"| Format | `{fmt}` |")
            out.append(f"| Inheritance | `{t['inheritance']}` |")
            out.append(f"| Override rule | `{t['override_rule']}` |")
            out.append(f"| Owner | {t['owner_role']} |")
            out.append(f"| Version | {t['version']} ({t.get('status','ACTIVE')}) |")
            out.append("| Applies to | "
                       + ", ".join(f"`{o}`" for o in t["applies_to"]) + " |")
            mandatory = [ot for ot in cat["object_types"]["all"]
                         if C.requirement(t, ot) == "MANDATORY"]
            out.append("| Mandatory on | "
                       + (", ".join(f"`{o}`" for o in mandatory) if mandatory
                          else "_nothing — conditional or advisory only_") + " |")
            out.append("| Consumed by | "
                       + ", ".join(f"`{d}`" for d in t["drives"]) + " |")
            out.append("")

    out.append("\n## Conditional mandates\n")
    out.append("Tags that become mandatory only when a predicate over other "
               "*effective* tag values holds.\n")
    out.append("| Rule | Severity | When | Then mandatory | On |")
    out.append("|---|---|---|---|---|")
    for r in cat.get("conditional_rules", []):
        when = (", ".join(f"`{k}` ∈ {v}" for k, v in (r.get("when") or {}).items())
                or "_always_")
        out.append(
            f"| **{r['id']}** | {r['severity']} | {when} | "
            + ", ".join(f"`{t}`" for t in r["then_mandatory"]) + " | "
            + ", ".join(f"`{o}`" for o in r["object_types"]) + " |")
        out.append(f"| | | _{C.one_line(r['description'])}_ | | |")

    out.append("\n## Regulation precedence\n")
    out.append("`REGULATION` holds a single governing regime. Where several "
               "apply, the earliest in this order wins and the tag is set to "
               "`MULTI`, with the full set recorded in "
               "`CONTROL.REGULATORY_SCOPE`.\n")
    out.append(" → ".join(f"`{r}`" for r in cat.get("regulation_precedence", [])))
    return "\n".join(out) + "\n"


def main() -> int:
    cat = C.load()
    os.makedirs(OUT_DIR, exist_ok=True)
    artifacts = {
        "requirement-matrix.md": gen_matrix(cat),
        "tag-catalog.md": gen_catalog_doc(cat),
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
            print("STALE generated docs (run `make build` and commit): "
                  + ", ".join(stale))
            return 1
        print("OK: generated docs are up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
