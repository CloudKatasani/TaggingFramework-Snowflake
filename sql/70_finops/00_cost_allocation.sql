-- =============================================================================
-- 70_finops/00_cost_allocation.sql
-- Tag-driven cost allocation, chargeback and showback.
-- -----------------------------------------------------------------------------
-- THE CENTRAL PROBLEM
-- -------------------
-- Warehouse-level metering answers "what did this warehouse cost". It cannot
-- answer "what did this business unit cost" as soon as two business units share
-- a warehouse - which they always do, because per-BU warehouses waste money on
-- idle time and lose the benefit of a warm cache.
--
-- So this framework allocates on two axes and reconciles them:
--
--   WAREHOUSE_METERING_HISTORY   authoritative total spend. Always ties to the
--                                invoice. Attribution is only as good as the
--                                warehouse's own tags.
--   QUERY_ATTRIBUTION_HISTORY    per-query credit attribution. Lets a shared
--                                warehouse be split across the tags of the
--                                objects each query actually touched.
--
-- The invoice is the control total. Query attribution redistributes it. Anything
-- that cannot be attributed lands in VW_UNALLOCATED_SPEND rather than being
-- silently spread - an unallocated bucket that shrinks over time is the single
-- most honest FinOps metric there is.
--
-- Run as: TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA CONTROL;

-- Credit price varies by edition, region and contract. Never hard-code it.
CREATE TABLE IF NOT EXISTS RATE_CARD (
    EFFECTIVE_FROM   DATE   NOT NULL,
    EFFECTIVE_TO     DATE,
    CREDIT_PRICE     NUMBER(12,4) NOT NULL,
    STORAGE_PRICE_TB NUMBER(12,4) NOT NULL,
    CURRENCY         STRING NOT NULL DEFAULT 'USD',
    CONSTRAINT PK_RATE_CARD PRIMARY KEY (EFFECTIVE_FROM) RELY
)
COMMENT = 'Contracted Snowflake pricing by effective date. Sourced from the commercial agreement.';

USE SCHEMA REPORTING;

-- -----------------------------------------------------------------------------
-- Warehouse spend, attributed by warehouse tags.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_WAREHOUSE_COST_ALLOCATION
COMMENT = 'Daily warehouse credits and cost, attributed via the warehouse''s own tags.'
AS
SELECT
    DATE_TRUNC('DAY', m.START_TIME)::DATE          AS USAGE_DATE,
    m.WAREHOUSE_NAME,
    p.BUSINESS_UNIT,
    p.DOMAIN,
    p.COST_CENTER,
    p.ENVIRONMENT,
    p.CRITICALITY,
    SUM(m.CREDITS_USED_COMPUTE)                    AS CREDITS_COMPUTE,
    SUM(m.CREDITS_USED_CLOUD_SERVICES)             AS CREDITS_CLOUD_SERVICES,
    SUM(m.CREDITS_USED)                            AS CREDITS_TOTAL,
    SUM(m.CREDITS_USED) * MAX(r.CREDIT_PRICE)      AS COST,
    MAX(r.CURRENCY)                                AS CURRENCY,
    -- Everything the business is charged for must name a payer. This flag is
    -- what makes the gap visible instead of absorbing it into a platform budget.
    (p.COST_CENTER IS NULL)                        AS IS_UNALLOCATED
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY m
LEFT JOIN VW_OBJECT_TAG_PROFILE p
       ON p.OBJECT_TYPE = 'WAREHOUSE' AND p.OBJECT_NAME = m.WAREHOUSE_NAME
LEFT JOIN GOVERNANCE.CONTROL.RATE_CARD r
       ON m.START_TIME::DATE BETWEEN r.EFFECTIVE_FROM
                                 AND COALESCE(r.EFFECTIVE_TO, '9999-12-31'::DATE)
GROUP BY 1, 2, 3, 4, 5, 6, 7;

-- -----------------------------------------------------------------------------
-- Per-query attribution: splits a shared warehouse across the consuming tags.
-- -----------------------------------------------------------------------------
-- QUERY_ATTRIBUTION_HISTORY gives credits per query. Joining it to the tags of
-- the *querying role* rather than the queried object is deliberate: chargeback
-- follows who ran the workload, not whose data was read. Reading a shared
-- reference table should not bill the team that publishes it.
CREATE OR REPLACE VIEW VW_QUERY_COST_ATTRIBUTION
COMMENT = 'Per-query credit attribution, keyed to the consuming role and warehouse tags.'
AS
-- QUERY_ATTRIBUTION_HISTORY already carries WAREHOUSE_NAME, USER_NAME and
-- ROLE_NAME, so no join to QUERY_HISTORY is needed. That join would be the most
-- expensive part of this view for no additional information.
SELECT
    DATE_TRUNC('DAY', qa.START_TIME)::DATE         AS USAGE_DATE,
    qa.WAREHOUSE_NAME,
    qa.USER_NAME,
    qa.ROLE_NAME,
    -- Attribution follows the CONSUMING role, not the queried object: reading a
    -- shared reference table must not bill the team that publishes it, or the
    -- mesh penalises exactly the behaviour it needs to encourage.
    COALESCE(rp.BUSINESS_UNIT, wp.BUSINESS_UNIT)   AS BUSINESS_UNIT,
    COALESCE(rp.COST_CENTER,   wp.COST_CENTER)     AS COST_CENTER,
    wp.ENVIRONMENT,
    COUNT(*)                                       AS QUERY_COUNT,
    SUM(qa.CREDITS_ATTRIBUTED_COMPUTE)             AS CREDITS_ATTRIBUTED,
    SUM(qa.CREDITS_ATTRIBUTED_COMPUTE) * MAX(rc.CREDIT_PRICE) AS COST,
    -- Falling back to the warehouse means the consuming role is untagged:
    -- accurate at warehouse level, imprecise below it. Surfaced rather than
    -- hidden, because it is the specific gap a steward can close.
    BOOLOR_AGG(rp.COST_CENTER IS NULL)             AS FELL_BACK_TO_WAREHOUSE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY qa
LEFT JOIN VW_OBJECT_TAG_PROFILE rp
       ON rp.OBJECT_TYPE = 'ROLE' AND rp.OBJECT_NAME = qa.ROLE_NAME
LEFT JOIN VW_OBJECT_TAG_PROFILE wp
       ON wp.OBJECT_TYPE = 'WAREHOUSE' AND wp.OBJECT_NAME = qa.WAREHOUSE_NAME
LEFT JOIN GOVERNANCE.CONTROL.RATE_CARD rc
       ON qa.START_TIME::DATE BETWEEN rc.EFFECTIVE_FROM
                                  AND COALESCE(rc.EFFECTIVE_TO, '9999-12-31'::DATE)
GROUP BY 1, 2, 3, 4, 5, 6, 7;

-- -----------------------------------------------------------------------------
-- Storage, attributed through database and schema tags.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_STORAGE_COST_ALLOCATION
COMMENT = 'Table storage attributed via schema/database tags, split active vs time-travel vs fail-safe.'
AS
SELECT
    CURRENT_DATE()                                  AS AS_OF_DATE,
    s.TABLE_CATALOG                                 AS OBJECT_DATABASE,
    s.TABLE_SCHEMA                                  AS OBJECT_SCHEMA,
    p.BUSINESS_UNIT,
    p.DOMAIN,
    p.COST_CENTER,
    p.ENVIRONMENT,
    p.RETENTION_CLASS,
    SUM(s.ACTIVE_BYTES)              / POWER(1024, 4) AS ACTIVE_TB,
    SUM(s.TIME_TRAVEL_BYTES)         / POWER(1024, 4) AS TIME_TRAVEL_TB,
    SUM(s.FAILSAFE_BYTES)            / POWER(1024, 4) AS FAILSAFE_TB,
    (SUM(s.ACTIVE_BYTES + s.TIME_TRAVEL_BYTES + s.FAILSAFE_BYTES)
        / POWER(1024, 4)) * MAX(r.STORAGE_PRICE_TB)   AS MONTHLY_COST,
    -- Time travel and fail-safe on a TRANSIENT_30D dataset is pure waste, and
    -- it is invisible without the retention tag sitting next to the bytes.
    IFF(p.RETENTION_CLASS = 'TRANSIENT_30D'
        AND SUM(s.TIME_TRAVEL_BYTES + s.FAILSAFE_BYTES) > 0,
        TRUE, FALSE)                                 AS HAS_AVOIDABLE_RETENTION_COST
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS s
LEFT JOIN VW_OBJECT_TAG_PROFILE p
       ON  p.OBJECT_DATABASE = s.TABLE_CATALOG
       AND p.OBJECT_NAME     = s.TABLE_SCHEMA
       AND p.OBJECT_TYPE     = 'SCHEMA'
LEFT JOIN GOVERNANCE.CONTROL.RATE_CARD r
       ON CURRENT_DATE() BETWEEN r.EFFECTIVE_FROM
                             AND COALESCE(r.EFFECTIVE_TO, '9999-12-31'::DATE)
WHERE s.DELETED = FALSE
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;

-- -----------------------------------------------------------------------------
-- The monthly chargeback statement.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_CHARGEBACK_MONTHLY
COMMENT = 'Monthly compute + storage by cost centre. The number that posts to the GL.'
AS
WITH COMPUTE AS (
    SELECT DATE_TRUNC('MONTH', USAGE_DATE)::DATE AS BILLING_MONTH,
           BUSINESS_UNIT, DOMAIN, COST_CENTER, ENVIRONMENT,
           SUM(CREDITS_TOTAL) AS CREDITS, SUM(COST) AS COMPUTE_COST
    FROM VW_WAREHOUSE_COST_ALLOCATION
    GROUP BY 1, 2, 3, 4, 5
),
STORAGE AS (
    SELECT DATE_TRUNC('MONTH', AS_OF_DATE)::DATE AS BILLING_MONTH,
           BUSINESS_UNIT, DOMAIN, COST_CENTER, ENVIRONMENT,
           SUM(MONTHLY_COST) AS STORAGE_COST
    FROM VW_STORAGE_COST_ALLOCATION
    GROUP BY 1, 2, 3, 4, 5
)
SELECT
    COALESCE(c.BILLING_MONTH, s.BILLING_MONTH)   AS BILLING_MONTH,
    COALESCE(c.BUSINESS_UNIT, s.BUSINESS_UNIT, '<UNALLOCATED>') AS BUSINESS_UNIT,
    COALESCE(c.DOMAIN,        s.DOMAIN,        '<UNALLOCATED>') AS DOMAIN,
    COALESCE(c.COST_CENTER,   s.COST_CENTER,   '<UNALLOCATED>') AS COST_CENTER,
    COALESCE(c.ENVIRONMENT,   s.ENVIRONMENT,   '<UNTAGGED>')    AS ENVIRONMENT,
    COALESCE(c.CREDITS, 0)                       AS CREDITS,
    COALESCE(c.COMPUTE_COST, 0)                  AS COMPUTE_COST,
    COALESCE(s.STORAGE_COST, 0)                  AS STORAGE_COST,
    COALESCE(c.COMPUTE_COST, 0) + COALESCE(s.STORAGE_COST, 0) AS TOTAL_COST,
    cc.GL_ACCOUNT
FROM COMPUTE c
FULL OUTER JOIN STORAGE s
  ON  c.BILLING_MONTH = s.BILLING_MONTH
  AND EQUAL_NULL(c.COST_CENTER, s.COST_CENTER)
  AND EQUAL_NULL(c.ENVIRONMENT, s.ENVIRONMENT)
LEFT JOIN GOVERNANCE.CONTROL.REF_COST_CENTER cc
       ON cc.COST_CENTER = COALESCE(c.COST_CENTER, s.COST_CENTER);

-- -----------------------------------------------------------------------------
-- The gap. Watch this shrink.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_UNALLOCATED_SPEND
COMMENT = 'Spend that cannot be attributed to a cost centre, with the specific missing tag named.'
AS
SELECT
    USAGE_DATE,
    'WAREHOUSE'                        AS RESOURCE_TYPE,
    WAREHOUSE_NAME                     AS RESOURCE_NAME,
    CREDITS_TOTAL,
    COST,
    ARRAY_COMPACT(ARRAY_CONSTRUCT(
        IFF(BUSINESS_UNIT IS NULL, 'BUSINESS_UNIT', NULL),
        IFF(COST_CENTER   IS NULL, 'COST_CENTER',   NULL),
        IFF(ENVIRONMENT   IS NULL, 'ENVIRONMENT',   NULL)
    ))                                 AS MISSING_TAGS
FROM VW_WAREHOUSE_COST_ALLOCATION
WHERE IS_UNALLOCATED;

SELECT 'FinOps allocation views ready' AS status;
