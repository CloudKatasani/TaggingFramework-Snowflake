-- =============================================================================
-- 40_procedures/10_validate_compliance.sql
-- SP_VALIDATE_COMPLIANCE - the scanner that turns the taxonomy into findings.
-- -----------------------------------------------------------------------------
-- Set-based by design. A cursor loop over an estate with tens of millions of
-- columns does not finish; every check below is a single INSERT ... SELECT and
-- the whole scan is one warehouse-minute on an XSMALL.
--
-- Scoping decision worth understanding
-- ------------------------------------
-- Mandatory column-level tags are NOT demanded of every column in the account.
-- A 5,000-database estate has hundreds of millions of columns and demanding a
-- PII decision on every one produces a backlog nobody will ever clear - which
-- discredits the whole programme. Column obligations apply only where the parent
-- table already indicates regulated or sensitive content (VW_COLUMN_IN_SCOPE).
-- Everything else is covered by inheritance from the table.
--
-- Run as: TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA REPORTING;

-- -----------------------------------------------------------------------------
-- Columns that carry column-level obligations.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_COLUMN_IN_SCOPE
COMMENT = 'Columns subject to column-level mandatory tagging: those in tables flagged as regulated or sensitive.'
AS
SELECT c.OBJECT_DATABASE, c.OBJECT_SCHEMA, c.OBJECT_NAME, c.COLUMN_NAME
FROM VW_OBJECT_INVENTORY c
JOIN VW_OBJECT_TAG_PROFILE t
  ON  t.OBJECT_DATABASE = c.OBJECT_DATABASE
  AND t.OBJECT_SCHEMA   = c.OBJECT_SCHEMA
  AND t.OBJECT_NAME     = c.OBJECT_NAME
  AND t.COLUMN_NAME IS NULL
WHERE c.OBJECT_TYPE = 'COLUMN'
  AND (   t.PII = 'YES'
       OR t.DATA_CLASSIFICATION IN ('RESTRICTED', 'HIGHLY_RESTRICTED')
       OR COALESCE(t.REGULATION, 'NONE') <> 'NONE');

USE SCHEMA AUTOMATION;

CREATE OR REPLACE PROCEDURE SP_VALIDATE_COMPLIANCE(
    P_SCOPE_DATABASE STRING,     -- NULL = whole account
    P_PURGE_PRIOR    BOOLEAN     -- TRUE closes prior OPEN findings first
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Scans the estate against the tag catalog and writes CONTROL.COMPLIANCE_FINDING.'
AS
$$
DECLARE
    V_SCAN_ID STRING;
    V_SCAN_AT TIMESTAMP_NTZ;
    V_COUNT   NUMBER;
BEGIN
    V_SCAN_ID := UUID_STRING();
    V_SCAN_AT := CURRENT_TIMESTAMP();

    IF (P_PURGE_PRIOR) THEN
        -- Findings are point-in-time. Anything still wrong is re-raised by this
        -- scan; anything not re-raised was fixed, so it is closed rather than
        -- left to rot as a permanently open item nobody trusts.
        UPDATE GOVERNANCE.CONTROL.COMPLIANCE_FINDING
           SET STATUS = 'REMEDIATED', REMEDIATED_AT = :V_SCAN_AT
         WHERE STATUS = 'OPEN'
           AND (:P_SCOPE_DATABASE IS NULL OR OBJECT_DATABASE = :P_SCOPE_DATABASE);
    END IF;

    -- =====================================================================
    -- CHECK 1: missing mandatory tags (object level)
    -- =====================================================================
    INSERT INTO GOVERNANCE.CONTROL.COMPLIANCE_FINDING
        (SCAN_ID, SCAN_AT, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
         OBJECT_TYPE, COLUMN_NAME, TAG_NAME, FINDING_TYPE, SEVERITY, DETAIL,
         EXPECTED_VALUE, DOMAIN, DATA_OWNER, DATA_STEWARD)
    SELECT
        :V_SCAN_ID, :V_SCAN_AT,
        i.OBJECT_DATABASE, i.OBJECT_SCHEMA, i.OBJECT_NAME, i.OBJECT_TYPE, NULL,
        r.TAG_NAME, 'MISSING_MANDATORY_TAG',
        CASE WHEN tc.TIER = 1 THEN 'HIGH' WHEN tc.TIER = 2 THEN 'MEDIUM' ELSE 'LOW' END,
        'Tier ' || tc.TIER || ' tag ' || r.TAG_NAME || ' is mandatory on ' ||
            i.OBJECT_TYPE || ' but is neither set nor inherited.',
        '<any valid value>',
        p.DOMAIN, p.DATA_OWNER, p.DATA_STEWARD
    FROM GOVERNANCE.REPORTING.VW_OBJECT_INVENTORY i
    JOIN GOVERNANCE.CONTROL.TAG_REQUIREMENT r
      ON r.OBJECT_TYPE = i.OBJECT_TYPE AND r.REQUIREMENT_LEVEL = 'MANDATORY'
    JOIN GOVERNANCE.CONTROL.TAG_CATALOG tc
      ON tc.TAG_NAME = r.TAG_NAME AND tc.STATUS = 'ACTIVE'
    LEFT JOIN GOVERNANCE.REPORTING.VW_EFFECTIVE_TAG e
      ON  EQUAL_NULL(e.OBJECT_DATABASE, i.OBJECT_DATABASE)
      AND EQUAL_NULL(e.OBJECT_SCHEMA,   i.OBJECT_SCHEMA)
      AND e.OBJECT_NAME = i.OBJECT_NAME
      AND e.OBJECT_TYPE = i.OBJECT_TYPE
      AND e.COLUMN_NAME IS NULL
      AND e.TAG_NAME    = r.TAG_NAME
    LEFT JOIN GOVERNANCE.REPORTING.VW_OBJECT_TAG_PROFILE p
      ON  EQUAL_NULL(p.OBJECT_DATABASE, i.OBJECT_DATABASE)
      AND EQUAL_NULL(p.OBJECT_SCHEMA,   i.OBJECT_SCHEMA)
      AND p.OBJECT_NAME = i.OBJECT_NAME
      AND p.OBJECT_TYPE = i.OBJECT_TYPE
      AND p.COLUMN_NAME IS NULL
    WHERE i.OBJECT_TYPE <> 'COLUMN'
      AND e.EFFECTIVE_VALUE IS NULL
      AND (:P_SCOPE_DATABASE IS NULL OR i.OBJECT_DATABASE = :P_SCOPE_DATABASE);

    -- =====================================================================
    -- CHECK 2: missing mandatory tags (column level, scoped)
    -- =====================================================================
    INSERT INTO GOVERNANCE.CONTROL.COMPLIANCE_FINDING
        (SCAN_ID, SCAN_AT, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
         OBJECT_TYPE, COLUMN_NAME, TAG_NAME, FINDING_TYPE, SEVERITY, DETAIL,
         DOMAIN, DATA_OWNER, DATA_STEWARD)
    SELECT
        :V_SCAN_ID, :V_SCAN_AT,
        s.OBJECT_DATABASE, s.OBJECT_SCHEMA, s.OBJECT_NAME, 'COLUMN', s.COLUMN_NAME,
        r.TAG_NAME, 'MISSING_MANDATORY_TAG', 'HIGH',
        'Column-level tag ' || r.TAG_NAME || ' is mandatory on columns of ' ||
            'regulated or sensitive tables, but is not set.',
        p.DOMAIN, p.DATA_OWNER, p.DATA_STEWARD
    FROM GOVERNANCE.REPORTING.VW_COLUMN_IN_SCOPE s
    JOIN GOVERNANCE.CONTROL.TAG_REQUIREMENT r
      ON r.OBJECT_TYPE = 'COLUMN' AND r.REQUIREMENT_LEVEL = 'MANDATORY'
    JOIN GOVERNANCE.CONTROL.TAG_CATALOG tc
      ON tc.TAG_NAME = r.TAG_NAME AND tc.STATUS = 'ACTIVE'
    LEFT JOIN GOVERNANCE.REPORTING.VW_EFFECTIVE_TAG e
      ON  e.OBJECT_DATABASE = s.OBJECT_DATABASE
      AND e.OBJECT_SCHEMA   = s.OBJECT_SCHEMA
      AND e.OBJECT_NAME     = s.OBJECT_NAME
      AND e.COLUMN_NAME     = s.COLUMN_NAME
      AND e.OBJECT_TYPE     = 'COLUMN'
      AND e.TAG_NAME        = r.TAG_NAME
    LEFT JOIN GOVERNANCE.REPORTING.VW_OBJECT_TAG_PROFILE p
      ON  p.OBJECT_DATABASE = s.OBJECT_DATABASE
      AND p.OBJECT_SCHEMA   = s.OBJECT_SCHEMA
      AND p.OBJECT_NAME     = s.OBJECT_NAME
      AND p.COLUMN_NAME IS NULL
    WHERE e.EFFECTIVE_VALUE IS NULL
      AND (:P_SCOPE_DATABASE IS NULL OR s.OBJECT_DATABASE = :P_SCOPE_DATABASE);

    -- =====================================================================
    -- CHECK 3: reference values that have gone stale
    -- =====================================================================
    -- A cost centre closes in the ERP, a support group is dissolved, an
    -- application is decommissioned - and the tag keeps pointing at it. Snowflake
    -- validated the value on the day it was set and never looks again; this is
    -- the check that keeps chargeback from posting to a closed GL account.
    INSERT INTO GOVERNANCE.CONTROL.COMPLIANCE_FINDING
        (SCAN_ID, SCAN_AT, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
         OBJECT_TYPE, COLUMN_NAME, TAG_NAME, FINDING_TYPE, SEVERITY, DETAIL,
         OBSERVED_VALUE)
    SELECT
        :V_SCAN_ID, :V_SCAN_AT,
        e.OBJECT_DATABASE, e.OBJECT_SCHEMA, e.OBJECT_NAME, e.OBJECT_TYPE,
        e.COLUMN_NAME, e.TAG_NAME, 'UNKNOWN_REFERENCE_VALUE', 'MEDIUM',
        'Value "' || e.EFFECTIVE_VALUE || '" is not an active member of ' ||
            tc.REFERENCE_SET || '. It was valid when set and has since been retired.',
        e.EFFECTIVE_VALUE
    FROM GOVERNANCE.REPORTING.VW_EFFECTIVE_TAG e
    JOIN GOVERNANCE.CONTROL.TAG_CATALOG tc
      ON tc.TAG_NAME = e.TAG_NAME AND tc.VALUE_SOURCE = 'reference_data'
    LEFT JOIN GOVERNANCE.CONTROL.REFERENCE_VALUE rv
      ON  rv.REFERENCE_SET = tc.REFERENCE_SET
      AND rv.VALUE_CODE    = e.EFFECTIVE_VALUE
      AND rv.IS_ACTIVE
      AND CURRENT_DATE() BETWEEN rv.VALID_FROM AND COALESCE(rv.VALID_TO, '9999-12-31'::DATE)
    WHERE e.IS_DIRECTLY_ASSIGNED
      AND rv.VALUE_CODE IS NULL
      AND (:P_SCOPE_DATABASE IS NULL OR e.OBJECT_DATABASE = :P_SCOPE_DATABASE);

    -- =====================================================================
    -- CHECK 4: conditional rule breaches
    -- =====================================================================
    -- Rules are stored as {tag: [values]} predicates. Flattening them here means
    -- a new rule is a row in TAG_CONDITIONAL_RULE, never a change to this
    -- procedure - which is what keeps the control set reviewable by people who
    -- do not read SQL.
    INSERT INTO GOVERNANCE.CONTROL.COMPLIANCE_FINDING
        (SCAN_ID, SCAN_AT, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
         OBJECT_TYPE, COLUMN_NAME, TAG_NAME, RULE_ID, FINDING_TYPE, SEVERITY,
         DETAIL, DOMAIN, DATA_OWNER, DATA_STEWARD)
    WITH RULE_TARGET AS (
        SELECT r.RULE_ID, r.DESCRIPTION, r.SEVERITY,
               ot.VALUE::STRING AS OBJECT_TYPE,
               tm.VALUE::STRING AS REQUIRED_TAG,
               r.PREDICATE
        FROM GOVERNANCE.CONTROL.TAG_CONDITIONAL_RULE r,
             LATERAL FLATTEN(INPUT => r.OBJECT_TYPES)   ot,
             LATERAL FLATTEN(INPUT => r.THEN_MANDATORY) tm
        WHERE r.IS_ACTIVE
    ),
    -- An object satisfies a predicate when every clause matches. A rule with an
    -- empty predicate ({}) applies unconditionally.
    PREDICATE_CLAUSE AS (
        SELECT rt.RULE_ID, f.KEY AS PRED_TAG, f.VALUE AS PRED_VALUES
        FROM (SELECT DISTINCT RULE_ID, PREDICATE FROM RULE_TARGET) rt,
             LATERAL FLATTEN(INPUT => rt.PREDICATE) f
    ),
    CLAUSE_COUNT AS (
        SELECT RULE_ID, COUNT(*) AS N_CLAUSES FROM PREDICATE_CLAUSE GROUP BY RULE_ID
    ),
    OBJECT_MATCH AS (
        SELECT p.OBJECT_DATABASE, p.OBJECT_SCHEMA, p.OBJECT_NAME, p.COLUMN_NAME,
               p.OBJECT_TYPE, rt.RULE_ID,
               COUNT(DISTINCT pc.PRED_TAG) AS MATCHED_CLAUSES
        FROM GOVERNANCE.REPORTING.VW_OBJECT_TAG_PROFILE p
        JOIN RULE_TARGET rt ON rt.OBJECT_TYPE = p.OBJECT_TYPE
        LEFT JOIN PREDICATE_CLAUSE pc ON pc.RULE_ID = rt.RULE_ID
        LEFT JOIN GOVERNANCE.REPORTING.VW_EFFECTIVE_TAG et
          ON  EQUAL_NULL(et.OBJECT_DATABASE, p.OBJECT_DATABASE)
          AND EQUAL_NULL(et.OBJECT_SCHEMA,   p.OBJECT_SCHEMA)
          AND et.OBJECT_NAME = p.OBJECT_NAME
          AND EQUAL_NULL(et.COLUMN_NAME, p.COLUMN_NAME)
          AND et.OBJECT_TYPE = p.OBJECT_TYPE
          AND et.TAG_NAME    = pc.PRED_TAG
          AND ARRAY_CONTAINS(et.EFFECTIVE_VALUE::VARIANT, pc.PRED_VALUES)
        WHERE et.EFFECTIVE_VALUE IS NOT NULL OR pc.PRED_TAG IS NULL
        GROUP BY 1, 2, 3, 4, 5, 6
    )
    SELECT
        :V_SCAN_ID, :V_SCAN_AT,
        om.OBJECT_DATABASE, om.OBJECT_SCHEMA, om.OBJECT_NAME, om.OBJECT_TYPE,
        om.COLUMN_NAME, rt.REQUIRED_TAG, rt.RULE_ID, 'CONDITIONAL_RULE_BREACH',
        rt.SEVERITY,
        rt.RULE_ID || ': ' || rt.DESCRIPTION ||
            ' Tag ' || rt.REQUIRED_TAG || ' is required here but is absent.',
        p.DOMAIN, p.DATA_OWNER, p.DATA_STEWARD
    FROM OBJECT_MATCH om
    JOIN RULE_TARGET rt
      ON rt.RULE_ID = om.RULE_ID AND rt.OBJECT_TYPE = om.OBJECT_TYPE
    LEFT JOIN CLAUSE_COUNT cc ON cc.RULE_ID = om.RULE_ID
    JOIN GOVERNANCE.REPORTING.VW_OBJECT_TAG_PROFILE p
      ON  EQUAL_NULL(p.OBJECT_DATABASE, om.OBJECT_DATABASE)
      AND EQUAL_NULL(p.OBJECT_SCHEMA,   om.OBJECT_SCHEMA)
      AND p.OBJECT_NAME = om.OBJECT_NAME
      AND EQUAL_NULL(p.COLUMN_NAME, om.COLUMN_NAME)
      AND p.OBJECT_TYPE = om.OBJECT_TYPE
    LEFT JOIN GOVERNANCE.REPORTING.VW_EFFECTIVE_TAG req
      ON  EQUAL_NULL(req.OBJECT_DATABASE, om.OBJECT_DATABASE)
      AND EQUAL_NULL(req.OBJECT_SCHEMA,   om.OBJECT_SCHEMA)
      AND req.OBJECT_NAME = om.OBJECT_NAME
      AND EQUAL_NULL(req.COLUMN_NAME, om.COLUMN_NAME)
      AND req.OBJECT_TYPE = om.OBJECT_TYPE
      AND req.TAG_NAME    = rt.REQUIRED_TAG
    WHERE om.MATCHED_CLAUSES = COALESCE(cc.N_CLAUSES, 0)   -- predicate satisfied
      AND req.EFFECTIVE_VALUE IS NULL                      -- required tag absent
      AND (:P_SCOPE_DATABASE IS NULL OR om.OBJECT_DATABASE = :P_SCOPE_DATABASE);

    -- =====================================================================
    -- CHECK 5: expired exceptions
    -- =====================================================================
    UPDATE GOVERNANCE.CONTROL.TAG_EXCEPTION
       SET STATUS = 'EXPIRED'
     WHERE STATUS = 'ACTIVE' AND EXPIRES_AT <= :V_SCAN_AT;

    INSERT INTO GOVERNANCE.CONTROL.COMPLIANCE_FINDING
        (SCAN_ID, SCAN_AT, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
         OBJECT_TYPE, COLUMN_NAME, TAG_NAME, FINDING_TYPE, SEVERITY, DETAIL)
    SELECT
        :V_SCAN_ID, :V_SCAN_AT, x.OBJECT_DATABASE, x.OBJECT_SCHEMA, x.OBJECT_NAME,
        x.OBJECT_TYPE, x.COLUMN_NAME, x.TAG_NAME, 'EXPIRED_EXCEPTION', 'HIGH',
        'Exception ' || x.EXCEPTION_ID || ' expired on ' ||
            TO_VARCHAR(x.EXPIRES_AT, 'YYYY-MM-DD') ||
            ' and the underlying condition has not been remediated. ' ||
            'Compensating control was: ' || x.COMPENSATING_CONTROL
    FROM GOVERNANCE.CONTROL.TAG_EXCEPTION x
    WHERE x.STATUS = 'EXPIRED'
      AND (:P_SCOPE_DATABASE IS NULL OR x.OBJECT_DATABASE = :P_SCOPE_DATABASE);

    -- =====================================================================
    -- CHECK 6: shadow tags - enterprise-looking tags created outside GOVERNANCE
    -- =====================================================================
    -- The taxonomy is only closed if nothing else looks like it. A local
    -- MYDB.UTIL.PII tag masks nothing, reports nowhere, and gives its creator
    -- entirely unfounded confidence.
    INSERT INTO GOVERNANCE.CONTROL.COMPLIANCE_FINDING
        (SCAN_ID, SCAN_AT, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
         OBJECT_TYPE, TAG_NAME, FINDING_TYPE, SEVERITY, DETAIL)
    SELECT
        :V_SCAN_ID, :V_SCAN_AT, t.TAG_DATABASE, t.TAG_SCHEMA, t.TAG_NAME,
        'TAG', t.TAG_NAME, 'UNGOVERNED_TAG_NAMESPACE', 'MEDIUM',
        'Tag ' || t.TAG_DATABASE || '.' || t.TAG_SCHEMA || '.' || t.TAG_NAME ||
            ' exists outside GOVERNANCE.TAGS' ||
            IFF(c.TAG_NAME IS NOT NULL,
                ' and shadows the enterprise tag of the same name.',
                '. Register it or drop it.')
    FROM SNOWFLAKE.ACCOUNT_USAGE.TAGS t
    LEFT JOIN GOVERNANCE.CONTROL.TAG_CATALOG c ON c.TAG_NAME = t.TAG_NAME
    WHERE t.DELETED IS NULL
      AND NOT (t.TAG_DATABASE = 'GOVERNANCE' AND t.TAG_SCHEMA = 'TAGS')
      AND t.TAG_DATABASE <> 'SNOWFLAKE';   -- SNOWFLAKE.CORE system tags are expected

    -- =====================================================================
    -- Suppress findings already covered by a live, approved exception.
    -- =====================================================================
    UPDATE GOVERNANCE.CONTROL.COMPLIANCE_FINDING f
       SET STATUS = 'EXCEPTED', EXCEPTION_ID = x.EXCEPTION_ID
      FROM GOVERNANCE.CONTROL.TAG_EXCEPTION x
     WHERE f.SCAN_ID = :V_SCAN_ID
       AND f.STATUS  = 'OPEN'
       AND x.STATUS  = 'ACTIVE'
       AND x.EXPIRES_AT > :V_SCAN_AT
       AND x.TAG_NAME = f.TAG_NAME
       AND x.OBJECT_DATABASE = f.OBJECT_DATABASE
       AND EQUAL_NULL(x.OBJECT_SCHEMA, f.OBJECT_SCHEMA)
       AND EQUAL_NULL(x.OBJECT_NAME,   f.OBJECT_NAME)
       AND EQUAL_NULL(x.COLUMN_NAME,   f.COLUMN_NAME);

    SELECT COUNT(*) INTO :V_COUNT
      FROM GOVERNANCE.CONTROL.COMPLIANCE_FINDING
     WHERE SCAN_ID = :V_SCAN_ID AND STATUS = 'OPEN';

    RETURN 'Scan ' || V_SCAN_ID || ' complete: ' || V_COUNT || ' open findings' ||
           COALESCE(' in ' || :P_SCOPE_DATABASE, ' account-wide') || '.';

EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR ' || SQLCODE || ': ' || SQLERRM;
END;
$$;

SELECT 'SP_VALIDATE_COMPLIANCE ready' AS status;
