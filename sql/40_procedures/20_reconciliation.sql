-- =============================================================================
-- 40_procedures/20_reconciliation.sql
-- Reconciliation procedures - the bridge between declared intent and enforced
-- reality.
-- -----------------------------------------------------------------------------
--   SP_APPLY_ROW_ACCESS_POLICIES   ROW_ACCESS_REQUIRED tag -> actual policy
--   SP_RECONCILE_CLASSIFICATION    Snowflake auto-classification -> PII tag
--   SP_DETECT_POLICY_DRIFT         declared bindings vs POLICY_REFERENCES
--
-- Run as: TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA AUTOMATION;

-- =============================================================================
-- SP_APPLY_ROW_ACCESS_POLICIES
-- =============================================================================
-- Closes the gap Snowflake leaves open: masking policies can be attached to a
-- tag, row access policies cannot. This procedure reads the ROW_ACCESS_REQUIRED
-- tag and issues the ALTER TABLE statements that tag attachment would have done
-- for us.
--
-- The policy signature must bind to a real column. A table declaring
-- ROW_ACCESS_REQUIRED = YES without a BUSINESS_UNIT column cannot be protected
-- by the standard policy, and is reported rather than silently skipped - a
-- silently skipped table is an unprotected table with a compliant-looking tag,
-- which is the worst of both worlds.
CREATE OR REPLACE PROCEDURE SP_APPLY_ROW_ACCESS_POLICIES(P_DRY_RUN BOOLEAN)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Applies row access policies to tables tagged ROW_ACCESS_REQUIRED = YES.'
AS
$$
DECLARE
    V_APPLIED   NUMBER := 0;
    V_SKIPPED   NUMBER := 0;
    V_STMT      STRING;
    V_FQN       STRING;
    C_TARGETS CURSOR FOR
        SELECT p.OBJECT_DATABASE, p.OBJECT_SCHEMA, p.OBJECT_NAME, p.OBJECT_TYPE,
               col.COLUMN_NAME AS BU_COLUMN
        FROM GOVERNANCE.REPORTING.VW_OBJECT_TAG_PROFILE p
        -- Does the table expose the dimension the policy needs?
        LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.COLUMNS col
          ON  col.TABLE_CATALOG = p.OBJECT_DATABASE
          AND col.TABLE_SCHEMA  = p.OBJECT_SCHEMA
          AND col.TABLE_NAME    = p.OBJECT_NAME
          AND col.COLUMN_NAME   = 'BUSINESS_UNIT'
          AND col.DELETED IS NULL
        -- Already protected?
        LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES pr
          ON  pr.REF_DATABASE_NAME = p.OBJECT_DATABASE
          AND pr.REF_SCHEMA_NAME   = p.OBJECT_SCHEMA
          AND pr.REF_ENTITY_NAME   = p.OBJECT_NAME
          AND pr.POLICY_KIND       = 'ROW_ACCESS_POLICY'
        WHERE p.COLUMN_NAME IS NULL
          AND p.ROW_ACCESS_REQUIRED = 'YES'
          AND p.OBJECT_TYPE IN ('TABLE', 'VIEW', 'MATERIALIZED_VIEW', 'DYNAMIC_TABLE')
          AND pr.POLICY_NAME IS NULL;
BEGIN
    FOR rec IN C_TARGETS DO
        V_FQN := rec.OBJECT_DATABASE || '.' || rec.OBJECT_SCHEMA || '.' || rec.OBJECT_NAME;

        IF (rec.BU_COLUMN IS NULL) THEN
            V_SKIPPED := V_SKIPPED + 1;
            INSERT INTO GOVERNANCE.CONTROL.COMPLIANCE_FINDING
                (SCAN_ID, SCAN_AT, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
                 OBJECT_TYPE, TAG_NAME, FINDING_TYPE, SEVERITY, DETAIL)
            SELECT 'RAP-RECONCILE', CURRENT_TIMESTAMP(), rec.OBJECT_DATABASE,
                   rec.OBJECT_SCHEMA, rec.OBJECT_NAME, rec.OBJECT_TYPE,
                   'ROW_ACCESS_REQUIRED', 'POLICY_DRIFT', 'CRITICAL',
                   'Declares ROW_ACCESS_REQUIRED = YES but has no BUSINESS_UNIT ' ||
                   'column, so the standard row access policy cannot bind. The ' ||
                   'table is UNPROTECTED. Either add the dimension column or ' ||
                   'register a bespoke policy in CONTROL.TAG_POLICY_BINDING.';
            CONTINUE;
        END IF;

        V_STMT := 'ALTER ' || REPLACE(rec.OBJECT_TYPE, '_', ' ') || ' ' || V_FQN ||
                  ' ADD ROW ACCESS POLICY GOVERNANCE.POLICIES.RAP_BUSINESS_UNIT_SCOPE' ||
                  ' ON (' || rec.BU_COLUMN || ')';

        IF (NOT P_DRY_RUN) THEN
            EXECUTE IMMEDIATE :V_STMT;
            INSERT INTO GOVERNANCE.CONTROL.TAG_CHANGE_LOG
                (ACTION, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, OBJECT_TYPE,
                 TAG_NAME, NEW_VALUE, CHANGE_REASON, SOURCE)
            SELECT 'SET', rec.OBJECT_DATABASE, rec.OBJECT_SCHEMA, rec.OBJECT_NAME,
                   rec.OBJECT_TYPE, 'ROW_ACCESS_REQUIRED', 'RAP_BUSINESS_UNIT_SCOPE',
                   'Row access policy applied by tag reconciliation.', 'REMEDIATION';
        END IF;
        V_APPLIED := V_APPLIED + 1;
    END FOR;

    RETURN IFF(P_DRY_RUN, 'DRY RUN: ', '') || V_APPLIED ||
           ' row access policies applied, ' || V_SKIPPED ||
           ' tables could not be bound (findings raised).';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR ' || SQLCODE || ': ' || SQLERRM;
END;
$$;

-- =============================================================================
-- SP_RECONCILE_CLASSIFICATION
-- =============================================================================
-- Snowflake's classifier writes SNOWFLAKE.CORE.PRIVACY_CATEGORY and
-- SEMANTIC_CATEGORY. Those are the machine's opinion, and they are good but not
-- accountable: no regulator accepts "the classifier said so" as the basis for a
-- privacy decision.
--
-- So the framework treats classifier output as a PROPOSAL:
--   * classifier says IDENTIFIER/QUASI_IDENTIFIER, no human decision yet
--         -> set PII = YES automatically, state AUTO_APPLIED, notify the steward
--   * classifier and the enterprise tag agree      -> AGREED, no action
--   * they disagree and a human set the tag        -> HUMAN_OVERRIDE, needs a
--         recorded reason, and is surfaced for review rather than overwritten
--
-- The last case is the important one. A framework that lets the classifier
-- overwrite a considered human decision every night trains people to stop
-- making considered decisions.
CREATE OR REPLACE PROCEDURE SP_RECONCILE_CLASSIFICATION(P_AUTO_APPLY BOOLEAN)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Reconciles Snowflake auto-classification output with the enterprise PII tag.'
AS
$$
DECLARE
    V_APPLIED  NUMBER := 0;
    V_CONFLICT NUMBER := 0;
    V_RESULT   STRING;
    C_PROPOSED CURSOR FOR
        SELECT OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, COLUMN_NAME
        FROM GOVERNANCE.CONTROL.CLASSIFICATION_RECONCILIATION
        WHERE RECONCILIATION_STATE = 'UNREVIEWED'
          AND PRIVACY_CATEGORY IN ('IDENTIFIER', 'QUASI_IDENTIFIER', 'SENSITIVE')
          AND COALESCE(ENTERPRISE_PII, 'UNSET') <> 'YES';
BEGIN
    -- 1. Refresh the reconciliation table from the classifier's system tags.
    MERGE INTO GOVERNANCE.CONTROL.CLASSIFICATION_RECONCILIATION t
    USING (
        SELECT
            c.OBJECT_DATABASE, c.OBJECT_SCHEMA, c.OBJECT_NAME, c.COLUMN_NAME,
            MAX(IFF(c.TAG_NAME = 'SEMANTIC_CATEGORY', c.TAG_VALUE, NULL)) AS SEMANTIC_CATEGORY,
            MAX(IFF(c.TAG_NAME = 'PRIVACY_CATEGORY',  c.TAG_VALUE, NULL)) AS PRIVACY_CATEGORY,
            MAX(e.EFFECTIVE_VALUE)                                        AS ENTERPRISE_PII
        FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES c
        LEFT JOIN GOVERNANCE.REPORTING.VW_EFFECTIVE_TAG e
          ON  e.OBJECT_DATABASE = c.OBJECT_DATABASE
          AND e.OBJECT_SCHEMA   = c.OBJECT_SCHEMA
          AND e.OBJECT_NAME     = c.OBJECT_NAME
          AND e.COLUMN_NAME     = c.COLUMN_NAME
          AND e.TAG_NAME        = 'PII'
        WHERE c.TAG_DATABASE = 'SNOWFLAKE'
          AND c.TAG_SCHEMA   = 'CORE'
          AND c.TAG_NAME IN ('SEMANTIC_CATEGORY', 'PRIVACY_CATEGORY')
          AND c.COLUMN_NAME IS NOT NULL
          AND c.OBJECT_DELETED IS NULL
        GROUP BY 1, 2, 3, 4
    ) s
    ON  t.OBJECT_DATABASE = s.OBJECT_DATABASE
    AND t.OBJECT_SCHEMA   = s.OBJECT_SCHEMA
    AND t.OBJECT_NAME     = s.OBJECT_NAME
    AND t.COLUMN_NAME     = s.COLUMN_NAME
    WHEN MATCHED THEN UPDATE SET
        t.SEMANTIC_CATEGORY = s.SEMANTIC_CATEGORY,
        t.PRIVACY_CATEGORY  = s.PRIVACY_CATEGORY,
        t.ENTERPRISE_PII    = s.ENTERPRISE_PII,
        t.LAST_CLASSIFIED_AT = CURRENT_TIMESTAMP(),
        -- A human decision is never demoted back to UNREVIEWED by a re-scan.
        t.RECONCILIATION_STATE = CASE
            WHEN t.RECONCILIATION_STATE = 'HUMAN_OVERRIDE' THEN 'HUMAN_OVERRIDE'
            WHEN s.ENTERPRISE_PII = 'YES' THEN 'AGREED'
            ELSE t.RECONCILIATION_STATE
        END
    WHEN NOT MATCHED THEN INSERT
        (OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, COLUMN_NAME,
         SEMANTIC_CATEGORY, PRIVACY_CATEGORY, ENTERPRISE_PII, RECONCILIATION_STATE)
    VALUES
        (s.OBJECT_DATABASE, s.OBJECT_SCHEMA, s.OBJECT_NAME, s.COLUMN_NAME,
         s.SEMANTIC_CATEGORY, s.PRIVACY_CATEGORY, s.ENTERPRISE_PII,
         IFF(s.ENTERPRISE_PII = 'YES', 'AGREED', 'UNREVIEWED'));

    -- 2. Apply the classifier's proposal where no human has ruled.
    IF (P_AUTO_APPLY) THEN
        FOR rec IN C_PROPOSED DO
            V_RESULT := (CALL SP_APPLY_TAG(
                'COLUMN',
                rec.OBJECT_DATABASE || '.' || rec.OBJECT_SCHEMA || '.' || rec.OBJECT_NAME,
                rec.COLUMN_NAME,
                'PII', 'YES',
                'Auto-applied from Snowflake classification (privacy category).',
                NULL, 'AUTO_CLASSIFY'));

            IF (STARTSWITH(V_RESULT, 'OK')) THEN
                V_APPLIED := V_APPLIED + 1;
                UPDATE GOVERNANCE.CONTROL.CLASSIFICATION_RECONCILIATION
                   SET RECONCILIATION_STATE = 'AUTO_APPLIED', ENTERPRISE_PII = 'YES'
                 WHERE OBJECT_DATABASE = rec.OBJECT_DATABASE
                   AND OBJECT_SCHEMA   = rec.OBJECT_SCHEMA
                   AND OBJECT_NAME     = rec.OBJECT_NAME
                   AND COLUMN_NAME     = rec.COLUMN_NAME;
            END IF;
        END FOR;
    END IF;

    -- 3. Surface disagreements. Never overwrite them.
    SELECT COUNT(*) INTO :V_CONFLICT
      FROM GOVERNANCE.CONTROL.CLASSIFICATION_RECONCILIATION
     WHERE PRIVACY_CATEGORY IN ('IDENTIFIER', 'QUASI_IDENTIFIER', 'SENSITIVE')
       AND ENTERPRISE_PII = 'NO'
       AND RECONCILIATION_STATE = 'HUMAN_OVERRIDE'
       AND OVERRIDE_REASON IS NULL;

    RETURN V_APPLIED || ' columns auto-tagged as PII; ' || V_CONFLICT ||
           ' human overrides lack a recorded reason and need steward review.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR ' || SQLCODE || ': ' || SQLERRM;
END;
$$;

-- =============================================================================
-- SP_DETECT_POLICY_DRIFT
-- =============================================================================
-- The control that catches the failure mode nobody plans for: someone with
-- sufficient privilege detaches a masking policy from a tag, or drops the policy
-- and recreates it without reattaching. Tags stay green, the compliance report
-- stays green, and the data is in clear.
CREATE OR REPLACE PROCEDURE SP_DETECT_POLICY_DRIFT()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Compares declared tag/policy bindings against the account''s actual policy references.'
AS
$$
DECLARE
    V_DRIFT NUMBER;
BEGIN
    INSERT INTO GOVERNANCE.CONTROL.COMPLIANCE_FINDING
        (SCAN_ID, SCAN_AT, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
         OBJECT_TYPE, TAG_NAME, FINDING_TYPE, SEVERITY, DETAIL,
         EXPECTED_VALUE, OBSERVED_VALUE)
    SELECT
        'POLICY-DRIFT', CURRENT_TIMESTAMP(), 'GOVERNANCE', 'TAGS', b.TAG_NAME,
        'TAG', b.TAG_NAME, 'POLICY_DRIFT', 'CRITICAL',
        'Declared ' || b.POLICY_KIND || ' policy ' || b.POLICY_NAME ||
            ' is no longer attached to tag ' || b.TAG_NAME ||
            COALESCE(' for data type ' || b.DATA_TYPE, '') ||
            '. Every column relying on this tag is currently unprotected.',
        b.POLICY_NAME, 'DETACHED'
    FROM GOVERNANCE.CONTROL.TAG_POLICY_BINDING b
    LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES pr
      ON  pr.TAG_NAME    = b.TAG_NAME
      AND pr.POLICY_NAME = SPLIT_PART(b.POLICY_NAME, '.', 3)
    WHERE b.IS_ACTIVE
      AND b.ATTACH_MODE = 'TAG_ATTACHED'
      AND pr.POLICY_NAME IS NULL;

    SELECT COUNT(*) INTO :V_DRIFT
      FROM GOVERNANCE.CONTROL.COMPLIANCE_FINDING
     WHERE SCAN_ID = 'POLICY-DRIFT' AND STATUS = 'OPEN';

    RETURN V_DRIFT || ' detached policy bindings detected.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR ' || SQLCODE || ': ' || SQLERRM;
END;
$$;

SELECT 'Reconciliation procedures ready' AS status;
