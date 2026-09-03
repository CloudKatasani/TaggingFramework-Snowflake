-- =============================================================================
-- 90_teardown/00_teardown.sql
-- Removes the framework from a Snowflake account.
-- -----------------------------------------------------------------------------
-- !! DESTRUCTIVE !!  For sandbox and demo accounts only.
--
-- Running this on an account carrying real assignments will:
--   * detach every masking policy from its tag, unmasking data immediately;
--   * remove every tag assignment across the estate;
--   * destroy the audit trail in CONTROL.TAG_CHANGE_LOG.
--
-- There is no safe production use of this script. Retiring a single tag from a
-- live estate is AUTOMATION.SP_RETIRE_TAG; retiring the framework is a project,
-- not a script.
--
-- This file is excluded from scripts/lint_sql.py, which otherwise blocks DROP
-- TAG repository-wide.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Stop the control loop before removing what it operates on, or tasks will fail
-- loudly against half-deleted objects for as long as they remain resumed.
ALTER TASK  IF EXISTS GOVERNANCE.AUTOMATION.TASK_VALIDATE_COMPLIANCE      SUSPEND;
ALTER TASK  IF EXISTS GOVERNANCE.AUTOMATION.TASK_RECONCILE_CLASSIFICATION SUSPEND;
ALTER TASK  IF EXISTS GOVERNANCE.AUTOMATION.TASK_SNAPSHOT_COMPLIANCE      SUSPEND;
ALTER TASK  IF EXISTS GOVERNANCE.AUTOMATION.TASK_APPLY_ROW_ACCESS         SUSPEND;
ALTER TASK  IF EXISTS GOVERNANCE.AUTOMATION.TASK_DETECT_POLICY_DRIFT      SUSPEND;
ALTER ALERT IF EXISTS GOVERNANCE.AUTOMATION.ALERT_POLICY_DRIFT            SUSPEND;
ALTER ALERT IF EXISTS GOVERNANCE.AUTOMATION.ALERT_CRITICAL_FINDINGS       SUSPEND;
ALTER ALERT IF EXISTS GOVERNANCE.AUTOMATION.ALERT_EXPIRING_EXCEPTIONS     SUSPEND;

-- Detach masking policies from the tag before dropping anything. Dropping a tag
-- that still carries a policy attachment leaves the policy orphaned and the
-- columns unprotected with no record of what changed.
ALTER TAG IF EXISTS GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE
    UNSET MASKING POLICY GOVERNANCE.POLICIES.MP_ENTERPRISE_STRING;
ALTER TAG IF EXISTS GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE
    UNSET MASKING POLICY GOVERNANCE.POLICIES.MP_ENTERPRISE_NUMBER;
ALTER TAG IF EXISTS GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE
    UNSET MASKING POLICY GOVERNANCE.POLICIES.MP_ENTERPRISE_DATE;
ALTER TAG IF EXISTS GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE
    UNSET MASKING POLICY GOVERNANCE.POLICIES.MP_ENTERPRISE_TIMESTAMP_NTZ;
ALTER TAG IF EXISTS GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE
    UNSET MASKING POLICY GOVERNANCE.POLICIES.MP_ENTERPRISE_VARIANT;

-- Dropping the database takes the tags, policies, procedures, tasks, views and
-- the entire control plane with it.
DROP DATABASE IF EXISTS GOVERNANCE;

DROP WAREHOUSE IF EXISTS GOVERNANCE_WH;

-- Roles last: dropping a role that still owns objects transfers ownership in
-- ways that are tedious to unpick.
DROP ROLE IF EXISTS TAG_STEWARD;
DROP ROLE IF EXISTS TAG_READER;
DROP ROLE IF EXISTS FINOPS_ANALYST;
DROP ROLE IF EXISTS COMPLIANCE_AUDITOR;
DROP ROLE IF EXISTS TAG_ADMIN;
DROP ROLE IF EXISTS PII_UNMASKED;
DROP ROLE IF EXISTS PHI_UNMASKED;
DROP ROLE IF EXISTS PCI_UNMASKED;
DROP ROLE IF EXISTS RESTRICTED_DATA_READER;
DROP ROLE IF EXISTS SPII_UNMASKED;
DROP ROLE IF EXISTS PSEUDONYM_ANALYST;

SELECT 'Framework removed' AS status;
