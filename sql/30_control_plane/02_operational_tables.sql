-- =============================================================================
-- 30_control_plane/02_operational_tables.sql
-- Operational control tables: exceptions, findings, audit trail, entitlements.
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA CONTROL;

-- -----------------------------------------------------------------------------
-- REGULATORY_SCOPE - the multi-valued companion to the REGULATION tag
-- -----------------------------------------------------------------------------
-- A Snowflake tag holds exactly one value per object. Real objects are often in
-- scope for several regimes at once (a payments table can be PCI-DSS, SOX and
-- GDPR simultaneously). Rather than minting a boolean tag per regime - which is
-- how tag estates reach four hundred tags - the tag carries the GOVERNING regime
-- (or MULTI) and this table carries the full truth.
CREATE TABLE IF NOT EXISTS REGULATORY_SCOPE (
    OBJECT_DATABASE  STRING NOT NULL,
    OBJECT_SCHEMA    STRING NOT NULL,
    OBJECT_NAME      STRING NOT NULL,
    OBJECT_TYPE      STRING NOT NULL,
    COLUMN_NAME      STRING,                -- NULL for object-level scope
    REGULATION       STRING NOT NULL,
    SCOPE_REASON     STRING NOT NULL,
    ASSESSED_BY      STRING NOT NULL,
    ASSESSED_AT      TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    NEXT_REVIEW_DATE DATE,
    IS_ACTIVE        BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT PK_REGULATORY_SCOPE PRIMARY KEY
        (OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, COLUMN_NAME, REGULATION) RELY
)
COMMENT = 'Full multi-regime regulatory scope per object. The REGULATION tag carries only the governing regime.';

-- -----------------------------------------------------------------------------
-- TAG_EXCEPTION - time-boxed, approved deviations
-- -----------------------------------------------------------------------------
-- Every framework meets an object that legitimately cannot comply. Without a
-- formal exception path teams either stall or quietly disable the control. An
-- exception is always time-boxed: EXPIRES_AT is NOT NULL by design.
CREATE TABLE IF NOT EXISTS TAG_EXCEPTION (
    EXCEPTION_ID     STRING NOT NULL DEFAULT UUID_STRING(),
    OBJECT_DATABASE  STRING NOT NULL,
    OBJECT_SCHEMA    STRING,
    OBJECT_NAME      STRING,
    OBJECT_TYPE      STRING NOT NULL,
    COLUMN_NAME      STRING,
    TAG_NAME         STRING NOT NULL,
    EXCEPTION_TYPE   STRING NOT NULL,   -- MISSING_TAG | INVALID_VALUE | POLICY_WAIVER
    JUSTIFICATION    STRING NOT NULL,
    COMPENSATING_CONTROL STRING NOT NULL,
    REQUESTED_BY     STRING NOT NULL,
    APPROVED_BY      STRING NOT NULL,
    RISK_ACCEPTED_BY STRING,            -- required when severity is CRITICAL
    APPROVED_AT      TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    EXPIRES_AT       TIMESTAMP_NTZ NOT NULL,
    STATUS           STRING NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT PK_TAG_EXCEPTION PRIMARY KEY (EXCEPTION_ID) RELY,
    CONSTRAINT CK_EXC_TYPE CHECK (EXCEPTION_TYPE IN
        ('MISSING_TAG', 'INVALID_VALUE', 'POLICY_WAIVER')),
    CONSTRAINT CK_EXC_STATUS CHECK (STATUS IN ('ACTIVE', 'EXPIRED', 'REVOKED'))
)
COMMENT = 'Approved, time-boxed deviations from the tagging standard. Expiry is mandatory - no permanent exceptions.';

-- -----------------------------------------------------------------------------
-- COMPLIANCE_FINDING - output of the validation engine
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS COMPLIANCE_FINDING (
    FINDING_ID       STRING NOT NULL DEFAULT UUID_STRING(),
    SCAN_ID          STRING NOT NULL,
    SCAN_AT          TIMESTAMP_NTZ NOT NULL,
    OBJECT_DATABASE  STRING NOT NULL,
    OBJECT_SCHEMA    STRING,
    OBJECT_NAME      STRING,
    OBJECT_TYPE      STRING NOT NULL,
    COLUMN_NAME      STRING,
    TAG_NAME         STRING,
    RULE_ID          STRING,            -- conditional rule, when applicable
    FINDING_TYPE     STRING NOT NULL,
    SEVERITY         STRING NOT NULL,
    DETAIL           STRING NOT NULL,
    OBSERVED_VALUE   STRING,
    EXPECTED_VALUE   STRING,
    DOMAIN           STRING,            -- denormalised for routing
    DATA_OWNER       STRING,
    DATA_STEWARD     STRING,
    EXCEPTION_ID     STRING,            -- set when a live exception covers it
    STATUS           STRING NOT NULL DEFAULT 'OPEN',
    REMEDIATED_AT    TIMESTAMP_NTZ,
    CONSTRAINT PK_COMPLIANCE_FINDING PRIMARY KEY (FINDING_ID) RELY,
    CONSTRAINT CK_FIND_TYPE CHECK (FINDING_TYPE IN
        ('MISSING_MANDATORY_TAG', 'INVALID_VALUE', 'UNKNOWN_REFERENCE_VALUE',
         'CONDITIONAL_RULE_BREACH', 'CONTRADICTORY_TAGS', 'ILLEGAL_OVERRIDE',
         'POLICY_DRIFT',
         'ORPHAN_TAG', 'STALE_TAG', 'CLASSIFICATION_MISMATCH',
         'EXPIRED_EXCEPTION', 'UNGOVERNED_TAG_NAMESPACE')),
    CONSTRAINT CK_FIND_SEV CHECK (SEVERITY IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT CK_FIND_STATUS CHECK (STATUS IN
        ('OPEN', 'ACKNOWLEDGED', 'EXCEPTED', 'REMEDIATED', 'FALSE_POSITIVE'))
)
COMMENT = 'Findings from SP_VALIDATE_COMPLIANCE. One row per object/tag violation per scan.';

-- -----------------------------------------------------------------------------
-- TAG_CHANGE_LOG - who changed what, when, and why
-- -----------------------------------------------------------------------------
-- ACCOUNT_USAGE.TAG_REFERENCES shows the current state with up to 2 hours of
-- latency and no reason code. Auditors ask "why was this column downgraded from
-- RESTRICTED to INTERNAL on 14 March?". This table answers that.
CREATE TABLE IF NOT EXISTS TAG_CHANGE_LOG (
    CHANGE_ID        STRING NOT NULL DEFAULT UUID_STRING(),
    CHANGED_AT       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CHANGED_BY       STRING NOT NULL DEFAULT CURRENT_USER(),
    CHANGED_BY_ROLE  STRING NOT NULL DEFAULT CURRENT_ROLE(),
    ACTION           STRING NOT NULL,   -- SET | UNSET | ALTER_DEFINITION
    OBJECT_DATABASE  STRING,
    OBJECT_SCHEMA    STRING,
    OBJECT_NAME      STRING,
    OBJECT_TYPE      STRING NOT NULL,
    COLUMN_NAME      STRING,
    TAG_NAME         STRING NOT NULL,
    OLD_VALUE        STRING,
    NEW_VALUE        STRING,
    CHANGE_REASON    STRING NOT NULL,
    CHANGE_TICKET    STRING,
    SOURCE           STRING NOT NULL,   -- MANUAL | CICD | AUTO_CLASSIFY | INHERITANCE | REMEDIATION
    CONSTRAINT PK_TAG_CHANGE_LOG PRIMARY KEY (CHANGE_ID) RELY,
    CONSTRAINT CK_TCL_ACTION CHECK (ACTION IN ('SET', 'UNSET', 'ALTER_DEFINITION')),
    CONSTRAINT CK_TCL_SOURCE CHECK (SOURCE IN
        ('MANUAL', 'CICD', 'AUTO_CLASSIFY', 'INHERITANCE', 'REMEDIATION', 'BACKFILL'))
)
COMMENT = 'Immutable audit trail of every tag assignment change made through the framework.';

-- -----------------------------------------------------------------------------
-- ROW_ACCESS_ENTITLEMENT - the mapping table behind row access policies
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ROW_ACCESS_ENTITLEMENT (
    ROLE_NAME     STRING NOT NULL,
    DIMENSION     STRING NOT NULL,   -- OPERATING_COMPANY | DOMAIN | DATA_RESIDENCY
    DIMENSION_VALUE STRING NOT NULL, -- '*' grants all values of the dimension
    GRANTED_BY    STRING NOT NULL,
    GRANTED_AT    TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    EXPIRES_AT    TIMESTAMP_NTZ,
    IS_ACTIVE     BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT PK_ROW_ACCESS_ENTITLEMENT
        PRIMARY KEY (ROLE_NAME, DIMENSION, DIMENSION_VALUE) RELY
)
COMMENT = 'Role-to-dimension entitlements consumed by row access policies.';

-- -----------------------------------------------------------------------------
-- CLASSIFICATION_RECONCILIATION - Snowflake auto-classification vs enterprise tags
-- -----------------------------------------------------------------------------
-- Snowflake's classifier writes SNOWFLAKE.CORE.SEMANTIC_CATEGORY and
-- PRIVACY_CATEGORY. Those are the machine's opinion. The enterprise PII tag is
-- the accountable human decision. This table is where the two are compared and
-- where a human disagreement is recorded with a reason.
CREATE TABLE IF NOT EXISTS CLASSIFICATION_RECONCILIATION (
    OBJECT_DATABASE     STRING NOT NULL,
    OBJECT_SCHEMA       STRING NOT NULL,
    OBJECT_NAME         STRING NOT NULL,
    COLUMN_NAME         STRING NOT NULL,
    SEMANTIC_CATEGORY   STRING,
    PRIVACY_CATEGORY    STRING,
    CLASSIFIER_CONFIDENCE STRING,
    ENTERPRISE_REGULATORY_CATEGORY STRING,   -- data_classification_regulatory
    RECONCILIATION_STATE STRING NOT NULL, -- AGREED | AUTO_APPLIED | HUMAN_OVERRIDE | UNREVIEWED
    OVERRIDE_REASON     STRING,
    REVIEWED_BY         STRING,
    REVIEWED_AT         TIMESTAMP_NTZ,
    LAST_CLASSIFIED_AT  TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_CLASSIFICATION_RECONCILIATION PRIMARY KEY
        (OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, COLUMN_NAME) RELY,
    CONSTRAINT CK_RECON_STATE CHECK (RECONCILIATION_STATE IN
        ('AGREED', 'AUTO_APPLIED', 'HUMAN_OVERRIDE', 'UNREVIEWED'))
)
COMMENT = 'Reconciliation between Snowflake auto-classification and the accountable enterprise regulatory classification.';

-- -----------------------------------------------------------------------------
-- COMPLIANCE_SCORE_HISTORY - the trend line executives actually look at
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS COMPLIANCE_SCORE_HISTORY (
    SNAPSHOT_DATE    DATE   NOT NULL,
    SCOPE_TYPE       STRING NOT NULL,   -- ACCOUNT | OPERATING_COMPANY | DEPARTMENT | DOMAIN
    SCOPE_VALUE      STRING NOT NULL,
    OBJECTS_IN_SCOPE NUMBER(18,0) NOT NULL,
    OBJECTS_COMPLIANT NUMBER(18,0) NOT NULL,
    TIER1_COVERAGE_PCT NUMBER(5,2) NOT NULL,
    CRITICAL_FINDINGS NUMBER(18,0) NOT NULL,
    HIGH_FINDINGS    NUMBER(18,0) NOT NULL,
    OPEN_EXCEPTIONS  NUMBER(18,0) NOT NULL,
    CONSTRAINT PK_COMPLIANCE_SCORE_HISTORY
        PRIMARY KEY (SNAPSHOT_DATE, SCOPE_TYPE, SCOPE_VALUE) RELY
)
COMMENT = 'Daily governance scorecard snapshot. Drives the maturity model KPIs.';

SELECT 'Operational control tables ready' AS status;
