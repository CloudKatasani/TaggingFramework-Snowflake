-- =========================================================================
-- GENERATED FILE - DO NOT EDIT.
-- Source : config/tag_catalog.yaml
-- Rebuild: make build   (scripts/generate_sql.py)
-- CI fails if this file differs from a fresh generation.
-- =========================================================================


-- -----------------------------------------------------------------------------
-- Tag-based masking policy attachment
-- -----------------------------------------------------------------------------
-- Run AFTER sql/20_policies/*.sql has created the policies themselves.
--
-- Snowflake permits at most ONE masking policy per data type per tag. Attaching
-- a policy to a tag makes every column that carries the tag masked, now and in
-- future, without touching the column - this is the single highest-leverage
-- control in the framework.
--
-- Row access policies CANNOT be attached to tags. They are applied by
-- AUTOMATION.SP_APPLY_ROW_ACCESS_POLICIES instead; see
-- docs/05-security-compliance-integration.md.
-- -----------------------------------------------------------------------------

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA TAGS;

-- data_classification_enterprise
-- Bound to data_classification_enterprise only. data_classification_regulatory deliberately carries no attachment of its own - it is read inside the policy body.
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE SET MASKING POLICY GOVERNANCE.POLICIES.MP_ENTERPRISE_STRING;
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE SET MASKING POLICY GOVERNANCE.POLICIES.MP_ENTERPRISE_NUMBER;
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE SET MASKING POLICY GOVERNANCE.POLICIES.MP_ENTERPRISE_DATE;
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE SET MASKING POLICY GOVERNANCE.POLICIES.MP_ENTERPRISE_TIMESTAMP_NTZ;
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE SET MASKING POLICY GOVERNANCE.POLICIES.MP_ENTERPRISE_VARIANT;

-- Verification: every attachment above should appear here.
SELECT tag_database, tag_schema, tag_name, policy_db, policy_schema, policy_name
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
        POLICY_KIND => 'MASKING_POLICY'))
WHERE tag_name IS NOT NULL
ORDER BY tag_name, policy_name;
