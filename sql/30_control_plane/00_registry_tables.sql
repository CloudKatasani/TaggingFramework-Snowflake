-- =============================================================================
-- 30_control_plane/00_registry_tables.sql
-- The tag registry: a queryable projection of config/tag_catalog.yaml.
-- -----------------------------------------------------------------------------
-- Snowflake's own metadata cannot answer "is this tag mandatory on a table?",
-- "who owns it?", "what consumes it?" or "when was it approved?". The registry
-- holds that governance metadata so procedures, views and auditors can reason
-- about the taxonomy in SQL.
--
-- Populated by : sql/_generated/11_catalog_seed.sql (generated from the YAML)
-- Run as       : TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA CONTROL;

-- -----------------------------------------------------------------------------
-- TAG_CATALOG - one row per enterprise tag definition
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS TAG_CATALOG (
    TAG_NAME             STRING       NOT NULL,
    TIER                 NUMBER(1,0)  NOT NULL,
    CATEGORY             STRING       NOT NULL,
    DESCRIPTION          STRING       NOT NULL,
    VALUE_SOURCE         STRING       NOT NULL,
    VALUE_FORMAT_REGEX   STRING,
    REFERENCE_SET        STRING,
    INHERITANCE_MODE     STRING       NOT NULL,
    OVERRIDE_RULE        STRING       NOT NULL,
    ORDINAL_VALUES       ARRAY,
    DRIVES               ARRAY        NOT NULL,
    OWNER_ROLE           STRING       NOT NULL,
    TAG_VERSION          STRING       NOT NULL,
    STATUS               STRING       NOT NULL,
    DEPRECATES           STRING,
    CATALOG_VERSION      STRING       NOT NULL,
    LOADED_AT            TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    LOADED_BY            STRING        NOT NULL DEFAULT CURRENT_USER(),
    CONSTRAINT PK_TAG_CATALOG PRIMARY KEY (TAG_NAME) RELY,
    CONSTRAINT CK_TIER  CHECK (TIER IN (1, 2, 3)),
    CONSTRAINT CK_STAT  CHECK (STATUS IN ('ACTIVE', 'DEPRECATED', 'RETIRED'))
)
COMMENT = 'Registry of enterprise tag definitions. Generated from config/tag_catalog.yaml.';

-- -----------------------------------------------------------------------------
-- TAG_ALLOWED_VALUE - controlled vocabulary, with ordinal severity
-- -----------------------------------------------------------------------------
-- Duplicates Snowflake's own ALLOWED_VALUES on purpose: Snowflake enforces the
-- list but exposes no severity ordering, no per-value description and no
-- effective dating. "Most restrictive wins" inheritance needs ORDINAL_POSITION.
CREATE TABLE IF NOT EXISTS TAG_ALLOWED_VALUE (
    TAG_NAME          STRING       NOT NULL,
    TAG_VALUE         STRING       NOT NULL,
    ORDINAL_POSITION  NUMBER(5,0),
    VALUE_DESCRIPTION STRING,
    IS_ACTIVE         BOOLEAN      NOT NULL DEFAULT TRUE,
    LOADED_AT         TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_TAG_ALLOWED_VALUE PRIMARY KEY (TAG_NAME, TAG_VALUE) RELY,
    CONSTRAINT FK_TAV_TAG FOREIGN KEY (TAG_NAME) REFERENCES TAG_CATALOG (TAG_NAME) RELY
)
COMMENT = 'Controlled vocabulary per tag. ORDINAL_POSITION ascends least -> most restrictive.';

-- -----------------------------------------------------------------------------
-- TAG_REQUIREMENT - the mandatory/optional matrix, in queryable form
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS TAG_REQUIREMENT (
    TAG_NAME          STRING NOT NULL,
    OBJECT_TYPE       STRING NOT NULL,
    REQUIREMENT_LEVEL STRING NOT NULL,
    LOADED_AT         TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_TAG_REQUIREMENT PRIMARY KEY (TAG_NAME, OBJECT_TYPE) RELY,
    CONSTRAINT FK_TR_TAG FOREIGN KEY (TAG_NAME) REFERENCES TAG_CATALOG (TAG_NAME) RELY,
    CONSTRAINT CK_LEVEL CHECK (REQUIREMENT_LEVEL IN
        ('MANDATORY', 'RECOMMENDED', 'OPTIONAL', 'INHERITED', 'NOT_APPLICABLE'))
)
COMMENT = 'Requirement level of each tag on each object type. Drives SP_VALIDATE_COMPLIANCE.';

-- -----------------------------------------------------------------------------
-- TAG_CONDITIONAL_RULE - "mandatory when ..." rules
-- -----------------------------------------------------------------------------
-- Modelled relationally rather than as a VARIANT blob so that the compliance
-- procedure can join to it and an auditor can read the control set in SQL.
CREATE TABLE IF NOT EXISTS TAG_CONDITIONAL_RULE (
    RULE_ID       STRING  NOT NULL,
    DESCRIPTION   STRING  NOT NULL,
    SEVERITY      STRING  NOT NULL,
    OBJECT_TYPES  ARRAY   NOT NULL,
    PREDICATE     OBJECT  NOT NULL,   -- {TAG_NAME: [value, ...]}; empty = always
    THEN_MANDATORY ARRAY  NOT NULL,
    IS_ACTIVE     BOOLEAN NOT NULL DEFAULT TRUE,
    LOADED_AT     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_TAG_CONDITIONAL_RULE PRIMARY KEY (RULE_ID) RELY,
    CONSTRAINT CK_SEVERITY CHECK (SEVERITY IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL'))
)
COMMENT = 'Conditional tag mandates evaluated against effective (lineage-resolved) tag values.';

-- -----------------------------------------------------------------------------
-- TAG_POLICY_BINDING - declared tag -> policy attachments
-- -----------------------------------------------------------------------------
-- The DECLARED state. Snowflake's ACCOUNT_USAGE.POLICY_REFERENCES holds the
-- ACTUAL state. VW_POLICY_DRIFT is the difference, and the difference is the
-- control failure an auditor cares about.
CREATE TABLE IF NOT EXISTS TAG_POLICY_BINDING (
    TAG_NAME      STRING NOT NULL,
    TAG_VALUE     STRING,             -- NULL = binding applies for any value
    POLICY_KIND   STRING NOT NULL,    -- MASKING | ROW_ACCESS | AGGREGATION | PROJECTION
    POLICY_NAME   STRING NOT NULL,
    DATA_TYPE     STRING,             -- masking only; one policy per type per tag
    ATTACH_MODE   STRING NOT NULL,    -- TAG_ATTACHED | RECONCILED
    NOTES         STRING,
    IS_ACTIVE     BOOLEAN NOT NULL DEFAULT TRUE,
    LOADED_AT     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_TAG_POLICY_BINDING
        PRIMARY KEY (TAG_NAME, POLICY_KIND, POLICY_NAME, DATA_TYPE) RELY,
    CONSTRAINT CK_KIND CHECK (POLICY_KIND IN
        ('MASKING', 'ROW_ACCESS', 'AGGREGATION', 'PROJECTION')),
    -- TAG_ATTACHED = Snowflake attaches the policy through the tag itself.
    -- RECONCILED   = Snowflake has no tag-attachment mechanism for this policy
    --                kind, so a task applies it. Row access policies are always
    --                RECONCILED - see docs/05-security-compliance-integration.md.
    CONSTRAINT CK_ATTACH CHECK (ATTACH_MODE IN ('TAG_ATTACHED', 'RECONCILED'))
)
COMMENT = 'Declared bindings between tags and governance policies. Compared against POLICY_REFERENCES to detect drift.';

-- -----------------------------------------------------------------------------
-- REGULATION_PRECEDENCE - resolves MULTI into a governing regime
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS REGULATION_PRECEDENCE (
    REGULATION       STRING      NOT NULL,
    PRECEDENCE_ORDER NUMBER(3,0) NOT NULL,
    NOTES            STRING,
    CONSTRAINT PK_REGULATION_PRECEDENCE PRIMARY KEY (REGULATION) RELY
)
COMMENT = 'Lower PRECEDENCE_ORDER wins when several regimes apply to one object.';

SELECT 'Registry tables ready' AS status;
