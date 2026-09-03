-- =============================================================================
-- 50_views/00_inventory_and_effective_tags.sql
-- The two views every other governance object is built on.
-- -----------------------------------------------------------------------------
-- VW_OBJECT_INVENTORY   what exists and should be tagged
-- VW_EFFECTIVE_TAG      what tag value actually applies to each object, after
--                       inheritance and override resolution
--
-- LATENCY - read this before trusting a number from these views
-- ------------------------------------------------------------
-- ACCOUNT_USAGE views lag by up to ~2 hours (TAG_REFERENCES) and up to ~90
-- minutes (TABLES/COLUMNS). That is fine for reporting, scorecards and drift
-- detection, and NOT fine for a deployment gate. Anything that must block a
-- release reads INFORMATION_SCHEMA.TAG_REFERENCES or SYSTEM$GET_TAG instead,
-- both of which are immediate. VW_EFFECTIVE_TAG_LIVE below is the no-latency
-- equivalent for a single object.
--
-- Run as: TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA REPORTING;

-- -----------------------------------------------------------------------------
-- Direct (non-inherited) enterprise tag assignments across the account.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_TAG_ASSIGNMENT
COMMENT = 'Every direct assignment of an enterprise tag. Excludes inherited values and dropped objects.'
AS
SELECT
    tr.TAG_NAME,
    tr.TAG_VALUE,
    tr.OBJECT_DATABASE,
    tr.OBJECT_SCHEMA,
    tr.OBJECT_NAME,
    tr.COLUMN_NAME,
    -- ACCOUNT_USAGE calls the object type DOMAIN, which collides with the
    -- enterprise DOMAIN tag. Renamed once, here, so nothing downstream has to
    -- disambiguate it.
    tr.DOMAIN AS OBJECT_TYPE,
    tr.OBJECT_ID,
    tr.OBJECT_DELETED
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES tr
WHERE tr.TAG_DATABASE = 'GOVERNANCE'
  AND tr.TAG_SCHEMA   = 'TAGS'
  AND tr.OBJECT_DELETED IS NULL;

-- -----------------------------------------------------------------------------
-- Objects that the framework expects to carry tags.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_OBJECT_INVENTORY
COMMENT = 'All taggable objects in scope of the framework, normalised to one shape.'
AS
-- Every branch aliases all seven columns explicitly and casts its NULLs. Relying
-- on positional UNION with unnamed literals produces duplicate auto-generated
-- column names inside a CTE and leaves NULL columns untyped, both of which fail
-- in ways that are tedious to diagnose.
WITH DATABASES AS (
    SELECT DATABASE_NAME      AS OBJECT_DATABASE,
           NULL::STRING       AS OBJECT_SCHEMA,
           DATABASE_NAME      AS OBJECT_NAME,
           NULL::STRING       AS COLUMN_NAME,
           'DATABASE'::STRING AS OBJECT_TYPE,
           DATABASE_OWNER     AS OBJECT_OWNER,
           CREATED            AS CREATED_ON
    FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASES
    WHERE DELETED IS NULL
      AND TYPE <> 'IMPORTED DATABASE'          -- inbound shares are governed at the share
      AND DATABASE_NAME NOT IN ('SNOWFLAKE', 'SNOWFLAKE_SAMPLE_DATA')
),
SCHEMAS AS (
    SELECT CATALOG_NAME      AS OBJECT_DATABASE,
           SCHEMA_NAME       AS OBJECT_SCHEMA,
           SCHEMA_NAME       AS OBJECT_NAME,
           NULL::STRING      AS COLUMN_NAME,
           'SCHEMA'::STRING  AS OBJECT_TYPE,
           SCHEMA_OWNER      AS OBJECT_OWNER,
           CREATED           AS CREATED_ON
    FROM SNOWFLAKE.ACCOUNT_USAGE.SCHEMATA
    WHERE DELETED IS NULL
      AND SCHEMA_NAME <> 'INFORMATION_SCHEMA'
      AND CATALOG_NAME NOT IN ('SNOWFLAKE', 'SNOWFLAKE_SAMPLE_DATA')
),
TABLES AS (
    SELECT TABLE_CATALOG AS OBJECT_DATABASE,
           TABLE_SCHEMA  AS OBJECT_SCHEMA,
           TABLE_NAME    AS OBJECT_NAME,
           NULL::STRING  AS COLUMN_NAME,
           CASE TABLE_TYPE
                WHEN 'BASE TABLE'        THEN 'TABLE'
                WHEN 'VIEW'              THEN 'VIEW'
                WHEN 'MATERIALIZED VIEW' THEN 'MATERIALIZED_VIEW'
                WHEN 'EXTERNAL TABLE'    THEN 'EXTERNAL_TABLE'
                ELSE UPPER(REPLACE(TABLE_TYPE, ' ', '_'))
           END::STRING   AS OBJECT_TYPE,
           TABLE_OWNER   AS OBJECT_OWNER,
           CREATED       AS CREATED_ON
    FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES
    WHERE DELETED IS NULL
      AND TABLE_SCHEMA <> 'INFORMATION_SCHEMA'
      AND TABLE_CATALOG NOT IN ('SNOWFLAKE', 'SNOWFLAKE_SAMPLE_DATA')
),
COLUMNS AS (
    -- Columns outnumber every other object class by orders of magnitude, which
    -- is why column-level obligations are scoped rather than universal - see
    -- VW_COLUMN_IN_SCOPE and docs/03-mandatory-vs-optional.md §3.4.
    SELECT TABLE_CATALOG    AS OBJECT_DATABASE,
           TABLE_SCHEMA     AS OBJECT_SCHEMA,
           TABLE_NAME       AS OBJECT_NAME,
           COLUMN_NAME      AS COLUMN_NAME,
           'COLUMN'::STRING AS OBJECT_TYPE,
           NULL::STRING     AS OBJECT_OWNER,
           NULL::TIMESTAMP_LTZ AS CREATED_ON
    FROM SNOWFLAKE.ACCOUNT_USAGE.COLUMNS
    WHERE DELETED IS NULL
      AND TABLE_SCHEMA <> 'INFORMATION_SCHEMA'
      AND TABLE_CATALOG NOT IN ('SNOWFLAKE', 'SNOWFLAKE_SAMPLE_DATA')
),
WAREHOUSES AS (
    SELECT NULL::STRING       AS OBJECT_DATABASE,
           NULL::STRING       AS OBJECT_SCHEMA,
           WAREHOUSE_NAME     AS OBJECT_NAME,
           NULL::STRING       AS COLUMN_NAME,
           'WAREHOUSE'::STRING AS OBJECT_TYPE,
           NULL::STRING       AS OBJECT_OWNER,
           CREATED            AS CREATED_ON
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSES
    WHERE DELETED IS NULL
),
STAGES AS (
    SELECT STAGE_CATALOG  AS OBJECT_DATABASE,
           STAGE_SCHEMA   AS OBJECT_SCHEMA,
           STAGE_NAME     AS OBJECT_NAME,
           NULL::STRING   AS COLUMN_NAME,
           'STAGE'::STRING AS OBJECT_TYPE,
           STAGE_OWNER    AS OBJECT_OWNER,
           CREATED        AS CREATED_ON
    FROM SNOWFLAKE.ACCOUNT_USAGE.STAGES
    WHERE DELETED IS NULL
),
PIPES AS (
    SELECT PIPE_CATALOG  AS OBJECT_DATABASE,
           PIPE_SCHEMA   AS OBJECT_SCHEMA,
           PIPE_NAME     AS OBJECT_NAME,
           NULL::STRING  AS COLUMN_NAME,
           'PIPE'::STRING AS OBJECT_TYPE,
           PIPE_OWNER    AS OBJECT_OWNER,
           CREATED       AS CREATED_ON
    FROM SNOWFLAKE.ACCOUNT_USAGE.PIPES
    WHERE DELETED IS NULL
),
TASKS AS (
    SELECT DATABASE_NAME AS OBJECT_DATABASE,
           SCHEMA_NAME   AS OBJECT_SCHEMA,
           NAME          AS OBJECT_NAME,
           NULL::STRING  AS COLUMN_NAME,
           'TASK'::STRING AS OBJECT_TYPE,
           OWNER         AS OBJECT_OWNER,
           CREATED       AS CREATED_ON
    FROM SNOWFLAKE.ACCOUNT_USAGE.TASKS
    WHERE DELETED IS NULL
),
-- Object classes with no ACCOUNT_USAGE view of their own - shares, roles,
-- integrations, notebooks, Streamlit apps. Only the TAGGED ones can be seen
-- here, which is a real and deliberate limitation: a completely untagged share
-- is invisible to this inventory, so conditional rules on those object types
-- (CR-007 in particular) verify the tags of shares that carry at least one tag,
-- not the existence of shares that carry none.
--
-- Closing that gap requires enumerating them with SHOW SHARES / SHOW ROLES into
-- a control table on a schedule; that job is intentionally out of scope here
-- rather than implied by an inventory that quietly omits them.
TAG_ONLY_OBJECTS AS (
    SELECT DISTINCT
           a.OBJECT_DATABASE,
           a.OBJECT_SCHEMA,
           a.OBJECT_NAME,
           NULL::STRING AS COLUMN_NAME,
           a.OBJECT_TYPE,
           NULL::STRING AS OBJECT_OWNER,
           NULL::TIMESTAMP_LTZ AS CREATED_ON
    FROM VW_TAG_ASSIGNMENT a
    WHERE a.COLUMN_NAME IS NULL
      AND a.OBJECT_TYPE IN ('SHARE', 'ROLE', 'USER', 'INTEGRATION',
                            'NOTEBOOK', 'STREAMLIT', 'APPLICATION',
                            'STREAM', 'FUNCTION', 'PROCEDURE',
                            'DYNAMIC_TABLE', 'ICEBERG_TABLE')
)
SELECT * FROM DATABASES
UNION ALL SELECT * FROM SCHEMAS
UNION ALL SELECT * FROM TABLES
UNION ALL SELECT * FROM COLUMNS
UNION ALL SELECT * FROM WAREHOUSES
UNION ALL SELECT * FROM STAGES
UNION ALL SELECT * FROM PIPES
UNION ALL SELECT * FROM TASKS
UNION ALL SELECT * FROM TAG_ONLY_OBJECTS;

-- -----------------------------------------------------------------------------
-- VW_EFFECTIVE_TAG - inheritance and override resolution, in one place.
-- -----------------------------------------------------------------------------
-- Two resolution modes, chosen per tag by TAG_CATALOG.OVERRIDE_RULE:
--
--   nearest-wins        the value set closest to the object applies. Correct for
--                       descriptive facts (DATA_OWNER, COST_CENTER) where a more
--                       specific statement is simply better information.
--
--   most-restrictive    the strongest value anywhere in the lineage applies,
--                       regardless of depth. Correct for controls
--                       (DATA_CLASSIFICATION, PII, CRITICALITY): a column must
--                       not become less protected than the table it lives in
--                       just because someone tagged the column later.
--
-- Getting this backwards is the single most consequential modelling error in a
-- tagging framework, because it is invisible until an audit.
CREATE OR REPLACE VIEW VW_EFFECTIVE_TAG
COMMENT = 'Effective tag value per object after inheritance, using each tag''s own override rule.'
AS
WITH ASSIGNMENTS AS (
    SELECT * FROM VW_TAG_ASSIGNMENT
),
-- Every object paired with every ancestor assignment that could reach it.
CANDIDATES AS (
    -- Level 0: the object's own tag.
    SELECT i.OBJECT_DATABASE, i.OBJECT_SCHEMA, i.OBJECT_NAME, i.COLUMN_NAME,
           i.OBJECT_TYPE, a.TAG_NAME, a.TAG_VALUE, 0 AS DISTANCE,
           i.OBJECT_TYPE AS SOURCE_LEVEL
    FROM VW_OBJECT_INVENTORY i
    JOIN ASSIGNMENTS a
      ON  a.OBJECT_TYPE = i.OBJECT_TYPE
      AND EQUAL_NULL(a.OBJECT_DATABASE, i.OBJECT_DATABASE)
      AND EQUAL_NULL(a.OBJECT_SCHEMA,   i.OBJECT_SCHEMA)
      AND a.OBJECT_NAME = i.OBJECT_NAME
      AND EQUAL_NULL(a.COLUMN_NAME, i.COLUMN_NAME)

    UNION ALL

    -- Level 1: a column inherits from its table.
    SELECT i.OBJECT_DATABASE, i.OBJECT_SCHEMA, i.OBJECT_NAME, i.COLUMN_NAME,
           i.OBJECT_TYPE, a.TAG_NAME, a.TAG_VALUE, 1, 'TABLE'
    FROM VW_OBJECT_INVENTORY i
    JOIN ASSIGNMENTS a
      ON  a.OBJECT_DATABASE = i.OBJECT_DATABASE
      AND a.OBJECT_SCHEMA   = i.OBJECT_SCHEMA
      AND a.OBJECT_NAME     = i.OBJECT_NAME
      AND a.COLUMN_NAME IS NULL
      AND a.OBJECT_TYPE IN ('TABLE', 'VIEW', 'MATERIALIZED_VIEW', 'EXTERNAL_TABLE')
    WHERE i.OBJECT_TYPE = 'COLUMN'

    UNION ALL

    -- Level 2: anything inside a schema inherits from that schema.
    SELECT i.OBJECT_DATABASE, i.OBJECT_SCHEMA, i.OBJECT_NAME, i.COLUMN_NAME,
           i.OBJECT_TYPE, a.TAG_NAME, a.TAG_VALUE,
           IFF(i.OBJECT_TYPE = 'COLUMN', 2, 1), 'SCHEMA'
    FROM VW_OBJECT_INVENTORY i
    JOIN ASSIGNMENTS a
      ON  a.OBJECT_DATABASE = i.OBJECT_DATABASE
      AND a.OBJECT_NAME     = i.OBJECT_SCHEMA
      AND a.OBJECT_TYPE     = 'SCHEMA'
    WHERE i.OBJECT_SCHEMA IS NOT NULL
      AND i.OBJECT_TYPE <> 'SCHEMA'

    UNION ALL

    -- Level 3: everything in a database inherits from that database.
    SELECT i.OBJECT_DATABASE, i.OBJECT_SCHEMA, i.OBJECT_NAME, i.COLUMN_NAME,
           i.OBJECT_TYPE, a.TAG_NAME, a.TAG_VALUE,
           CASE i.OBJECT_TYPE WHEN 'COLUMN' THEN 3 WHEN 'SCHEMA' THEN 1 ELSE 2 END,
           'DATABASE'
    FROM VW_OBJECT_INVENTORY i
    JOIN ASSIGNMENTS a
      ON  a.OBJECT_NAME = i.OBJECT_DATABASE
      AND a.OBJECT_TYPE = 'DATABASE'
    WHERE i.OBJECT_DATABASE IS NOT NULL
      AND i.OBJECT_TYPE <> 'DATABASE'
),
RANKED AS (
    SELECT c.*,
           tc.OVERRIDE_RULE,
           av.ORDINAL_POSITION,
           ROW_NUMBER() OVER (
               PARTITION BY c.OBJECT_DATABASE, c.OBJECT_SCHEMA, c.OBJECT_NAME,
                            c.COLUMN_NAME, c.OBJECT_TYPE, c.TAG_NAME
               ORDER BY
                   -- Controls: strongest value first, ties broken by proximity.
                   -- Descriptive tags: nearest value first.
                   CASE WHEN tc.OVERRIDE_RULE = 'more_restrictive_only'
                        THEN -COALESCE(av.ORDINAL_POSITION, 0) ELSE 0 END,
                   c.DISTANCE
           ) AS RN
    FROM CANDIDATES c
    JOIN GOVERNANCE.CONTROL.TAG_CATALOG tc ON tc.TAG_NAME = c.TAG_NAME
    LEFT JOIN GOVERNANCE.CONTROL.TAG_ALLOWED_VALUE av
           ON av.TAG_NAME = c.TAG_NAME AND av.TAG_VALUE = c.TAG_VALUE
)
SELECT
    OBJECT_DATABASE,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    COLUMN_NAME,
    OBJECT_TYPE,
    TAG_NAME,
    TAG_VALUE          AS EFFECTIVE_VALUE,
    SOURCE_LEVEL       AS INHERITED_FROM,
    DISTANCE           AS INHERITANCE_DISTANCE,
    (DISTANCE = 0)     AS IS_DIRECTLY_ASSIGNED,
    OVERRIDE_RULE
FROM RANKED
WHERE RN = 1;

-- -----------------------------------------------------------------------------
-- VW_OBJECT_TAG_PROFILE - one row per object, Tier 1 tags pivoted out.
-- -----------------------------------------------------------------------------
-- The shape almost every consumer actually wants: joinable, one row per object,
-- no pivoting in the caller. Deliberately limited to Tier 1 - a view with 42
-- columns is a view nobody reads.
CREATE OR REPLACE VIEW VW_OBJECT_TAG_PROFILE
COMMENT = 'One row per object with the Tier 1 enterprise tags resolved and pivoted.'
AS
SELECT
    OBJECT_DATABASE,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    COLUMN_NAME,
    OBJECT_TYPE,
    MAX(IFF(TAG_NAME = 'BUSINESS_UNIT',       EFFECTIVE_VALUE, NULL)) AS BUSINESS_UNIT,
    MAX(IFF(TAG_NAME = 'DOMAIN',              EFFECTIVE_VALUE, NULL)) AS DOMAIN,
    MAX(IFF(TAG_NAME = 'DATA_PRODUCT',        EFFECTIVE_VALUE, NULL)) AS DATA_PRODUCT,
    MAX(IFF(TAG_NAME = 'DATA_OWNER',          EFFECTIVE_VALUE, NULL)) AS DATA_OWNER,
    MAX(IFF(TAG_NAME = 'DATA_STEWARD',        EFFECTIVE_VALUE, NULL)) AS DATA_STEWARD,
    MAX(IFF(TAG_NAME = 'SUPPORT_GROUP',       EFFECTIVE_VALUE, NULL)) AS SUPPORT_GROUP,
    MAX(IFF(TAG_NAME = 'DATA_CLASSIFICATION', EFFECTIVE_VALUE, NULL)) AS DATA_CLASSIFICATION,
    MAX(IFF(TAG_NAME = 'PII',                 EFFECTIVE_VALUE, NULL)) AS PII,
    MAX(IFF(TAG_NAME = 'ENVIRONMENT',         EFFECTIVE_VALUE, NULL)) AS ENVIRONMENT,
    MAX(IFF(TAG_NAME = 'DATA_LIFECYCLE',      EFFECTIVE_VALUE, NULL)) AS DATA_LIFECYCLE,
    MAX(IFF(TAG_NAME = 'CRITICALITY',         EFFECTIVE_VALUE, NULL)) AS CRITICALITY,
    MAX(IFF(TAG_NAME = 'COST_CENTER',         EFFECTIVE_VALUE, NULL)) AS COST_CENTER,
    MAX(IFF(TAG_NAME = 'RETENTION_CLASS',     EFFECTIVE_VALUE, NULL)) AS RETENTION_CLASS,
    MAX(IFF(TAG_NAME = 'REGULATION',          EFFECTIVE_VALUE, NULL)) AS REGULATION,
    MAX(IFF(TAG_NAME = 'MASKING_REQUIRED',    EFFECTIVE_VALUE, NULL)) AS MASKING_REQUIRED,
    MAX(IFF(TAG_NAME = 'ROW_ACCESS_REQUIRED', EFFECTIVE_VALUE, NULL)) AS ROW_ACCESS_REQUIRED,
    MAX(IFF(TAG_NAME = 'SLA_TIER',            EFFECTIVE_VALUE, NULL)) AS SLA_TIER
FROM VW_EFFECTIVE_TAG
GROUP BY 1, 2, 3, 4, 5;

SELECT 'Inventory and effective-tag views ready' AS status;
