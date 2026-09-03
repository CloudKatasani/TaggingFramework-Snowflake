-- =============================================================================
-- examples/02_onboard_data_product.sql
-- Onboarding a workload end to end against the allocation hierarchy.
-- -----------------------------------------------------------------------------
-- The hierarchy reads top-down, and so does this script:
--
--   operating_company -> department -> domain -> team -> application
--                     -> workload_type -> owner_user
--   + environment + the two classification tags
--
-- Roughly twenty assignments protect the whole product, and most sit at database
-- and schema level where every future table reuses them by inheritance.
--
-- Every call goes through SP_APPLY_TAG, which validates the value, enforces the
-- override rules, checks that the caller's role owns the namespace, and writes
-- an audit row with a reason. A raw ALTER ... SET TAG bypasses all four.
-- =============================================================================

USE ROLE TAG_STEWARD;
USE WAREHOUSE GOVERNANCE_WH;

SET TICKET = 'CHG-88213';
SET REASON = 'Onboarding Customer 360 data product';

-- ── 1. Database: the allocation hierarchy down to team ──────────────────────
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'OPERATING_COMPANY', 'OPCO_AEP_OHIO', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'DEPARTMENT', 'CUSTOMER', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'DOMAIN', 'CUSTOMER', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'TEAM', 'team-customer-360', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'ENVIRONMENT', 'PRD', $REASON, $TICKET, 'CICD');
-- A floor, not a ceiling: individual objects escalate from here.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'DATA_CLASSIFICATION_ENTERPRISE', 'CONFIDENTIAL', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'OWNER_USER', 'jane.doe@aep.com', $REASON, $TICKET, 'CICD');

-- ── 2. Schema: application, data product, governance ────────────────────────
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PRD.C360', NULL,
    'APPLICATION', 'app-cust360-api', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PRD.C360', NULL,
    'DATA_PRODUCT', 'dp-customer-360', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PRD.C360', NULL,
    'WORKLOAD_TYPE', 'ANALYTICS', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PRD.C360', NULL,
    'DATA_OWNER', 'vp.customer@aep.com', 'CR-004: regulated data needs an owner',
    $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PRD.C360', NULL,
    'RETENTION_CLASS', 'EXTENDED_7Y', 'Retention schedule RS-114', $TICKET, 'CICD');
-- CR-008: production workloads must name an on-call queue and an SLA.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PRD.C360', NULL,
    'SUPPORT_GROUP', 'GRP-CUSTOMER-ENG', 'CR-008', $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PRD.C360', NULL,
    'SLA_TIER', 'GOLD_1H', 'CR-008', $TICKET, 'CICD');
-- CR-005: SPII and above must declare residency.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PRD.C360', NULL,
    'DATA_RESIDENCY', 'US_EAST', 'CR-005', $TICKET, 'CICD');

-- ── 3. Warehouse: infrastructure carries its own hierarchy ──────────────────
-- A warehouse belongs to no database, so nothing is inherited: every allocation
-- tag has to be set directly or the compute lands in <UNALLOCATED>.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('WAREHOUSE', 'CUSTOMER_ANALYTICS_WH', NULL,
    'OPERATING_COMPANY', 'OPCO_AEP_OHIO', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('WAREHOUSE', 'CUSTOMER_ANALYTICS_WH', NULL,
    'DEPARTMENT', 'CUSTOMER', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('WAREHOUSE', 'CUSTOMER_ANALYTICS_WH', NULL,
    'TEAM', 'team-customer-360', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('WAREHOUSE', 'CUSTOMER_ANALYTICS_WH', NULL,
    'APPLICATION', 'app-cust360-api', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('WAREHOUSE', 'CUSTOMER_ANALYTICS_WH', NULL,
    'WORKLOAD_TYPE', 'ANALYTICS', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('WAREHOUSE', 'CUSTOMER_ANALYTICS_WH', NULL,
    'ENVIRONMENT', 'PRD', $REASON, $TICKET, 'CICD');

-- ── 4. Table: escalate classification, declare row access ───────────────────
-- Accepted: RESTRICTED is more restrictive than the inherited CONFIDENTIAL.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('TABLE',
    'CUSTOMER_PRD.C360.CUSTOMER_MASTER', NULL,
    'DATA_CLASSIFICATION_ENTERPRISE', 'RESTRICTED',
    'Contains the full customer identity set', $TICKET, 'CICD');

CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('TABLE',
    'CUSTOMER_PRD.C360.CUSTOMER_MASTER', NULL,
    'DATA_CLASSIFICATION_REGULATORY', 'PII',
    'Customer identity data', $TICKET, 'CICD');

-- CR-003: RESTRICTED data requires row scoping.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('TABLE',
    'CUSTOMER_PRD.C360.CUSTOMER_MASTER', NULL,
    'ROW_ACCESS_REQUIRED', 'YES', 'CR-003', $TICKET, 'CICD');

-- ── 5. Columns: the enforcement point ───────────────────────────────────────
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PRD.C360.CUSTOMER_MASTER', 'EMAIL_ADDRESS',
    'DATA_CLASSIFICATION_REGULATORY', 'PII', 'Direct identifier', $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PRD.C360.CUSTOMER_MASTER', 'EMAIL_ADDRESS',
    'MASKING_REQUIRED', 'YES', 'CR-001', $TICKET, 'CICD');

-- SPII outranks PII, so this column masks harder than the one above even though
-- both sit in the same table. That is the ordinal vocabulary doing its job.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PRD.C360.CUSTOMER_MASTER', 'SSN',
    'DATA_CLASSIFICATION_REGULATORY', 'SPII', 'Sensitive identifier', $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PRD.C360.CUSTOMER_MASTER', 'SSN',
    'MASKING_REQUIRED', 'YES', 'CR-001', $TICKET, 'CICD');

-- The full multi-category scope. The tag holds only the governing category.
INSERT INTO GOVERNANCE.CONTROL.REGULATORY_SCOPE
    (OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, OBJECT_TYPE, COLUMN_NAME,
     REGULATION, SCOPE_REASON, ASSESSED_BY, NEXT_REVIEW_DATE)
SELECT 'CUSTOMER_PRD', 'C360', 'CUSTOMER_MASTER', 'TABLE', c1, c2, c3,
       CURRENT_USER(), DATEADD('year', 1, CURRENT_DATE())
FROM VALUES
    (NULL,   'CCPA', 'California residents present in the customer base'),
    (NULL,   'SOX',  'Feeds regulated financial reporting'),
    ('SSN',  'GLBA', 'Non-public personal information under GLBA')
AS v(c1, c2, c3);

-- ── 6. What the framework refuses ───────────────────────────────────────────
-- Weakening an inherited control tag. Returns a REJECTED message rather than
-- raising, so a batch reports the problem without aborting.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PRD.C360.CUSTOMER_MASTER', 'SSN',
    'DATA_CLASSIFICATION_REGULATORY', 'PII',
    'Attempting to downgrade SPII to PII', $TICKET, 'MANUAL');
-- → REJECTED: cannot weaken DATA_CLASSIFICATION_REGULATORY from "SPII" to "PII".

-- A team that is not in the registry (or has been disbanded).
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'TEAM', 'team-does-not-exist', 'Typo in the deployment script', $TICKET, 'CICD');
-- → REJECTED: "team-does-not-exist" is not an active value in REF_TEAM.

-- A value outside the controlled vocabulary. Snowflake itself would also reject
-- this; SP_APPLY_TAG catches it first and explains it in business language.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PRD', NULL,
    'ENVIRONMENT', 'PROD', 'Wrong spelling - the standard value is PRD',
    $TICKET, 'MANUAL');
-- → REJECTED: "PROD" is not an allowed value of ENVIRONMENT.

-- A tag that does not apply to the object type.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('WAREHOUSE', 'CUSTOMER_ANALYTICS_WH', NULL,
    'RETENTION_CLASS', 'STANDARD_3Y', 'Misunderstanding', $TICKET, 'MANUAL');
-- → REJECTED: RETENTION_CLASS does not apply to WAREHOUSE.

-- ── 7. Verify ───────────────────────────────────────────────────────────────
CALL GOVERNANCE.AUTOMATION.SP_VALIDATE_COMPLIANCE('CUSTOMER_PRD', TRUE);

SELECT * FROM GOVERNANCE.REPORTING.VW_STEWARD_WORKLIST
 WHERE OBJECT_DATABASE = 'CUSTOMER_PRD';

SELECT * FROM GOVERNANCE.REPORTING.VW_COMPLIANCE_EVIDENCE
 WHERE OBJECT_DATABASE = 'CUSTOMER_PRD';
