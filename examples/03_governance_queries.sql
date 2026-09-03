-- =============================================================================
-- examples/03_governance_queries.sql
-- The queries governance teams actually run.
-- =============================================================================

USE ROLE TAG_READER;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;

-- ── Where is our personal data? ─────────────────────────────────────────────
-- The question a DPO asks first and most estates cannot answer.
SELECT OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, COLUMN_NAME,
       DATA_CLASSIFICATION_REGULATORY, DATA_CLASSIFICATION_ENTERPRISE,
       OPERATING_COMPANY, DATA_OWNER
FROM REPORTING.VW_OBJECT_TAG_PROFILE
WHERE IS_REGULATED
ORDER BY DATA_CLASSIFICATION_REGULATORY DESC, OBJECT_DATABASE, OBJECT_SCHEMA,
         OBJECT_NAME, COLUMN_NAME;

-- ── Which controls are declared but not enforced? ───────────────────────────
-- The highest-value query in the framework. A green compliance report that
-- cannot answer this is measuring tags, not protection.
SELECT OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, CONTROL_STATE,
       GOVERNING_CATEGORY, DATA_CLASSIFICATION_ENTERPRISE, DATA_OWNER
FROM REPORTING.VW_COMPLIANCE_EVIDENCE
WHERE CONTROL_STATE <> 'CONTROLS ALIGNED'
ORDER BY CASE WHEN CONTROL_STATE LIKE 'GAP: row access%' THEN 1
              WHEN CONTROL_STATE LIKE 'GAP: PII%'        THEN 2
              ELSE 3 END;

-- ── Regulated data that is classified as if it were not (XR-001) ───────────
-- The single most dangerous state in the estate: scores as fully covered on
-- every coverage metric, while the masking policy reads the enterprise
-- classification and lets the data through in clear.
SELECT OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, COLUMN_NAME,
       DATA_CLASSIFICATION_REGULATORY, DATA_CLASSIFICATION_ENTERPRISE
FROM REPORTING.VW_OBJECT_TAG_PROFILE
WHERE IS_REGULATED
  AND DATA_CLASSIFICATION_ENTERPRISE IN ('NONE', 'PUBLIC');

-- ── What is the governance trend by domain? ─────────────────────────────────
-- Reported per domain, never as one account-wide number: a single percentage
-- hides the stalled domain that is the actual risk.
SELECT SCOPE_VALUE AS DOMAIN, COMPLIANCE_PCT, TIER1_COVERAGE_PCT,
       TIER1_COVERAGE_DELTA_30D, CRITICAL_FINDINGS, OPEN_EXCEPTIONS,
       MATURITY_LEVEL
FROM REPORTING.VW_COMPLIANCE_DASHBOARD
WHERE SCOPE_TYPE = 'DOMAIN'
ORDER BY TIER1_COVERAGE_PCT;

-- ── Who owns this table, and who do I page at 3am? ──────────────────────────
SELECT OWNER_USER, TEAM, SUPPORT_GROUP, DATA_OWNER, DOMAIN, APPLICATION, SLA_TIER
FROM REPORTING.VW_OBJECT_TAG_PROFILE
WHERE OBJECT_DATABASE = 'CUSTOMER_PRD'
  AND OBJECT_SCHEMA   = 'C360'
  AND OBJECT_NAME     = 'CUSTOMER_MASTER'
  AND COLUMN_NAME IS NULL;

-- ── Is the taxonomy itself healthy? ─────────────────────────────────────────
-- The question most tagging programmes never ask. Input to quarterly review.
SELECT TAG_NAME, CANONICAL_KEY, TIER, N_ASSIGNMENTS, N_DISTINCT_VALUES, N_DATABASES,
       DAYS_SINCE_LAST_CHANGE, ADOPTION_VERDICT
FROM REPORTING.VW_TAG_ADOPTION
WHERE ADOPTION_VERDICT <> 'HEALTHY'
ORDER BY TIER, N_ASSIGNMENTS;

-- ── Where is spend going, and what is unallocated? ──────────────────────────
SELECT OPERATING_COMPANY, DEPARTMENT, COST_CENTER, ENVIRONMENT,
       ROUND(SUM(COMPUTE_COST), 2) AS COMPUTE,
       ROUND(SUM(STORAGE_COST), 2) AS STORAGE,
       ROUND(SUM(TOTAL_COST), 2)   AS TOTAL
FROM REPORTING.VW_CHARGEBACK_MONTHLY
WHERE BILLING_MONTH >= DATEADD('month', -3, DATE_TRUNC('MONTH', CURRENT_DATE()))
GROUP BY 1, 2, 3, 4
ORDER BY TOTAL DESC;

SELECT RESOURCE_NAME, ROUND(SUM(COST), 2) AS COST,
       ANY_VALUE(MISSING_TAGS) AS MISSING_TAGS
FROM REPORTING.VW_UNALLOCATED_SPEND
WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1
ORDER BY COST DESC;

-- ── Storage the retention tag says we should not be paying for ──────────────
SELECT OPERATING_COMPANY, OBJECT_DATABASE, OBJECT_SCHEMA, RETENTION_CLASS,
       ROUND(TIME_TRAVEL_TB + FAILSAFE_TB, 3) AS AVOIDABLE_TB,
       ROUND(MONTHLY_COST, 2) AS MONTHLY_COST
FROM REPORTING.VW_STORAGE_COST_ALLOCATION
WHERE HAS_AVOIDABLE_RETENTION_COST
ORDER BY AVOIDABLE_TB DESC;

-- ── Audit: why did this classification change? ──────────────────────────────
SELECT CHANGED_AT, CHANGED_BY, CHANGED_BY_ROLE, ACTION,
       OLD_VALUE, NEW_VALUE, CHANGE_REASON, CHANGE_TICKET, SOURCE
FROM CONTROL.TAG_CHANGE_LOG
WHERE OBJECT_DATABASE = 'CUSTOMER_PRD'
  AND OBJECT_NAME     = 'CUSTOMER_MASTER'
  AND TAG_NAME        = 'DATA_CLASSIFICATION_ENTERPRISE'
ORDER BY CHANGED_AT DESC;

-- ── Exception debt ──────────────────────────────────────────────────────────
-- Read next to the compliance percentage: 99% compliant with 400 open
-- exceptions is not 99% compliant.
SELECT STATUS, COUNT(*) AS N,
       MIN(EXPIRES_AT) AS EARLIEST_EXPIRY,
       COUNT_IF(EXPIRES_AT < CURRENT_TIMESTAMP()) AS ALREADY_LAPSED
FROM CONTROL.TAG_EXCEPTION
GROUP BY 1;
