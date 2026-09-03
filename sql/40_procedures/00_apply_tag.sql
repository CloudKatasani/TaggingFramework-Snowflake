-- =============================================================================
-- 40_procedures/00_apply_tag.sql
-- SP_APPLY_TAG - the only supported way to assign an enterprise tag.
-- -----------------------------------------------------------------------------
-- WHY A PROCEDURE AND NOT A GRANT
-- -------------------------------
-- Snowflake's APPLY TAG privilege is account-scoped: it cannot be limited to a
-- database, a schema or a domain. Granting it to every steward in a global
-- enterprise means every steward can retag every object in the account,
-- including someone else's RESTRICTED columns.
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
    -- Existence is checked with a scalar subquery before the SELECT ... INTO:
    -- a SELECT ... INTO that matches no rows is not a dependable way to observe
    -- absence, and the whole guard would be skipped.
    LET V_REGISTERED NUMBER := (
        SELECT COUNT(*) FROM GOVERNANCE.CONTROL.TAG_CATALOG
         WHERE TAG_NAME = UPPER(:P_TAG_NAME));

    IF (V_REGISTERED = 0) THEN
        RETURN 'REJECTED: ' || :P_TAG_NAME || ' is not a registered enterprise tag.';
    END IF;

    SELECT VALUE_SOURCE, REFERENCE_SET, VALUE_FORMAT_REGEX, OVERRIDE_RULE, STATUS
      INTO :V_VALUE_SOURCE, :V_REFERENCE_SET, :V_FORMAT_REGEX, :V_OVERRIDE_RULE, :V_STATUS
      FROM GOVERNANCE.CONTROL.TAG_CATALOG
     WHERE TAG_NAME = UPPER(:P_TAG_NAME);
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
    V_REQ_LEVEL := (
        SELECT MAX(REQUIREMENT_LEVEL) FROM GOVERNANCE.CONTROL.TAG_REQUIREMENT
         WHERE TAG_NAME = UPPER(:P_TAG_NAME)
           AND OBJECT_TYPE = UPPER(:P_OBJECT_TYPE));

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
                V_NEW_ORDINAL := (
                    SELECT MAX(ORDINAL_POSITION)
                      FROM GOVERNANCE.CONTROL.TAG_ALLOWED_VALUE
                     WHERE TAG_NAME = UPPER(:P_TAG_NAME)
                       AND TAG_VALUE = :P_TAG_VALUE);

                V_PARENT_ORDINAL := (
                    SELECT MAX(ORDINAL_POSITION)
                      FROM GOVERNANCE.CONTROL.TAG_ALLOWED_VALUE
                     WHERE TAG_NAME = UPPER(:P_TAG_NAME)
                       AND TAG_VALUE = :V_PARENT_VALUE);

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
    -- 7. Injection guard.
    --
    --    Snowflake does not accept bind variables in DDL, so the tag value has
    --    to be interpolated into an ALTER statement. Every value reaching this
    --    point has already passed step 5 - an allow-list, a reference-data
    --    lookup, or an anchored regex - and all shipped regexes exclude quotes.
    --    This block is the belt to that braces: it defends against a future
    --    free_text tag being added with a loose pattern, which is exactly the
    --    kind of change that looks harmless in review.
    -- ---------------------------------------------------------------------
    IF (V_ACTION = 'SET') THEN
        IF (CONTAINS(:P_TAG_VALUE, '''') OR CONTAINS(:P_TAG_VALUE, ';')
            OR CONTAINS(:P_TAG_VALUE, '--') OR LENGTH(:P_TAG_VALUE) > 256) THEN
            RETURN 'REJECTED: tag value contains a quote, a semicolon or a comment ' ||
                   'marker, or exceeds the 256-character Snowflake limit. ' ||
                   'Tighten the value_format for ' || :P_TAG_NAME || '.';
        END IF;
    END IF;

    -- ---------------------------------------------------------------------
    -- 8. Capture the prior value for the audit trail, then apply.
    -- ---------------------------------------------------------------------
    -- SYSTEM$GET_TAG takes the object DOMAIN, which uses spaces rather than
    -- underscores: MATERIALIZED_VIEW -> 'MATERIALIZED VIEW'.
    V_OBJECT_KEYWORD := REPLACE(UPPER(:P_OBJECT_TYPE), '_', ' ');

    IF (UPPER(:P_OBJECT_TYPE) = 'COLUMN') THEN
        V_OLD_VALUE := SYSTEM$GET_TAG(:V_TAG_FQN,
                                      :P_OBJECT_FQN || '.' || :P_COLUMN_NAME, 'COLUMN');
        V_STMT := 'ALTER TABLE ' || :P_OBJECT_FQN ||
                  ' MODIFY COLUMN ' || :P_COLUMN_NAME || ' ' || V_ACTION || ' TAG ' ||
                  V_TAG_FQN || IFF(V_ACTION = 'SET', ' = ''' || :P_TAG_VALUE || '''', '');
    ELSE
        V_OLD_VALUE := SYSTEM$GET_TAG(:V_TAG_FQN, :P_OBJECT_FQN, :V_OBJECT_KEYWORD);
        V_STMT := 'ALTER ' || V_OBJECT_KEYWORD || ' ' || :P_OBJECT_FQN || ' ' ||
                  V_ACTION || ' TAG ' || V_TAG_FQN ||
                  IFF(V_ACTION = 'SET', ' = ''' || :P_TAG_VALUE || '''', '');
    END IF;

    IF (V_OLD_VALUE = :P_TAG_VALUE) THEN
        RETURN 'NO-OP: ' || :P_TAG_NAME || ' is already "' || :P_TAG_VALUE || '".';
    END IF;

    EXECUTE IMMEDIATE :V_STMT;

    -- ---------------------------------------------------------------------
    -- 9. Audit.
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
