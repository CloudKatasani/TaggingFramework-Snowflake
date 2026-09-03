# 7. FinOps Framework

## 7.1 The problem tags solve

Snowflake bills the account. Finance needs the bill by business unit, cost centre,
domain, project and environment. Nothing in the platform knows those concepts —
tags are the only bridge.

The hard part is not producing a number. It is producing a number that survives
contact with a cost-centre owner who disputes it. That requires the allocation to
be **explainable, reconcilable to the invoice, and honest about what it cannot
attribute**.

## 7.2 Architecture

```
  ┌──────────────────────────┐   ┌──────────────────────────┐
  │ WAREHOUSE_METERING_      │   │ QUERY_ATTRIBUTION_       │
  │ HISTORY                  │   │ HISTORY                  │
  │                          │   │                          │
  │ Authoritative total.     │   │ Credits per query.       │
  │ Always ties to invoice.  │   │ Splits a shared          │
  │ Granularity: warehouse.  │   │ warehouse by consumer.   │
  └────────────┬─────────────┘   └────────────┬─────────────┘
               │                              │
               │  warehouse tags              │  role + warehouse tags
               ▼                              ▼
  ┌──────────────────────────┐   ┌──────────────────────────┐
  │ VW_WAREHOUSE_COST_       │   │ VW_QUERY_COST_           │
  │ ALLOCATION               │   │ ATTRIBUTION              │
  │ (the control total)      │   │ (the redistribution)     │
  └────────────┬─────────────┘   └────────────┬─────────────┘
               │                              │
               └──────────────┬───────────────┘
                              ▼
  ┌────────────────────────────────────────────────────────┐
  │ VW_CHARGEBACK_MONTHLY   compute + storage by cost centre│
  │ VW_UNALLOCATED_SPEND    the gap, with the missing tag   │
  │ VW_STORAGE_COST_ALLOCATION                              │
  └────────────────────────────────────────────────────────┘
                              ▲
  ┌───────────────────────────┴────────────────────────────┐
  │ TABLE_STORAGE_METRICS  ×  schema/database tags          │
  │ CONTROL.RATE_CARD      credits → currency, by date      │
  └─────────────────────────────────────────────────────────┘
```

## 7.3 Compute allocation

### Dedicated warehouses

Where a warehouse serves one team, its own tags allocate it completely:

```sql
SELECT OPERATING_COMPANY, DEPARTMENT, WORKLOAD_TYPE, SUM(COST)
FROM GOVERNANCE.REPORTING.VW_WAREHOUSE_COST_ALLOCATION
WHERE USAGE_DATE >= DATE_TRUNC('MONTH', CURRENT_DATE())
GROUP BY 1, 2, 3;
```

### Shared warehouses — the real case

Dedicating a warehouse per department is the naive fix, and it is expensive:
idle time multiplies, the result cache and warm local cache are fragmented, and
utilisation collapses. Real estates share warehouses, and then warehouse-level
metering cannot answer the allocation question at all.

`QUERY_ATTRIBUTION_HISTORY` gives credits per query, which allows a shared
warehouse to be split across its consumers.

**Attribution follows the consuming role, not the queried object.** This is a
deliberate policy choice with a real consequence: reading a shared reference table
bills the team that *ran* the query, not the team that publishes the table. The
alternative — billing the data owner — punishes teams for publishing useful data,
which is exactly the behaviour a data mesh needs to encourage. Publishing costs
show up as the publisher's *pipeline* compute, which is correct.

`workload_type` makes the split actionable rather than merely accurate. Comparing
ML_TRAIN spend against ML_TRAIN spend across operating companies surfaces
right-sizing opportunities that a per-department total never will — a department
whose bill doubled because it started training models is not the same problem as
one whose BI queries got slower.

### Reconciliation

The two axes disagree, always. `WAREHOUSE_METERING_HISTORY` includes idle time,
cloud services and warehouse spin-up that no individual query owns;
`QUERY_ATTRIBUTION_HISTORY` accounts only for query execution.

The rule: **metering is the control total, attribution is the split.** Unattributed
residue (idle time, cloud services) is allocated across the warehouse's consumers
in proportion to their attributed credits, and reported as a separate line so a
cost-centre owner can see it. Presenting an unexplained gap between the sum of
allocations and the invoice is how a chargeback programme loses its mandate.

## 7.4 Storage allocation

Storage is attributed through the schema's tags, split three ways — and the split
is where the value is:

| Component | Typical share | Why it is broken out |
|---|---|---|
| `ACTIVE_BYTES` | 60–75% | The data itself |
| `TIME_TRAVEL_BYTES` | 10–25% | Retention setting, not data volume |
| `FAILSAFE_BYTES` | 10–20% | 7 days, not configurable on permanent tables |

`HAS_AVOIDABLE_RETENTION_COST` flags datasets tagged `RETENTION_CLASS =
TRANSIENT_30D` that are still carrying time-travel and fail-safe storage. That
combination means a permanent table is holding short-lived data: switching it to
transient removes fail-safe entirely and typically cuts its storage bill by a
quarter to a third. Without the retention tag sitting next to the bytes, this is
invisible — which is a concrete example of governance metadata paying for the
governance programme.

## 7.5 Showback before chargeback

`cost_allocation_model` distinguishes them, and the sequencing matters:

| Value | Meaning |
|---|---|
| `SHOWBACK` | Reported to the business, not journalled |
| `CHARGEBACK` | Posts a journal entry to the ERP |
| `SHARED_SERVICE` | Split by an agreed key |
| `ABSORBED_PLATFORM` | Central platform budget |

Run showback for at least two quarters first. Chargeback numbers are disputed the
moment money moves, and every dispute traces back to a tag. Showback surfaces
those disputes while the stakes are low, and it does so with a pressure nothing
else generates: a cost-centre owner who sees `<UNALLOCATED>` on their report will
chase the missing tag far more effectively than any governance mandate.

Do not enable chargeback until `VW_UNALLOCATED_SPEND` is below ~2% of spend.

## 7.6 The unallocated bucket

```sql
SELECT RESOURCE_NAME, SUM(COST) AS COST, ANY_VALUE(MISSING_TAGS) AS MISSING
FROM GOVERNANCE.REPORTING.VW_UNALLOCATED_SPEND
WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1 ORDER BY COST DESC;
```

Nearly every row will be a **warehouse**. A warehouse has no parent to inherit
from, so all six allocation tags must be set on it directly, and any one of them
missing makes the spend unallocatable. Databases, by contrast, are tagged once
and cover ten thousand objects by inheritance. If unallocated spend is stubborn,
look at warehouse tagging before anything else.

Unallocated spend is **never silently spread across cost centres**. Spreading it
hides the tagging gap and quietly overcharges well-governed teams to subsidise
poorly-governed ones — precisely inverting the incentive the programme needs.

The view names the specific missing tags, so the remediation is a work item rather
than an investigation. A shrinking unallocated percentage is the single most
honest FinOps metric available:

| Maturity | Unallocated |
|---|---|
| Starting | 40–70% |
| Working | 10–20% |
| Good | 2–5% |
| Chargeback-ready | < 2% |

## 7.7 Cost governance beyond allocation

Tags drive spend *decisions*, not just reporting:

- **Budgets and resource monitors per department.** Group warehouses by
  `operating_company` + `department`; alert the owner named in `data_owner` rather than a central
  inbox nobody reads.
- **Non-production waste.** `environment ∈ (DEV, TST, TRAINING)` with credits
  above a threshold, and non-production warehouses with `AUTO_SUSPEND > 300`.
- **Retirement.** `DATA_LIFECYCLE = DEPRECATED` objects still accruing storage,
  and `ARCHIVED` objects that should have moved to cheaper storage. Deprecated
  data nobody deleted is one of the largest recoverable line items in a mature
  estate.
- **Criticality-tiered DR.** `CRITICALITY = LOW` databases do not need replication;
  the tag makes that a query rather than a discussion.
- **Chargeback-visible time travel.** `retention_class` next to
  `TIME_TRAVEL_BYTES` shows a team exactly what their retention choice costs, in
  currency, on their own report.

## 7.8 Reporting

| Audience | View | Cadence |
|---|---|---|
| CFO / CIO | `VW_CHARGEBACK_MONTHLY` rolled to `operating_company` | Monthly |
| Operating company controller | `VW_CHARGEBACK_MONTHLY` by `department` | Monthly |
| Cost centre owner | `VW_CHARGEBACK_MONTHLY` filtered | Monthly |
| Domain owner | `VW_QUERY_COST_ATTRIBUTION` by `domain` | Weekly |
| Platform / FinOps | `VW_UNALLOCATED_SPEND` | Weekly |
| Data product owner | Cost per data product against consumption | Monthly |

Set `CONTROL.RATE_CARD` from the commercial agreement before the first report.
Credit price varies by edition, region and contract; a hard-coded rate produces
numbers Finance will reject on sight, and the credibility is hard to win back.
