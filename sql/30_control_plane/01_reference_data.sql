-- =============================================================================
-- 30_control_plane/01_reference_data.sql
-- Reference data for tags whose values are too volatile or too numerous for
-- Snowflake ALLOWED_VALUES.
-- -----------------------------------------------------------------------------
-- Design note
-- -----------
-- A large enterprise has thousands of cost centres and hundreds of applications.
-- Putting those in ALLOWED_VALUES would mean an ALTER TAG (and a change ticket)
-- every time Finance opens a cost centre - and would breach Snowflake's 300
-- allowed-values ceiling. Instead:
--
--   controlled_vocabulary  -> ALLOWED_VALUES, enforced by Snowflake at SET time.
--   reference_data         -> free-form to Snowflake, enforced by SP_APPLY_TAG
--                             and by the nightly SP_VALIDATE_REFERENCE_DATA job.
--
-- One generic table serves every reference set, so onboarding a new
-- reference-data tag requires no DDL - only a load into REFERENCE_VALUE.
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA CONTROL;

CREATE TABLE IF NOT EXISTS REFERENCE_VALUE (
    REFERENCE_SET  STRING       NOT NULL,  -- e.g. REF_COST_CENTER
    VALUE_CODE     STRING       NOT NULL,  -- the literal tag value, e.g. CC-004120
    DISPLAY_NAME   STRING       NOT NULL,
    PARENT_SET     STRING,                 -- hierarchy: REF_SUB_DOMAIN -> REF_DOMAIN
    PARENT_CODE    STRING,
    ATTRIBUTES     VARIANT,                -- set-specific extras (GL account, region, ...)
    IS_ACTIVE      BOOLEAN      NOT NULL DEFAULT TRUE,
    VALID_FROM     DATE         NOT NULL DEFAULT CURRENT_DATE(),
    VALID_TO       DATE,                   -- NULL = open-ended
    SOURCE_SYSTEM  STRING       NOT NULL,  -- ERP, CMDB, HR, MANUAL
    SYNCED_AT      TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_REFERENCE_VALUE PRIMARY KEY (REFERENCE_SET, VALUE_CODE) RELY
)
COMMENT = 'Authoritative values for reference_data tags. Synchronised from the systems of record.';

-- Convenience views. Consumers reference REF_<SET> rather than filtering the
-- generic table, so the physical model can change without breaking callers.
CREATE OR REPLACE VIEW REF_BUSINESS_UNIT COMMENT = 'Active business units.' AS
SELECT VALUE_CODE AS BUSINESS_UNIT, DISPLAY_NAME, ATTRIBUTES, VALID_FROM, VALID_TO
FROM REFERENCE_VALUE
WHERE REFERENCE_SET = 'REF_BUSINESS_UNIT' AND IS_ACTIVE
  AND CURRENT_DATE() BETWEEN VALID_FROM AND COALESCE(VALID_TO, '9999-12-31'::DATE);

CREATE OR REPLACE VIEW REF_DOMAIN COMMENT = 'Active data mesh domains.' AS
SELECT VALUE_CODE AS DOMAIN, DISPLAY_NAME, ATTRIBUTES, VALID_FROM, VALID_TO
FROM REFERENCE_VALUE
WHERE REFERENCE_SET = 'REF_DOMAIN' AND IS_ACTIVE
  AND CURRENT_DATE() BETWEEN VALID_FROM AND COALESCE(VALID_TO, '9999-12-31'::DATE);

CREATE OR REPLACE VIEW REF_SUB_DOMAIN COMMENT = 'Active sub-domains with parent domain.' AS
SELECT VALUE_CODE AS SUB_DOMAIN, PARENT_CODE AS DOMAIN, DISPLAY_NAME, ATTRIBUTES
FROM REFERENCE_VALUE
WHERE REFERENCE_SET = 'REF_SUB_DOMAIN' AND IS_ACTIVE
  AND CURRENT_DATE() BETWEEN VALID_FROM AND COALESCE(VALID_TO, '9999-12-31'::DATE);

CREATE OR REPLACE VIEW REF_DATA_PRODUCT COMMENT = 'Registered data products.' AS
SELECT VALUE_CODE AS DATA_PRODUCT, PARENT_CODE AS DOMAIN, DISPLAY_NAME, ATTRIBUTES
FROM REFERENCE_VALUE
WHERE REFERENCE_SET = 'REF_DATA_PRODUCT' AND IS_ACTIVE
  AND CURRENT_DATE() BETWEEN VALID_FROM AND COALESCE(VALID_TO, '9999-12-31'::DATE);

CREATE OR REPLACE VIEW REF_COST_CENTER COMMENT = 'Open cost centres from the ERP chart of accounts.' AS
SELECT VALUE_CODE AS COST_CENTER, PARENT_CODE AS BUSINESS_UNIT, DISPLAY_NAME,
       ATTRIBUTES:gl_account::STRING AS GL_ACCOUNT, ATTRIBUTES
FROM REFERENCE_VALUE
WHERE REFERENCE_SET = 'REF_COST_CENTER' AND IS_ACTIVE
  AND CURRENT_DATE() BETWEEN VALID_FROM AND COALESCE(VALID_TO, '9999-12-31'::DATE);

CREATE OR REPLACE VIEW REF_SUPPORT_GROUP COMMENT = 'ITSM support queues.' AS
SELECT VALUE_CODE AS SUPPORT_GROUP, DISPLAY_NAME,
       ATTRIBUTES:itsm_queue_id::STRING AS ITSM_QUEUE_ID, ATTRIBUTES
FROM REFERENCE_VALUE
WHERE REFERENCE_SET = 'REF_SUPPORT_GROUP' AND IS_ACTIVE
  AND CURRENT_DATE() BETWEEN VALID_FROM AND COALESCE(VALID_TO, '9999-12-31'::DATE);

CREATE OR REPLACE VIEW REF_APPLICATION COMMENT = 'CMDB application portfolio.' AS
SELECT VALUE_CODE AS APPLICATION, DISPLAY_NAME,
       ATTRIBUTES:owner::STRING AS APPLICATION_OWNER, ATTRIBUTES
FROM REFERENCE_VALUE
WHERE REFERENCE_SET = 'REF_APPLICATION' AND IS_ACTIVE
  AND CURRENT_DATE() BETWEEN VALID_FROM AND COALESCE(VALID_TO, '9999-12-31'::DATE);

CREATE OR REPLACE VIEW REF_PROJECT COMMENT = 'Active projects and programmes.' AS
SELECT VALUE_CODE AS PROJECT_CODE, PARENT_CODE AS PROGRAM, DISPLAY_NAME, ATTRIBUTES
FROM REFERENCE_VALUE
WHERE REFERENCE_SET = 'REF_PROJECT' AND IS_ACTIVE
  AND CURRENT_DATE() BETWEEN VALID_FROM AND COALESCE(VALID_TO, '9999-12-31'::DATE);

CREATE OR REPLACE VIEW REF_CAPABILITY COMMENT = 'Enterprise business capability model (L2).' AS
SELECT VALUE_CODE AS CAPABILITY, PARENT_CODE AS PARENT_CAPABILITY, DISPLAY_NAME, ATTRIBUTES
FROM REFERENCE_VALUE
WHERE REFERENCE_SET = 'REF_CAPABILITY' AND IS_ACTIVE
  AND CURRENT_DATE() BETWEEN VALID_FROM AND COALESCE(VALID_TO, '9999-12-31'::DATE);

CREATE OR REPLACE VIEW REF_PRODUCT COMMENT = 'Commercial product / SKU master.' AS
SELECT VALUE_CODE AS PRODUCT_CODE, DISPLAY_NAME, ATTRIBUTES
FROM REFERENCE_VALUE
WHERE REFERENCE_SET = 'REF_PRODUCT' AND IS_ACTIVE
  AND CURRENT_DATE() BETWEEN VALID_FROM AND COALESCE(VALID_TO, '9999-12-31'::DATE);

-- -----------------------------------------------------------------------------
-- DOMAIN_OWNERSHIP - which steward may tag which part of the account
-- -----------------------------------------------------------------------------
-- APPLY TAG is account-wide and cannot be scoped by grant. This table is how the
-- framework scopes it in practice: SP_APPLY_TAG refuses to act outside the
-- caller's registered ownership.
CREATE TABLE IF NOT EXISTS DOMAIN_OWNERSHIP (
    DOMAIN            STRING NOT NULL,
    DATABASE_PATTERN  STRING NOT NULL,   -- ILIKE pattern, e.g. 'CUSTOMER_%'
    SCHEMA_PATTERN    STRING NOT NULL DEFAULT '%',
    STEWARD_ROLE      STRING NOT NULL,   -- e.g. TAG_STEWARD_CUSTOMER
    DOMAIN_OWNER      STRING NOT NULL,
    IS_ACTIVE         BOOLEAN NOT NULL DEFAULT TRUE,
    CREATED_AT        TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_DOMAIN_OWNERSHIP
        PRIMARY KEY (DOMAIN, DATABASE_PATTERN, SCHEMA_PATTERN) RELY
)
COMMENT = 'Maps domains to the object namespaces their stewards may tag. Enforced by SP_APPLY_TAG.';

-- -----------------------------------------------------------------------------
-- DOMAIN_TAG_POLICY - domains raising the enterprise minimum
-- -----------------------------------------------------------------------------
-- Federated governance: a domain may make a Tier 2/3 tag mandatory for itself.
-- It may never make an enterprise-mandatory tag optional - SP_VALIDATE_COMPLIANCE
-- takes the stricter of the two.
CREATE TABLE IF NOT EXISTS DOMAIN_TAG_POLICY (
    DOMAIN            STRING NOT NULL,
    TAG_NAME          STRING NOT NULL,
    OBJECT_TYPE       STRING NOT NULL,
    REQUIREMENT_LEVEL STRING NOT NULL,
    RATIONALE         STRING NOT NULL,
    APPROVED_BY       STRING NOT NULL,
    APPROVED_AT       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    IS_ACTIVE         BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT PK_DOMAIN_TAG_POLICY PRIMARY KEY (DOMAIN, TAG_NAME, OBJECT_TYPE) RELY,
    CONSTRAINT CK_DTP_LEVEL CHECK (REQUIREMENT_LEVEL IN ('MANDATORY', 'RECOMMENDED'))
)
COMMENT = 'Domain-local strengthening of the enterprise tag requirements. Can only tighten, never relax.';

SELECT 'Reference data model ready' AS status;
