-- =============================================================================
-- 40_procedures/00_apply_tag.sql
-- SP_APPLY_TAG - the only supported way to assign an enterprise tag.
-- -----------------------------------------------------------------------------
-- WHY A PROCEDURE AND NOT A GRANT
-- -------------------------------
-- Snowflake's APPLY TAG privilege is account-scoped: it cannot be limited to a
-- database, a schema or a domain. Granting it to every steward in a global
-- enterprise means every steward can retag every object in the account,
-- including someone else's HIGHLY_RESTRICTED columns.
--
-- So APPLY TAG is granted to exactly one role, TAG_ADMIN, and this owner's-rights
-- procedure lends that privilege out under conditions:
--   * the tag exists, is ACTIVE and is legal on that object type
--   * the value is legal (vocabulary, reference data or format)
--   * the assignment does not breach the tag's override rule
--   * the caller's role owns that part of the namespace
-- and every accepted change is written to CONTROL.TAG_CHANGE_LOG with a reason.
--
-- Callers get scoped delegation, auditors get intent, and the estate keeps one
-- enforcement path instead of thousands of ad-hoc ALTER statements.
--
-- Run as: TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA AUTOMATION;

CREATE OR REPLACE PROCEDURE SP_APPLY_TAG(
    P_OBJECT_TYPE   STRING,   -- TABLE, VIEW, SCHEMA, DATABASE, COLUMN, WAREHOUSE, ...
    P_OBJECT_FQN    STRING,   -- fully qualified object name; for COLUMN, the TABLE fqn
    P_COLUMN_NAME   STRING,   -- NULL unless P_OBJECT_TYPE = 'COLUMN'
    P_TAG_NAME      STRING,
    P_TAG_VALUE     STRING,   -- NULL to UNSET the tag
    P_CHANGE_REASON STRING,
    P_CHANGE_TICKET STRING,
    P_SOURCE        STRING    -- MANUAL | CICD | AUTO_CLASSIFY | REMEDIATION | BACKFILL
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'Validated, audited tag assignment. The only sanctioned way to set an enterprise tag.'
AS
$$
DECLARE
    V_CALLER          STRING;
    V_TAG_FQN         STRING;
    V_VALUE_SOURCE    STRING;
    V_REFERENCE_SET   STRING;
    V_FORMAT_REGEX    STRING;
    V_OVERRIDE_RULE   STRING;
    V_STATUS          STRING;
    V_REQ_LEVEL       STRING;
    V_OLD_VALUE       STRING;
    V_PARENT_VALUE    STRING;
    V_NEW_ORDINAL     NUMBER;
    V_PARENT_ORDINAL  NUMBER;
    V_DB              STRING;
    V_SCHEMA          STRING;
    V_NAME            STRING;
    V_OBJECT_KEYWORD  STRING;
    V_STMT            STRING;
    V_OWNED           NUMBER;
    V_ACTION          STRING;
BEGIN
    V_CALLER  := COALESCE(INVOKER_ROLE(), CURRENT_ROLE());
    V_TAG_FQN := 'GOVERNANCE.TAGS.' || UPPER(:P_TAG_NAME);
    V_ACTION  := IFF(:P_TAG_VALUE IS NULL, 'UNSET', 'SET');

    IF (:P_CHANGE_REASON IS NULL OR TRIM(:P_CHANGE_REASON) = '') THEN
        RETURN 'REJECTED: a change reason is mandatory. An untraceable tag change ' ||
               'is indistinguishable from an unauthorised one.';
    END IF;

    -- ---------------------------------------------------------------------
    -- 1. Split the FQN. Everything downstream needs the three parts.
    -- ---------------------------------------------------------------------
    V_DB     := UPPER(SPLIT_PART(:P_OBJECT_FQN, '.', 1));
    V_SCHEMA := UPPER(SPLIT_PART(:P_OBJECT_FQN, '.', 2));
    V_NAME   := UPPER(SPLIT_PART(:P_OBJECT_FQN, '.', 3));

    IF (UPPER(:P_OBJECT_TYPE) = 'COLUMN' AND
        (:P_COLUMN_NAME IS NULL OR TRIM(:P_COLUMN_NAME) = '')) THEN
        RETURN 'REJECTED: P_COLUMN_NAME is required when P_OBJECT_TYPE is COLUMN.';
    END IF;

    -- ---------------------------------------------------------------------
    -- 2. The tag must exist in the registry and still be in service.
    --    A tag that exists in Snowflake but not in the registry is a shadow
    --    tag: refusing it here is what keeps the taxonomy closed.
    -- ---------------------------------------------------------------------
    SELECT VALUE_SOURCE, REFERENCE_SET, VALUE_FORMAT_REGEX, OVERRIDE_RULE, STATUS
      INTO :V_VALUE_SOURCE, :V_REFERENCE_SET, :V_FORMAT_REGEX, :V_OVERRIDE_RULE, :V_STATUS
      FROM GOVERNANCE.CONTROL.TAG_CATALOG
     WHERE TAG_NAME = UPPER(:P_TAG_NAME);

    IF (V_VALUE_SOURCE IS NULL) THEN
        RETURN 'REJECTED: ' || :P_TAG_NAME || ' is not a registered enterprise tag.';
    END IF;
    IF (V_STATUS = 'RETIRED') THEN
        RETURN 'REJECTED: ' || :P_TAG_NAME || ' is RETIRED and can no longer be assigned.';
    END IF;
    IF (V_STATUS = 'DEPRECATED' AND V_ACTION = 'SET') THEN
        -- Deprecated tags may still be removed, never newly applied.
        RETURN 'REJECTED: ' || :P_TAG_NAME || ' is DEPRECATED. Use its replacement; ' ||
               'UNSET is still permitted during migration.';
    END IF;

    -- ---------------------------------------------------------------------
    -- 3. The tag must be legal on this object type.
    -- ---------------------------------------------------------------------
    SELECT REQUIREMENT_LEVEL INTO :V_REQ_LEVEL
      FROM GOVERNANCE.CONTROL.TAG_REQUIREMENT
     WHERE TAG_NAME = UPPER(:P_TAG_NAME)
       AND OBJECT_TYPE = UPPER(:P_OBJECT_TYPE);

    IF (V_REQ_LEVEL IS NULL OR V_REQ_LEVEL = 'NOT_APPLICABLE') THEN
        RETURN 'REJECTED: ' || :P_TAG_NAME || ' does not apply to ' ||
               UPPER(:P_OBJECT_TYPE) || '. Applying it there would create metadata ' ||
               'no consumer reads.';
    END IF;

    -- ---------------------------------------------------------------------
    -- 4. Namespace ownership. APPLY TAG cannot be scoped by grant, so it is
    --    scoped here instead.
    -- ---------------------------------------------------------------------
    IF (V_CALLER <> 'TAG_ADMIN' AND V_CALLER <> 'ACCOUNTADMIN') THEN
        SELECT COUNT(*) INTO :V_OWNED
          FROM GOVERNANCE.CONTROL.DOMAIN_OWNERSHIP
         WHERE IS_ACTIVE
           AND STEWARD_ROLE = :V_CALLER
           AND :V_DB ILIKE DATABASE_PATTERN
           AND COALESCE(:V_SCHEMA, '') ILIKE SCHEMA_PATTERN;

        IF (V_OWNED = 0) THEN
            RETURN 'REJECTED: role ' || V_CALLER || ' is not a registered steward for ' ||
                   :P_OBJECT_FQN || '. Register the ownership in ' ||
                   'CONTROL.DOMAIN_OWNERSHIP or ask the owning domain to make the change.';
        END IF;
    END IF;

    -- ---------------------------------------------------------------------
    -- 5. Value validation.
    --    Snowflake enforces ALLOWED_VALUES itself, but reference data and free
    --    text have no server-side enforcement at all - without this block those
    --    tags accept literally anything, which is how "CC-1234", "cc1234" and
    --    "1234" end up as three cost centres in the chargeback report.
    -- ---------------------------------------------------------------------
    IF (V_ACTION = 'SET') THEN
        IF (V_VALUE_SOURCE = 'controlled_vocabulary') THEN
            LET V_OK NUMBER := (
                SELECT COUNT(*) FROM GOVERNANCE.CONTROL.TAG_ALLOWED_VALUE
                 WHERE TAG_NAME = UPPER(:P_TAG_NAME)
                   AND TAG_VALUE = :P_TAG_VALUE AND IS_ACTIVE);
            IF (V_OK = 0) THEN
                RETURN 'REJECTED: "' || :P_TAG_VALUE || '" is not an allowed value of ' ||
                       :P_TAG_NAME || '.';
            END IF;

        ELSEIF (V_VALUE_SOURCE = 'reference_data') THEN
            LET V_OK NUMBER := (
                SELECT COUNT(*) FROM GOVERNANCE.CONTROL.REFERENCE_VALUE
                 WHERE REFERENCE_SET = :V_REFERENCE_SET
                   AND VALUE_CODE = :P_TAG_VALUE
                   AND IS_ACTIVE
                   AND CURRENT_DATE() BETWEEN VALID_FROM
                                          AND COALESCE(VALID_TO, '9999-12-31'::DATE));
            IF (V_OK = 0) THEN
                RETURN 'REJECTED: "' || :P_TAG_VALUE || '" is not an active value in ' ||
                       :V_REFERENCE_SET || '.';
            END IF;

        ELSEIF (V_FORMAT_REGEX IS NOT NULL) THEN
            IF (NOT RLIKE(:P_TAG_VALUE, :V_FORMAT_REGEX)) THEN
                RETURN 'REJECTED: "' || :P_TAG_VALUE || '" does not match the required ' ||
                       'format for ' || :P_TAG_NAME || ' (' || :V_FORMAT_REGEX || ').';
            END IF;
        END IF;
    END IF;

    -- ---------------------------------------------------------------------
    -- 6. Override rules against the inherited value.
    --    Reading the parent directly with SYSTEM$GET_TAG is deliberate: it is
    --    immediate, whereas ACCOUNT_USAGE.TAG_REFERENCES lags by up to two
    --    hours and would let a downgrade slip through in that window.
    -- ---------------------------------------------------------------------
    IF (V_ACTION = 'SET' AND V_OVERRIDE_RULE <> 'any') THEN
        IF (UPPER(:P_OBJECT_TYPE) IN ('COLUMN', 'TABLE', 'VIEW', 'MATERIALIZED_VIEW',
                                      'DYNAMIC_TABLE', 'EXTERNAL_TABLE', 'ICEBERG_TABLE')) THEN
            V_PARENT_VALUE := SYSTEM$GET_TAG(:V_TAG_FQN, :V_DB || '.' || :V_SCHEMA, 'SCHEMA');
        ELSEIF (UPPER(:P_OBJECT_TYPE) = 'SCHEMA') THEN
            V_PARENT_VALUE := SYSTEM$GET_TAG(:V_TAG_FQN, :V_DB, 'DATABASE');
        ELSE
            V_PARENT_VALUE := NULL;
        END IF;

        IF (V_PARENT_VALUE IS NOT NULL AND V_PARENT_VALUE <> :P_TAG_VALUE) THEN
            IF (V_OVERRIDE_RULE = 'none') THEN
                RETURN 'REJECTED: ' || :P_TAG_NAME || ' is inherited as "' ||
                       V_PARENT_VALUE || '" and may not be overridden on this object.';
            END IF;

            IF (V_OVERRIDE_RULE = 'more_restrictive_only') THEN
                SELECT ORDINAL_POSITION INTO :V_NEW_ORDINAL
                  FROM GOVERNANCE.CONTROL.TAG_ALLOWED_VALUE
                 WHERE TAG_NAME = UPPER(:P_TAG_NAME) AND TAG_VALUE = :P_TAG_VALUE;

                SELECT ORDINAL_POSITION INTO :V_PARENT_ORDINAL
                  FROM GOVERNANCE.CONTROL.TAG_ALLOWED_VALUE
                 WHERE TAG_NAME = UPPER(:P_TAG_NAME) AND TAG_VALUE = :V_PARENT_VALUE;

                IF (V_NEW_ORDINAL < V_PARENT_ORDINAL) THEN
                    RETURN 'REJECTED: cannot weaken ' || :P_TAG_NAME || ' from inherited "' ||
                           V_PARENT_VALUE || '" to "' || :P_TAG_VALUE || '". A child object ' ||
                           'may only be equally or more restrictive than its parent. ' ||
                           'Raise a time-boxed exception in CONTROL.TAG_EXCEPTION if this ' ||
                           'is genuinely required.';
                END IF;
            END IF;
        END IF;
    END IF;

    -- ---------------------------------------------------------------------
    -- 7. Capture the prior value for the audit trail, then apply.
    -- ---------------------------------------------------------------------
    IF (UPPER(:P_OBJECT_TYPE) = 'COLUMN') THEN
        V_OLD_VALUE := SYSTEM$GET_TAG(:V_TAG_FQN,
                                      :P_OBJECT_FQN || '.' || :P_COLUMN_NAME, 'COLUMN');
        V_STMT := 'ALTER TABLE ' || :P_OBJECT_FQN ||
                  ' MODIFY COLUMN ' || :P_COLUMN_NAME || ' ' || V_ACTION || ' TAG ' ||
                  V_TAG_FQN || IFF(V_ACTION = 'SET', ' = ?', '');
    ELSE
        -- MATERIALIZED_VIEW -> 'MATERIALIZED VIEW', ICEBERG_TABLE -> 'ICEBERG TABLE', ...
        V_OBJECT_KEYWORD := REPLACE(UPPER(:P_OBJECT_TYPE), '_', ' ');
        V_OLD_VALUE := SYSTEM$GET_TAG(:V_TAG_FQN, :P_OBJECT_FQN, UPPER(:P_OBJECT_TYPE));
        V_STMT := 'ALTER ' || V_OBJECT_KEYWORD || ' ' || :P_OBJECT_FQN || ' ' ||
                  V_ACTION || ' TAG ' || V_TAG_FQN || IFF(V_ACTION = 'SET', ' = ?', '');
    END IF;

    IF (V_OLD_VALUE = :P_TAG_VALUE) THEN
        RETURN 'NO-OP: ' || :P_TAG_NAME || ' is already "' || :P_TAG_VALUE || '".';
    END IF;

    -- Bind the value rather than concatenating it: a tag value is user-supplied
    -- text and must never be interpolated into DDL.
    IF (V_ACTION = 'SET') THEN
        EXECUTE IMMEDIATE :V_STMT USING (P_TAG_VALUE);
    ELSE
        EXECUTE IMMEDIATE :V_STMT;
    END IF;

    -- ---------------------------------------------------------------------
    -- 8. Audit.
    -- ---------------------------------------------------------------------
    INSERT INTO GOVERNANCE.CONTROL.TAG_CHANGE_LOG
        (CHANGED_BY, CHANGED_BY_ROLE, ACTION, OBJECT_DATABASE, OBJECT_SCHEMA,
         OBJECT_NAME, OBJECT_TYPE, COLUMN_NAME, TAG_NAME, OLD_VALUE, NEW_VALUE,
         CHANGE_REASON, CHANGE_TICKET, SOURCE)
    SELECT CURRENT_USER(), :V_CALLER, :V_ACTION, :V_DB, :V_SCHEMA, :V_NAME,
           UPPER(:P_OBJECT_TYPE), :P_COLUMN_NAME, UPPER(:P_TAG_NAME),
           :V_OLD_VALUE, :P_TAG_VALUE, :P_CHANGE_REASON, :P_CHANGE_TICKET,
           COALESCE(UPPER(:P_SOURCE), 'MANUAL');

    RETURN 'OK: ' || V_ACTION || ' ' || :P_TAG_NAME ||
           IFF(V_ACTION = 'SET', ' = "' || :P_TAG_VALUE || '"', '') ||
           ' on ' || UPPER(:P_OBJECT_TYPE) || ' ' || :P_OBJECT_FQN ||
           COALESCE('.' || :P_COLUMN_NAME, '') ||
           IFF(V_OLD_VALUE IS NULL, '', ' (was "' || V_OLD_VALUE || '")');

EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR ' || SQLCODE || ': ' || SQLERRM;
END;
$$;

-- Stewards call the procedure; they never hold APPLY TAG themselves.
GRANT USAGE ON PROCEDURE SP_APPLY_TAG(STRING, STRING, STRING, STRING, STRING, STRING, STRING, STRING)
    TO ROLE TAG_STEWARD;

SELECT 'SP_APPLY_TAG ready' AS status;
