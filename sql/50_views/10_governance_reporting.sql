-- =============================================================================
-- 50_views/10_governance_reporting.sql
-- Reporting surface for stewards, auditors and executives.
-- Run as: TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA REPORTING;

-- -----------------------------------------------------------------------------
-- The steward's daily worklist.
-- -----------------------------------------------------------------------------
-- Ordered so the top of the list is genuinely the next thing to fix. A findings
-- report that is not ranked gets read once.
CREATE OR REPLACE VIEW VW_STEWARD_WORKLIST
COMMENT = 'Open findings routed to the accountable steward, ranked by severity then blast radius.'
AS
SELECT
    f.DATA_STEWARD,
    f.DATA_OWNER,
    f.DOMAIN,
    f.SEVERITY,
    f.FINDING_TYPE,
    f.OBJECT_DATABASE,
    f.OBJECT_SCHEMA,
    f.OBJECT_NAME,
    f.COLUMN_NAME,
    f.OBJECT_TYPE,
    f.TAG_NAME,
    f.RULE_ID,
    f.DETAIL,
    f.SCAN_AT,
    DATEDIFF('day', f.SCAN_AT, CURRENT_TIMESTAMP()) AS AGE_DAYS,
    CASE f.SEVERITY WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2
                    WHEN 'MEDIUM' THEN 3 ELSE 4 END AS SEVERITY_RANK,
    -- A missing tag on a database or schema propagates to everything beneath it,
    -- so fixing one parent can clear thousands of child findings. Ranking by
    -- blast radius puts those first.
    CASE f.OBJECT_TYPE WHEN 'DATABASE' THEN 1 WHEN 'SCHEMA' THEN 2
                       WHEN 'COLUMN' THEN 4 ELSE 3 END AS BLAST_RADIUS_RANK
FROM GOVERNANCE.CONTROL.COMPLIANCE_FINDING f
WHERE f.STATUS = 'OPEN'
ORDER BY SEVERITY_RANK, BLAST_RADIUS_RANK, AGE_DAYS DESC;

-- -----------------------------------------------------------------------------
-- Executive dashboard.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_COMPLIANCE_DASHBOARD
COMMENT = 'Governance scorecard by scope, with 30-day trend. The executive view.'
AS
WITH LATEST AS (
    SELECT * FROM GOVERNANCE.CONTROL.COMPLIANCE_SCORE_HISTORY
     WHERE SNAPSHOT_DATE = (SELECT MAX(SNAPSHOT_DATE)
                              FROM GOVERNANCE.CONTROL.COMPLIANCE_SCORE_HISTORY)
),
PRIOR AS (
    SELECT * FROM GOVERNANCE.CONTROL.COMPLIANCE_SCORE_HISTORY
     WHERE SNAPSHOT_DATE = (SELECT MAX(SNAPSHOT_DATE)
                              FROM GOVERNANCE.CONTROL.COMPLIANCE_SCORE_HISTORY
                             WHERE SNAPSHOT_DATE <= DATEADD('day', -30, CURRENT_DATE()))
)
SELECT
    l.SCOPE_TYPE,
    l.SCOPE_VALUE,
    l.OBJECTS_IN_SCOPE,
    l.OBJECTS_COMPLIANT,
    ROUND(100.0 * l.OBJECTS_COMPLIANT / NULLIF(l.OBJECTS_IN_SCOPE, 0), 2) AS COMPLIANCE_PCT,
    l.TIER1_COVERAGE_PCT,
    l.CRITICAL_FINDINGS,
    l.HIGH_FINDINGS,
    l.OPEN_EXCEPTIONS,
    p.TIER1_COVERAGE_PCT                            AS TIER1_COVERAGE_PCT_30D_AGO,
    ROUND(l.TIER1_COVERAGE_PCT - p.TIER1_COVERAGE_PCT, 2) AS TIER1_COVERAGE_DELTA_30D,
    -- Maturity bands from docs/11-roadmap-maturity-raci.md, computed rather
    -- than asserted in a slide.
    CASE
        WHEN l.TIER1_COVERAGE_PCT >= 98 AND l.CRITICAL_FINDINGS = 0 THEN 'L5 OPTIMISED'
        WHEN l.TIER1_COVERAGE_PCT >= 95 AND l.CRITICAL_FINDINGS = 0 THEN 'L4 MANAGED'
        WHEN l.TIER1_COVERAGE_PCT >= 80                              THEN 'L3 DEFINED'
        WHEN l.TIER1_COVERAGE_PCT >= 50                              THEN 'L2 REPEATABLE'
        ELSE 'L1 INITIAL'
    END                                             AS MATURITY_LEVEL
FROM LATEST l
LEFT JOIN PRIOR p
       ON p.SCOPE_TYPE = l.SCOPE_TYPE AND p.SCOPE_VALUE = l.SCOPE_VALUE;

-- -----------------------------------------------------------------------------
-- Data product catalogue - the Data Mesh consumer view.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_DATA_PRODUCT_CATALOG
COMMENT = 'Published data products with owner, SLA, quality tier and sensitivity. The mesh discovery surface.'
AS
SELECT
    p.DATA_PRODUCT,
    p.DOMAIN,
    p.OPERATING_COMPANY,
    p.DEPARTMENT,
    p.OBJECT_DATABASE                                AS PRODUCT_DATABASE,
    p.OBJECT_NAME                                    AS PRODUCT_SCHEMA,
    p.DATA_OWNER,
    p.DATA_STEWARD,
    p.SLA_TIER,
    p.DATA_CLASSIFICATION_ENTERPRISE,
    p.DATA_LIFECYCLE,
    p.CRITICALITY,
    p.REGULATION,
    p.DATA_CLASSIFICATION_REGULATORY,
    e_type.EFFECTIVE_VALUE                           AS DATA_PRODUCT_TYPE,
    e_qual.EFFECTIVE_VALUE                           AS DATA_QUALITY_TIER,
    e_dpo.EFFECTIVE_VALUE                            AS DATA_PRODUCT_OWNER,
    -- Consumers need to know whether a product contains regulated data before
    -- they request access, not after their request is refused.
    p.IS_REGULATED                                   AS CONTAINS_REGULATED_DATA,
    obj.N_TABLES,
    obj.N_VIEWS
FROM VW_OBJECT_TAG_PROFILE p
LEFT JOIN VW_EFFECTIVE_TAG e_type
       ON e_type.OBJECT_DATABASE = p.OBJECT_DATABASE
      AND e_type.OBJECT_NAME     = p.OBJECT_NAME
      AND e_type.OBJECT_TYPE     = 'SCHEMA'
      AND e_type.TAG_NAME        = 'DATA_PRODUCT_TYPE'
LEFT JOIN VW_EFFECTIVE_TAG e_qual
       ON e_qual.OBJECT_DATABASE = p.OBJECT_DATABASE
      AND e_qual.OBJECT_NAME     = p.OBJECT_NAME
      AND e_qual.OBJECT_TYPE     = 'SCHEMA'
      AND e_qual.TAG_NAME        = 'DATA_QUALITY_TIER'
LEFT JOIN VW_EFFECTIVE_TAG e_dpo
       ON e_dpo.OBJECT_DATABASE = p.OBJECT_DATABASE
      AND e_dpo.OBJECT_NAME     = p.OBJECT_NAME
      AND e_dpo.OBJECT_TYPE     = 'SCHEMA'
      AND e_dpo.TAG_NAME        = 'DATA_PRODUCT_OWNER'
LEFT JOIN (
    SELECT OBJECT_DATABASE, OBJECT_SCHEMA,
           COUNT_IF(OBJECT_TYPE = 'TABLE') AS N_TABLES,
           COUNT_IF(OBJECT_TYPE = 'VIEW')  AS N_VIEWS
    FROM VW_OBJECT_INVENTORY GROUP BY 1, 2
) obj ON obj.OBJECT_DATABASE = p.OBJECT_DATABASE
     AND obj.OBJECT_SCHEMA   = p.OBJECT_NAME
WHERE p.OBJECT_TYPE = 'SCHEMA'
  AND p.DATA_PRODUCT IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Tag adoption and health - is the taxonomy itself working?
-- -----------------------------------------------------------------------------
-- The question this answers is the one most tagging programmes never ask: which
-- of our tags are actually being used? A tag applied to eleven objects across a
-- 40,000-object estate is not governance, it is clutter, and it should be
-- retired or promoted deliberately rather than left to drift.
CREATE OR REPLACE VIEW VW_TAG_ADOPTION
COMMENT = 'Adoption, distinct-value spread and staleness per tag. The input to quarterly taxonomy review.'
AS
SELECT
    tc.TAG_NAME,
    tc.CANONICAL_KEY,
    tc.HIERARCHY_LEVEL,
    tc.TIER,
    tc.CATEGORY,
    tc.STATUS,
    tc.OWNER_ROLE,
    ARRAY_SIZE(tc.DRIVES)                            AS N_CONSUMERS,
    COUNT(a.TAG_NAME)                                AS N_ASSIGNMENTS,
    COUNT(DISTINCT a.TAG_VALUE)                      AS N_DISTINCT_VALUES,
    COUNT(DISTINCT a.OBJECT_DATABASE)                AS N_DATABASES,
    MAX(cl.CHANGED_AT)                               AS LAST_CHANGED_AT,
    DATEDIFF('day', MAX(cl.CHANGED_AT), CURRENT_TIMESTAMP()) AS DAYS_SINCE_LAST_CHANGE,
    CASE
        WHEN tc.STATUS <> 'ACTIVE'                   THEN 'LIFECYCLE'
        WHEN COUNT(a.TAG_NAME) = 0                   THEN 'UNUSED - retire or promote'
        WHEN COUNT(a.TAG_NAME) < 10                  THEN 'MARGINAL - review value'
        -- A controlled vocabulary of 5 values that shows 4 in use is healthy.
        -- A free-text tag with as many distinct values as assignments is not a
        -- tag, it is a comment field, and it cannot drive any automation.
        WHEN tc.VALUE_SOURCE = 'free_text'
             AND COUNT(DISTINCT a.TAG_VALUE) > 0.9 * COUNT(a.TAG_NAME)
             AND COUNT(a.TAG_NAME) > 50              THEN 'HIGH CARDINALITY - not automatable'
        ELSE 'HEALTHY'
    END                                              AS ADOPTION_VERDICT
FROM GOVERNANCE.CONTROL.TAG_CATALOG tc
LEFT JOIN VW_TAG_ASSIGNMENT a           ON a.TAG_NAME = tc.TAG_NAME
LEFT JOIN GOVERNANCE.CONTROL.TAG_CHANGE_LOG cl ON cl.TAG_NAME = tc.TAG_NAME
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, tc.VALUE_SOURCE;

-- -----------------------------------------------------------------------------
-- Audit evidence pack.
-- -----------------------------------------------------------------------------
-- Written to be handed to an assessor unmodified. Every row states the object,
-- the regime, the classification, the control that applies and whether that
-- control is actually attached - which is the only question an assessor asks.
CREATE OR REPLACE VIEW VW_COMPLIANCE_EVIDENCE
COMMENT = 'Per-object regulatory control evidence. Designed to be exported directly for an audit.'
AS
SELECT
    p.OBJECT_DATABASE,
    p.OBJECT_SCHEMA,
    p.OBJECT_NAME,
    p.OBJECT_TYPE,
    p.REGULATION                                     AS GOVERNING_REGULATION,
    p.DATA_CLASSIFICATION_REGULATORY                 AS GOVERNING_CATEGORY,
    scope.ALL_REGULATIONS,
    p.DATA_CLASSIFICATION_ENTERPRISE,
    p.RETENTION_CLASS,
    p.DATA_OWNER,
    p.DATA_STEWARD,
    p.MASKING_REQUIRED                               AS MASKING_DECLARED,
    mask.N_MASKED_COLUMNS                            AS MASKING_ENFORCED_COLUMNS,
    p.ROW_ACCESS_REQUIRED                            AS ROW_ACCESS_DECLARED,
    IFF(rap.POLICY_NAME IS NOT NULL, 'YES', 'NO')    AS ROW_ACCESS_ENFORCED,
    -- The assessor's question, answered as a single column.
    CASE
        WHEN p.ROW_ACCESS_REQUIRED = 'YES' AND rap.POLICY_NAME IS NULL
            THEN 'GAP: row access declared but not enforced'
        WHEN p.PII = 'YES' AND COALESCE(mask.N_MASKED_COLUMNS, 0) = 0
            THEN 'GAP: PII present but no column carries a masking policy'
        WHEN p.DATA_CLASSIFICATION_ENTERPRISE IS NULL
            THEN 'GAP: object is unclassified'
        ELSE 'CONTROLS ALIGNED'
    END                                              AS CONTROL_STATE
FROM VW_OBJECT_TAG_PROFILE p
LEFT JOIN (
    SELECT OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
           LISTAGG(DISTINCT REGULATION, ', ') WITHIN GROUP (ORDER BY REGULATION)
               AS ALL_REGULATIONS
    FROM GOVERNANCE.CONTROL.REGULATORY_SCOPE
    WHERE IS_ACTIVE GROUP BY 1, 2, 3
) scope ON  scope.OBJECT_DATABASE = p.OBJECT_DATABASE
        AND scope.OBJECT_SCHEMA   = p.OBJECT_SCHEMA
        AND scope.OBJECT_NAME     = p.OBJECT_NAME
LEFT JOIN (
    SELECT REF_DATABASE_NAME, REF_SCHEMA_NAME, REF_ENTITY_NAME,
           COUNT(DISTINCT REF_COLUMN_NAME) AS N_MASKED_COLUMNS
    FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
    WHERE POLICY_KIND = 'MASKING_POLICY' AND REF_COLUMN_NAME IS NOT NULL
    GROUP BY 1, 2, 3
) mask ON  mask.REF_DATABASE_NAME = p.OBJECT_DATABASE
       AND mask.REF_SCHEMA_NAME   = p.OBJECT_SCHEMA
       AND mask.REF_ENTITY_NAME   = p.OBJECT_NAME
LEFT JOIN (
    SELECT DISTINCT REF_DATABASE_NAME, REF_SCHEMA_NAME, REF_ENTITY_NAME, POLICY_NAME
    FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
    WHERE POLICY_KIND = 'ROW_ACCESS_POLICY'
) rap ON  rap.REF_DATABASE_NAME = p.OBJECT_DATABASE
      AND rap.REF_SCHEMA_NAME   = p.OBJECT_SCHEMA
      AND rap.REF_ENTITY_NAME   = p.OBJECT_NAME
WHERE p.COLUMN_NAME IS NULL
  AND p.OBJECT_TYPE IN ('TABLE', 'VIEW', 'MATERIALIZED_VIEW', 'DYNAMIC_TABLE');

GRANT SELECT ON ALL VIEWS IN SCHEMA GOVERNANCE.REPORTING TO ROLE TAG_READER;

SELECT 'Governance reporting views ready' AS status;
