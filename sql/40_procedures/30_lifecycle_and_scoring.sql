-- =============================================================================
-- 40_procedures/30_lifecycle_and_scoring.sql
--   SP_REMEDIATE_CLONE_TAGS   fixes ENVIRONMENT after a clone
--   SP_SNAPSHOT_COMPLIANCE    writes the daily governance scorecard
--   SP_RETIRE_TAG             the safe path to removing a tag from the estate
-- Run as: TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA AUTOMATION;

-- =============================================================================
-- SP_REMEDIATE_CLONE_TAGS
-- =============================================================================
-- CLONE copies tags along with the object. That is usually what you want - and
-- for ENVIRONMENT it is exactly wrong: cloning PROD to build a UAT refresh
-- produces a UAT database whose every object insists it is PROD. Cost reports
-- then bill UAT compute to the production cost centre, and the promotion gate
-- believes UAT objects have already passed production review.
--
-- Left alone this is one of the most common and most expensive tagging defects
-- in a large Snowflake estate, because nothing about it looks broken.
CREATE OR REPLACE PROCEDURE SP_REMEDIATE_CLONE_TAGS(
    P_DATABASE            STRING,
    P_CORRECT_ENVIRONMENT STRING,   -- PRD | UAT | TST | DEV | TRAINING | BACKUP
    P_DRY_RUN             BOOLEAN
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Rewrites ENVIRONMENT (and clears certifications) on a freshly cloned database.'
AS
$$
DECLARE
    V_FIXED   NUMBER := 0;
    V_DB      STRING;
    V_SCHEMA  STRING;
    V_NAME    STRING;
    V_TYPE    STRING;
    V_FQN     STRING;
    C_WRONG CURSOR FOR
        SELECT OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, OBJECT_TYPE
        FROM GOVERNANCE.REPORTING.VW_EFFECTIVE_TAG
        WHERE TAG_NAME = 'ENVIRONMENT'
          AND IS_DIRECTLY_ASSIGNED
          AND OBJECT_DATABASE = :P_DATABASE
          AND EFFECTIVE_VALUE <> :P_CORRECT_ENVIRONMENT;
BEGIN
    FOR rec IN C_WRONG DO
        V_DB     := rec.OBJECT_DATABASE;
        V_SCHEMA := rec.OBJECT_SCHEMA;
        V_NAME   := rec.OBJECT_NAME;
        V_TYPE   := rec.OBJECT_TYPE;

        -- A database's own FQN is just its name; a schema's is db.schema; every
        -- other object is db.schema.name.
        V_FQN := CASE
            WHEN V_TYPE = 'DATABASE' THEN V_DB
            WHEN V_TYPE = 'SCHEMA'   THEN V_DB || '.' || V_NAME
            ELSE V_DB || '.' || V_SCHEMA || '.' || V_NAME
        END;

        IF (NOT P_DRY_RUN) THEN
            CALL SP_APPLY_TAG(:V_TYPE, :V_FQN, NULL,
                'ENVIRONMENT', :P_CORRECT_ENVIRONMENT,
                'Clone remediation: object was cloned from another environment.',
                NULL, 'REMEDIATION');
        END IF;
        V_FIXED := V_FIXED + 1;
    END FOR;

    -- A clone is not a certified data product. Quality certification and SLA
    -- commitments belong to the original and must be re-earned, not inherited
    -- by copy.
    IF (NOT P_DRY_RUN) THEN
        INSERT INTO GOVERNANCE.CONTROL.COMPLIANCE_FINDING
            (SCAN_ID, SCAN_AT, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
             OBJECT_TYPE, TAG_NAME, FINDING_TYPE, SEVERITY, DETAIL)
        SELECT 'CLONE-REMEDIATION', CURRENT_TIMESTAMP(), OBJECT_DATABASE,
               OBJECT_SCHEMA, OBJECT_NAME, OBJECT_TYPE, 'DATA_QUALITY_TIER',
               'STALE_TAG', 'MEDIUM',
               'Quality certification was carried in by CLONE and does not apply ' ||
               'to this copy. Re-certify or unset.'
        FROM GOVERNANCE.REPORTING.VW_EFFECTIVE_TAG
        WHERE TAG_NAME = 'DATA_QUALITY_TIER'
          AND IS_DIRECTLY_ASSIGNED
          AND OBJECT_DATABASE = :P_DATABASE;
    END IF;

    RETURN IFF(P_DRY_RUN, 'DRY RUN: ', '') || V_FIXED ||
           ' objects re-tagged to ENVIRONMENT = ' || :P_CORRECT_ENVIRONMENT || '.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR ' || SQLCODE || ': ' || SQLERRM;
END;
$$;

-- =============================================================================
-- SP_SNAPSHOT_COMPLIANCE
-- =============================================================================
-- Point-in-time findings tell a steward what to fix today. The trend tells an
-- executive whether the programme is working. Without the second, governance
-- funding does not survive its second budget cycle.
CREATE OR REPLACE PROCEDURE SP_SNAPSHOT_COMPLIANCE()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Writes the daily governance scorecard into CONTROL.COMPLIANCE_SCORE_HISTORY.'
AS
$$
BEGIN
    DELETE FROM GOVERNANCE.CONTROL.COMPLIANCE_SCORE_HISTORY
     WHERE SNAPSHOT_DATE = CURRENT_DATE();

    INSERT INTO GOVERNANCE.CONTROL.COMPLIANCE_SCORE_HISTORY
        (SNAPSHOT_DATE, SCOPE_TYPE, SCOPE_VALUE, OBJECTS_IN_SCOPE,
         OBJECTS_COMPLIANT, TIER1_COVERAGE_PCT, CRITICAL_FINDINGS,
         HIGH_FINDINGS, OPEN_EXCEPTIONS)
    WITH SCOPED AS (
        -- Every object, labelled with each scope it rolls up to. UNION ALL over
        -- three grains keeps one query producing the whole scorecard.
        SELECT 'ACCOUNT' AS SCOPE_TYPE, 'ACCOUNT' AS SCOPE_VALUE,
               p.OBJECT_DATABASE, p.OBJECT_SCHEMA, p.OBJECT_NAME, p.OBJECT_TYPE
        FROM GOVERNANCE.REPORTING.VW_OBJECT_TAG_PROFILE p
        WHERE p.COLUMN_NAME IS NULL
        UNION ALL
        SELECT 'OPERATING_COMPANY', COALESCE(p.OPERATING_COMPANY, '<UNTAGGED>'),
               p.OBJECT_DATABASE, p.OBJECT_SCHEMA, p.OBJECT_NAME, p.OBJECT_TYPE
        FROM GOVERNANCE.REPORTING.VW_OBJECT_TAG_PROFILE p
        WHERE p.COLUMN_NAME IS NULL
        UNION ALL
        SELECT 'DEPARTMENT', COALESCE(p.DEPARTMENT, '<UNTAGGED>'),
               p.OBJECT_DATABASE, p.OBJECT_SCHEMA, p.OBJECT_NAME, p.OBJECT_TYPE
        FROM GOVERNANCE.REPORTING.VW_OBJECT_TAG_PROFILE p
        WHERE p.COLUMN_NAME IS NULL
        UNION ALL
        SELECT 'DOMAIN', COALESCE(p.DOMAIN, '<UNTAGGED>'),
               p.OBJECT_DATABASE, p.OBJECT_SCHEMA, p.OBJECT_NAME, p.OBJECT_TYPE
        FROM GOVERNANCE.REPORTING.VW_OBJECT_TAG_PROFILE p
        WHERE p.COLUMN_NAME IS NULL
    ),
    FINDINGS AS (
        SELECT OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, OBJECT_TYPE,
               COUNT(*)                                       AS N_FINDINGS,
               COUNT_IF(SEVERITY = 'CRITICAL')                 AS N_CRITICAL,
               COUNT_IF(SEVERITY = 'HIGH')                     AS N_HIGH
        FROM GOVERNANCE.CONTROL.COMPLIANCE_FINDING
        WHERE STATUS = 'OPEN' AND COLUMN_NAME IS NULL
        GROUP BY 1, 2, 3, 4
    ),
    TIER1_COVERAGE AS (
        -- Share of the mandatory Tier 1 surface that is actually populated.
        SELECT s.SCOPE_TYPE, s.SCOPE_VALUE,
               COUNT_IF(e.EFFECTIVE_VALUE IS NOT NULL) AS FILLED,
               COUNT(*)                                AS REQUIRED
        FROM SCOPED s
        JOIN GOVERNANCE.CONTROL.TAG_REQUIREMENT r
          ON r.OBJECT_TYPE = s.OBJECT_TYPE AND r.REQUIREMENT_LEVEL = 'MANDATORY'
        JOIN GOVERNANCE.CONTROL.TAG_CATALOG tc
          ON tc.TAG_NAME = r.TAG_NAME AND tc.TIER = 1 AND tc.STATUS = 'ACTIVE'
        LEFT JOIN GOVERNANCE.REPORTING.VW_EFFECTIVE_TAG e
          ON  EQUAL_NULL(e.OBJECT_DATABASE, s.OBJECT_DATABASE)
          AND EQUAL_NULL(e.OBJECT_SCHEMA,   s.OBJECT_SCHEMA)
          AND e.OBJECT_NAME = s.OBJECT_NAME
          AND e.OBJECT_TYPE = s.OBJECT_TYPE
          AND e.COLUMN_NAME IS NULL
          AND e.TAG_NAME    = r.TAG_NAME
        GROUP BY 1, 2
    )
    SELECT
        CURRENT_DATE(),
        s.SCOPE_TYPE,
        s.SCOPE_VALUE,
        COUNT(*),
        COUNT_IF(f.N_FINDINGS IS NULL),
        ROUND(100.0 * MAX(c.FILLED) / NULLIF(MAX(c.REQUIRED), 0), 2),
        COALESCE(SUM(f.N_CRITICAL), 0),
        COALESCE(SUM(f.N_HIGH), 0),
        (SELECT COUNT(*) FROM GOVERNANCE.CONTROL.TAG_EXCEPTION WHERE STATUS = 'ACTIVE')
    FROM SCOPED s
    LEFT JOIN FINDINGS f
      ON  EQUAL_NULL(f.OBJECT_DATABASE, s.OBJECT_DATABASE)
      AND EQUAL_NULL(f.OBJECT_SCHEMA,   s.OBJECT_SCHEMA)
      AND f.OBJECT_NAME = s.OBJECT_NAME
      AND f.OBJECT_TYPE = s.OBJECT_TYPE
    LEFT JOIN TIER1_COVERAGE c
      ON c.SCOPE_TYPE = s.SCOPE_TYPE AND c.SCOPE_VALUE = s.SCOPE_VALUE
    GROUP BY 1, 2, 3;

    RETURN 'Compliance scorecard written for ' || CURRENT_DATE() || '.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR ' || SQLCODE || ': ' || SQLERRM;
END;
$$;

-- =============================================================================
-- SP_RETIRE_TAG
-- =============================================================================
-- Removing a tag is the operation most likely to break something silently.
-- DROP TAG succeeds even when thousands of objects carry it, taking every
-- assignment - and any masking policy attached to it - with it.
--
-- This procedure refuses to drop anything. It reports what a drop would destroy
-- and unsets assignments in a controlled, logged sweep, leaving the DROP as a
-- separate deliberate act once the count reaches zero.
CREATE OR REPLACE PROCEDURE SP_RETIRE_TAG(P_TAG_NAME STRING, P_EXECUTE BOOLEAN)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Safely withdraws a tag from the estate. Never drops the tag object itself.'
AS
$$
DECLARE
    V_ASSIGNMENTS NUMBER;
    V_POLICIES    NUMBER;
    V_UNSET       NUMBER := 0;
    V_DB          STRING;
    V_SCHEMA      STRING;
    V_NAME        STRING;
    V_COLUMN      STRING;
    V_TYPE        STRING;
    V_FQN         STRING;
    C_ASSIGNED CURSOR FOR
        SELECT OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, COLUMN_NAME, OBJECT_TYPE
        FROM GOVERNANCE.REPORTING.VW_TAG_ASSIGNMENT
        WHERE TAG_NAME = :P_TAG_NAME;
BEGIN
    V_ASSIGNMENTS := (SELECT COUNT(*)
                        FROM GOVERNANCE.REPORTING.VW_TAG_ASSIGNMENT
                       WHERE TAG_NAME = :P_TAG_NAME);

    V_POLICIES := (SELECT COUNT(*)
                     FROM GOVERNANCE.CONTROL.TAG_POLICY_BINDING
                    WHERE TAG_NAME = :P_TAG_NAME AND IS_ACTIVE);

    IF (V_POLICIES > 0) THEN
        RETURN 'BLOCKED: ' || :P_TAG_NAME || ' still has ' || V_POLICIES ||
               ' active policy binding(s). Detach the policies first - dropping ' ||
               'this tag would silently unmask every column that relies on it.';
    END IF;

    IF (NOT P_EXECUTE) THEN
        RETURN 'DRY RUN: retiring ' || :P_TAG_NAME || ' would unset ' ||
               V_ASSIGNMENTS || ' assignment(s). Re-run with P_EXECUTE => TRUE.';
    END IF;

    FOR rec IN C_ASSIGNED DO
        V_DB     := rec.OBJECT_DATABASE;
        V_SCHEMA := rec.OBJECT_SCHEMA;
        V_NAME   := rec.OBJECT_NAME;
        V_COLUMN := rec.COLUMN_NAME;
        V_TYPE   := rec.OBJECT_TYPE;

        V_FQN := CASE
            WHEN V_TYPE = 'DATABASE'  THEN V_DB
            WHEN V_TYPE = 'SCHEMA'    THEN V_DB || '.' || V_NAME
            WHEN V_TYPE = 'WAREHOUSE' THEN V_NAME
            ELSE V_DB || '.' || V_SCHEMA || '.' || V_NAME
        END;

        CALL SP_APPLY_TAG(:V_TYPE, :V_FQN, :V_COLUMN, :P_TAG_NAME, NULL,
            'Tag retirement sweep.', NULL, 'REMEDIATION');
        V_UNSET := V_UNSET + 1;
    END FOR;

    UPDATE GOVERNANCE.CONTROL.TAG_CATALOG
       SET STATUS = 'RETIRED' WHERE TAG_NAME = :P_TAG_NAME;

    RETURN V_UNSET || ' assignments removed. ' || :P_TAG_NAME ||
           ' is now RETIRED and rejects new assignments. The tag object is ' ||
           'deliberately left in place so historical ACCOUNT_USAGE queries ' ||
           'still resolve; drop it only after the audit retention window.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR ' || SQLCODE || ': ' || SQLERRM;
END;
$$;

SELECT 'Lifecycle and scoring procedures ready' AS status;
