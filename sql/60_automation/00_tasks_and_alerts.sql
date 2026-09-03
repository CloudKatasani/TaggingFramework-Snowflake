-- =============================================================================
-- 60_automation/00_tasks_and_alerts.sql
-- The scheduled control loop.
-- -----------------------------------------------------------------------------
-- CADENCE, AND WHY EACH ONE
-- -------------------------
--   every 15 min  row access reconciliation - this is the only control with a
--                 real exposure window (Snowflake cannot attach row policies to
--                 tags), so it runs far more often than anything else
--   hourly        policy drift - a detached masking policy is a live incident
--   daily 02:00   full compliance scan
--   daily 03:00   classification reconciliation (after the scan, so new columns
--                 are already in the inventory)
--   daily 05:00   scorecard snapshot (after both, so the trend reflects the day)
--
-- Run as: TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA AUTOMATION;

-- -----------------------------------------------------------------------------
-- Notification integration for alerts.
-- Replace the recipient list with real distribution addresses. Snowflake only
-- delivers to verified account users, so a shared mailbox must be onboarded as
-- a notification-only user first.
-- -----------------------------------------------------------------------------
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS GOVERNANCE_EMAIL_INT
    TYPE = EMAIL
    ENABLED = TRUE
    COMMENT = 'Delivers governance alerts to the data governance and security teams.';

GRANT USAGE ON INTEGRATION GOVERNANCE_EMAIL_INT TO ROLE TAG_ADMIN;

-- =============================================================================
-- TASKS
-- =============================================================================

-- Root of the daily DAG.
CREATE OR REPLACE TASK TASK_VALIDATE_COMPLIANCE
    WAREHOUSE = GOVERNANCE_WH
    SCHEDULE  = 'USING CRON 0 2 * * * UTC'
    COMMENT   = 'Nightly full-estate compliance scan.'
AS
    CALL SP_VALIDATE_COMPLIANCE(NULL, TRUE);

CREATE OR REPLACE TASK TASK_RECONCILE_CLASSIFICATION
    WAREHOUSE = GOVERNANCE_WH
    AFTER     = TASK_VALIDATE_COMPLIANCE
    COMMENT   = 'Reconciles Snowflake auto-classification with the enterprise PII tag.'
AS
    CALL SP_RECONCILE_CLASSIFICATION(TRUE);

CREATE OR REPLACE TASK TASK_SNAPSHOT_COMPLIANCE
    WAREHOUSE = GOVERNANCE_WH
    AFTER     = TASK_RECONCILE_CLASSIFICATION
    COMMENT   = 'Writes the daily governance scorecard.'
AS
    CALL SP_SNAPSHOT_COMPLIANCE();

-- Independent, high-frequency loop. Deliberately NOT part of the daily DAG:
-- a failure in the nightly scan must never stop row access policies being
-- applied to new tables.
CREATE OR REPLACE TASK TASK_APPLY_ROW_ACCESS
    WAREHOUSE = GOVERNANCE_WH
    SCHEDULE  = '15 MINUTE'
    COMMENT   = 'Applies row access policies to newly tagged tables. Closes the gap left by Snowflake not supporting tag-attached row policies.'
AS
    CALL SP_APPLY_ROW_ACCESS_POLICIES(FALSE);

CREATE OR REPLACE TASK TASK_DETECT_POLICY_DRIFT
    WAREHOUSE = GOVERNANCE_WH
    SCHEDULE  = '60 MINUTE'
    COMMENT   = 'Detects masking policies that have become detached from their tag.'
AS
    CALL SP_DETECT_POLICY_DRIFT();

-- Resume order matters: children before the root, or the DAG will not start.
ALTER TASK TASK_SNAPSHOT_COMPLIANCE     RESUME;
ALTER TASK TASK_RECONCILE_CLASSIFICATION RESUME;
ALTER TASK TASK_VALIDATE_COMPLIANCE     RESUME;
ALTER TASK TASK_APPLY_ROW_ACCESS        RESUME;
ALTER TASK TASK_DETECT_POLICY_DRIFT     RESUME;

-- =============================================================================
-- ALERTS
-- =============================================================================

-- A detached masking policy means data that is supposed to be masked is not.
-- This is the one alert that should wake somebody up.
CREATE OR REPLACE ALERT ALERT_POLICY_DRIFT
    WAREHOUSE = GOVERNANCE_WH
    SCHEDULE  = '30 MINUTE'
    COMMENT   = 'Fires when a declared tag/policy binding is no longer attached.'
IF (EXISTS (
    SELECT 1 FROM GOVERNANCE.CONTROL.COMPLIANCE_FINDING
     WHERE FINDING_TYPE = 'POLICY_DRIFT'
       AND STATUS = 'OPEN'
       AND SCAN_AT > DATEADD('hour', -1, CURRENT_TIMESTAMP())
))
THEN
    CALL SYSTEM$SEND_EMAIL(
        'GOVERNANCE_EMAIL_INT',
        'data-security@example.com',
        '[P1] Snowflake masking policy detached from tag',
        'One or more masking policies are no longer attached to their governing '
        || 'tag. Columns relying on tag-based masking are currently returning '
        || 'data in clear. Query GOVERNANCE.CONTROL.COMPLIANCE_FINDING where '
        || 'FINDING_TYPE = ''POLICY_DRIFT''.');

CREATE OR REPLACE ALERT ALERT_CRITICAL_FINDINGS
    WAREHOUSE = GOVERNANCE_WH
    SCHEDULE  = 'USING CRON 0 6 * * * UTC'
    COMMENT   = 'Daily digest of critical governance findings.'
IF (EXISTS (
    SELECT 1 FROM GOVERNANCE.CONTROL.COMPLIANCE_FINDING
     WHERE SEVERITY = 'CRITICAL' AND STATUS = 'OPEN'
))
THEN
    CALL SYSTEM$SEND_EMAIL(
        'GOVERNANCE_EMAIL_INT',
        'data-governance@example.com',
        '[Governance] Critical tagging findings require action',
        'Critical findings are open against the Snowflake estate. See '
        || 'GOVERNANCE.REPORTING.VW_COMPLIANCE_DASHBOARD.');

-- An exception that lapses without remediation is a control that has quietly
-- stopped applying. Chasing them a week before expiry is far cheaper than
-- explaining them after.
CREATE OR REPLACE ALERT ALERT_EXPIRING_EXCEPTIONS
    WAREHOUSE = GOVERNANCE_WH
    SCHEDULE  = 'USING CRON 0 7 * * MON UTC'
    COMMENT   = 'Weekly warning for exceptions expiring within 14 days.'
IF (EXISTS (
    SELECT 1 FROM GOVERNANCE.CONTROL.TAG_EXCEPTION
     WHERE STATUS = 'ACTIVE'
       AND EXPIRES_AT BETWEEN CURRENT_TIMESTAMP()
                          AND DATEADD('day', 14, CURRENT_TIMESTAMP())
))
THEN
    CALL SYSTEM$SEND_EMAIL(
        'GOVERNANCE_EMAIL_INT',
        'data-governance@example.com',
        '[Governance] Tag exceptions expiring within 14 days',
        'Renew with fresh justification or remediate. On expiry the underlying '
        || 'finding is automatically re-raised at HIGH severity.');

ALTER ALERT ALERT_POLICY_DRIFT       RESUME;
ALTER ALERT ALERT_CRITICAL_FINDINGS  RESUME;
ALTER ALERT ALERT_EXPIRING_EXCEPTIONS RESUME;

SELECT 'Tasks and alerts ready' AS status;
