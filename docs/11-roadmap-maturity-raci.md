# 11. Roadmap, Maturity Model and RACI

## 11.1 Implementation roadmap

Twelve months, five phases. Each phase ends with something that produces value on
its own — a governance programme whose first deliverable is in month nine does not
reach month nine.

### Phase 0 · Foundation (weeks 1–4)

| | |
|---|---|
| **Deliver** | Governance database, RBAC, warehouse; catalog v1.0 approved by council; CI pipeline; Tier 1 tags deployed to non-production |
| **Team** | 1 governance lead, 1 platform engineer, council time |
| **Exit** | Tier 1 tags exist in non-prod; CI blocks a malformed catalog PR; `SP_APPLY_TAG` rejects an invalid value in a live demo |

The demo matters. Showing the council a rejected bad value converts the framework
from a document into a mechanism in a way no slide does.

### Phase 1 · Pilot (weeks 5–12)

| | |
|---|---|
| **Deliver** | One domain, 3–5 data products, fully tagged; masking on pilot PII columns; first compliance scan; first chargeback report for the pilot cost centre |
| **Team** | + 1 domain steward, 1 data owner |
| **Exit** | Pilot at ≥ 95% Tier 1 coverage; masking demonstrably working; steward reports the workload as sustainable |

Choose a pilot domain with an engaged owner and a real pain point — usually
someone who has recently been asked an access question they could not answer, or
whose cost allocation is visibly wrong. A pilot with a motivated sponsor
establishes the pattern; a pilot chosen for being "simple" establishes nothing.

### Phase 2 · Scale (months 4–7)

| | |
|---|---|
| **Deliver** | Top 20% of databases by consumption tagged at database and schema level; auto-classification across those schemas; masking policies attached in production; full automation running; deployment gate enforced for new objects |
| **Team** | + stewards per domain (0.2 FTE each), 1 platform engineer |
| **Exit** | ≥ 80% of consumption under Tier 1 coverage; unallocated spend below 20%; gate blocking untagged production deployments |

Enable the deployment gate at the *start* of this phase, not the end. Otherwise
the backlog grows faster than it is cleared.

### Phase 3 · Enforce (months 8–10)

| | |
|---|---|
| **Deliver** | Row access policies live; exception register operating; chargeback moved from showback to journalled; column-level tagging complete for regulated tables; first audit evidence pack produced from `VW_COMPLIANCE_EVIDENCE` |
| **Team** | Steady state + compliance/audit engagement |
| **Exit** | ≥ 95% Tier 1 coverage; zero critical findings older than 30 days; unallocated spend < 5%; an assessor accepts the evidence pack |

### Phase 4 · Optimise (months 11–12+)

| | |
|---|---|
| **Deliver** | First quarterly taxonomy review with retirements; Tier 3 domain tags federated to domains; tag-driven cost optimisation campaigns; catalog integration (Horizon / external catalogue) |
| **Exit** | Taxonomy shrinks or holds steady rather than growing; measurable cost recovery attributable to lifecycle and retention tags |

**The exit criterion for Phase 4 is a taxonomy that stops growing.** That is the
signal that the framework has become a managed product rather than an
accumulating pile of well-intentioned metadata.

## 11.2 Maturity model

Computed, not asserted — `VW_COMPLIANCE_DASHBOARD.MATURITY_LEVEL` derives the band
from live coverage and findings.

| Level | Tier 1 coverage | Critical findings | Characteristics |
|---|---|---|---|
| **L1 Initial** | < 50% | any | Ad-hoc tags; no vocabulary; no automation; nobody can list who owns what |
| **L2 Repeatable** | 50–79% | any | Catalog exists and is approved; tags applied manually on new objects; reporting exists but nobody acts on it |
| **L3 Defined** | 80–94% | any | CI/CD applies tags; masking attached; compliance scan running; findings routed to named stewards |
| **L4 Managed** | ≥ 95% | 0 | Deployment gate enforced; chargeback journalled; exceptions time-boxed and tracked; drift detected within the hour |
| **L5 Optimised** | ≥ 98% | 0 | Quarterly retirements; taxonomy stable or shrinking; tag-driven cost optimisation; governance metadata consumed outside the platform |

Note what separates L3 from L4: not more tags, but **enforcement and a closed
loop**. Most estates plateau at L3 — coverage is good, but nothing prevents
regression and no one is accountable for the gap between declared and enforced.

### KPIs

| KPI | Source | L4 target |
|---|---|---|
| Tier 1 coverage (by domain) | `COMPLIANCE_SCORE_HISTORY` | ≥ 95% |
| Critical findings > 30 days | `COMPLIANCE_FINDING` | 0 |
| Mean time to remediate (HIGH) | `COMPLIANCE_FINDING` | < 10 days |
| Unallocated spend | `VW_UNALLOCATED_SPEND` | < 2% |
| Policy drift incidents | `SP_DETECT_POLICY_DRIFT` | 0 open |
| Open exceptions | `TAG_EXCEPTION` | < 25, none expired |
| Classification review backlog | `CLASSIFICATION_RECONCILIATION` | < 5% `UNREVIEWED` |
| Tags with `UNUSED` verdict | `VW_TAG_ADOPTION` | 0 after review |

Report coverage **by domain and business unit, never as a single account-wide
number** (AP-14). One aggregate percentage hides the stalled domain that is the
actual risk.

## 11.3 RACI

**R** responsible · **A** accountable · **C** consulted · **I** informed

| Activity | Council | EDGO | Domain owner | Steward | Data owner | Platform | CISO | Privacy | Finance | Legal |
|---|---|---|---|---|---|---|---|---|---|---|
| Approve taxonomy (Tier 1/2) | **A** | R | C | I | I | C | C | C | C | C |
| Maintain the catalog | I | **A/R** | C | I | I | C | C | C | C | I |
| Add Tier 3 domain tag | I | C | **A/R** | R | I | I | I | I | I | I |
| Add a controlled value | I | **A/R** | C | I | I | I | C | C | C | I |
| Deploy tags and policies | I | C | I | I | I | **A/R** | C | I | I | I |
| Define classification levels | **A** | R | C | I | C | I | **R** | C | I | C |
| Classify a dataset | I | C | C | R | **A** | I | C | C | I | I |
| Assign tags to objects | I | C | **A** | **R** | C | C | I | I | I | I |
| Own masking policy design | I | C | I | I | I | R | **A** | C | I | I |
| Own row access entitlements | I | C | **A** | R | C | R | C | I | I | I |
| Set retention classes | I | C | C | R | **A** | I | I | C | I | **C** |
| Issue a legal hold | I | I | I | R | C | I | I | C | I | **A/R** |
| Approve an exception | C | **A/R** | C | I | C | I | C | C | I | I |
| Accept CRITICAL risk | **A** | R | C | I | C | I | **C** | C | I | C |
| Remediate findings | I | C | **A** | **R** | C | C | I | I | I | I |
| Own cost allocation model | I | C | C | I | I | C | I | I | **A/R** | I |
| Validate chargeback figures | I | C | **A** | R | C | C | I | I | **R** | I |
| Quarterly taxonomy review | **A** | R | C | C | I | C | C | C | C | I |
| Approve a tag retirement | **A** | R | C | I | I | C | C | C | C | I |
| Produce audit evidence | I | **A/R** | C | R | C | C | C | C | I | C |
| Run governance automation | I | C | I | I | I | **A/R** | I | I | I | I |

Three deliberate placements:

- **Classifying a specific dataset is the data owner's decision (A), not the
  governance team's.** The centre owns the vocabulary; the business owns the
  facts. A governance team that classifies datasets on the business's behalf owns
  a risk it cannot assess.
- **Masking policy design is accountable to the CISO, not to the platform.** The
  platform builds it; Security owns whether it is sufficient.
- **Accepting CRITICAL risk sits with the council, not with the EDGO.** A
  governance office approving its own exceptions is not a control.

## 11.4 Team model

| Phase | Governance lead | Platform eng. | Stewards | Total FTE |
|---|---|---|---|---|
| 0 Foundation | 1.0 | 1.0 | — | 2.0 |
| 1 Pilot | 1.0 | 0.5 | 0.5 | 2.0 |
| 2 Scale | 1.0 | 1.0 | 0.2 × domains | 2 + 0.2n |
| 3 Enforce | 1.0 | 0.5 | 0.2 × domains | 1.5 + 0.2n |
| 4 Steady state | 0.5 | 0.25 | 0.1 × domains | 0.75 + 0.1n |

Stewardship is **0.1–0.2 FTE per domain, not a full-time role**. If it exceeds
that, the framework is demanding too much manual input and the fix is more
automation (P8), not more headcount. A steady-state figure above 0.3 FTE per
domain is a design defect, and should be treated as one.

## 11.5 Common failure modes for the programme

| Failure | Signal | Response |
|---|---|---|
| Coverage plateaus at ~70% | Remaining objects belong to disengaged domains | Escalate to council with per-domain figures; do not average it away |
| Stewards stop working the list | Findings age past 30 days | Check ranking is by blast radius; check the demand is not AP-03 |
| Taxonomy creeps past 60 tags | Every quarter adds tags, none retired | Enforce P7 at the council; run the adoption review and retire |
| Chargeback disputed | Cost centre owners reject the numbers | Return to showback; fix `VW_UNALLOCATED_SPEND` first |
| Exceptions accumulate | Register grows every quarter | The standard is wrong somewhere — fix the standard, not the register |
| Nobody reads the dashboard | No traffic on the reporting views | The metric is not tied to a decision anyone owns; find the decision or drop the metric |
