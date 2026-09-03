-- =============================================================================
-- examples/02_onboard_data_product.sql
-- Onboarding a data product end to end: CUSTOMER_360 in the CUSTOMER domain.
-- -----------------------------------------------------------------------------
-- Roughly twenty assignments protect the whole product, and most of them sit at
-- database and schema level where every future table reuses them.
--
-- Every call goes through SP_APPLY_TAG, which validates the value, enforces the
-- override rules, checks that the caller's role owns the namespace, and writes
-- an audit row with a reason. Raw ALTER ... SET TAG bypasses all four.
-- =============================================================================

USE ROLE TAG_STEWARD;
USE WAREHOUSE GOVERNANCE_WH;

SET TICKET = 'CHG-88213';
SET REASON = 'Data product onboarding CUSTOMER_360';

-- ── 1. Database: identity, economics, operations ────────────────────────────
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PROD', NULL,
    'BUSINESS_UNIT', 'RETAIL_BANKING', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PROD', NULL,
    'DOMAIN', 'CUSTOMER', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PROD', NULL,
    'ENVIRONMENT', 'PROD', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PROD', NULL,
    'COST_CENTER', 'CC-004120', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PROD', NULL,
    'SUPPORT_GROUP', 'GRP-CUSTOMER-ENG', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PROD', NULL,
    'DATA_OWNER', 'vp.customer@example.com', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PROD', NULL,
    'CRITICALITY', 'HIGH', $REASON, $TICKET, 'CICD');
-- A floor, not a ceiling: individual objects escalate from here.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PROD', NULL,
    'DATA_CLASSIFICATION', 'CONFIDENTIAL', $REASON, $TICKET, 'CICD');

-- ── 2. Schema: the data product boundary ────────────────────────────────────
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PROD.C360', NULL,
    'DATA_PRODUCT', 'CUSTOMER_360', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PROD.C360', NULL,
    'DATA_STEWARD', 'steward.customer@example.com', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PROD.C360', NULL,
    'REGULATION', 'GDPR', 'EU customer master data', $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PROD.C360', NULL,
    'RETENTION_CLASS', 'EXTENDED_7Y', 'Retention schedule RS-114', $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PROD.C360', NULL,
    'SLA_TIER', 'GOLD_1H', $REASON, $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PROD.C360', NULL,
    'DATA_LIFECYCLE', 'ACTIVE', $REASON, $TICKET, 'CICD');

-- CR-005: GDPR objects must declare residency.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('SCHEMA', 'CUSTOMER_PROD.C360', NULL,
    'DATA_RESIDENCY', 'EU', 'CR-005', $TICKET, 'CICD');

-- The full multi-regime scope. The REGULATION tag holds only the governing one.
INSERT INTO GOVERNANCE.CONTROL.REGULATORY_SCOPE
    (OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, OBJECT_TYPE, REGULATION,
     SCOPE_REASON, ASSESSED_BY, NEXT_REVIEW_DATE)
SELECT 'CUSTOMER_PROD', 'C360', c1, 'TABLE', c2, c3, CURRENT_USER(),
       DATEADD('year', 1, CURRENT_DATE())
FROM VALUES
    ('CUSTOMER_MASTER', 'GDPR', 'EU data subjects'),
    ('CUSTOMER_MASTER', 'CCPA', 'California residents in the same table'),
    ('CUSTOMER_MASTER', 'SOX',  'Feeds regulated financial reporting')
AS v(c1, c2, c3);

-- ── 3. Table: escalate classification, declare PII and row access ───────────
-- Accepted: RESTRICTED is more restrictive than the inherited CONFIDENTIAL.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('TABLE',
    'CUSTOMER_PROD.C360.CUSTOMER_MASTER', NULL,
    'DATA_CLASSIFICATION', 'RESTRICTED',
    'Contains the full customer identity set', $TICKET, 'CICD');

CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('TABLE',
    'CUSTOMER_PROD.C360.CUSTOMER_MASTER', NULL,
    'PII', 'YES', 'Customer identity data', $TICKET, 'CICD');

-- CR-003: RESTRICTED data requires row scoping.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('TABLE',
    'CUSTOMER_PROD.C360.CUSTOMER_MASTER', NULL,
    'ROW_ACCESS_REQUIRED', 'YES', 'CR-003', $TICKET, 'CICD');

-- ── 4. Columns: the enforcement point ───────────────────────────────────────
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PROD.C360.CUSTOMER_MASTER', 'EMAIL_ADDRESS',
    'PII', 'YES', 'Direct identifier', $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PROD.C360.CUSTOMER_MASTER', 'EMAIL_ADDRESS',
    'MASKING_REQUIRED', 'YES', 'CR-004', $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PROD.C360.CUSTOMER_MASTER', 'DATE_OF_BIRTH',
    'PII', 'YES', 'Quasi-identifier', $TICKET, 'CICD');
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PROD.C360.CUSTOMER_MASTER', 'DATE_OF_BIRTH',
    'MASKING_REQUIRED', 'YES', 'CR-004', $TICKET, 'CICD');

-- ── 5. What the framework refuses ───────────────────────────────────────────
-- Weakening an inherited control tag. Returns a REJECTED message, not an error,
-- so a batch of assignments reports the problem without aborting.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('COLUMN',
    'CUSTOMER_PROD.C360.CUSTOMER_MASTER', 'EMAIL_ADDRESS',
    'PII', 'NO', 'Attempting to silence a false positive', $TICKET, 'MANUAL');
-- → REJECTED: cannot weaken PII from inherited "YES" to "NO"...

-- A cost centre that is not open in the ERP.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('DATABASE', 'CUSTOMER_PROD', NULL,
    'COST_CENTER', 'CC-999999', 'Typo in the deployment script', $TICKET, 'CICD');
-- → REJECTED: "CC-999999" is not an active value in REF_COST_CENTER.

-- A tag that does not apply to the object type.
CALL GOVERNANCE.AUTOMATION.SP_APPLY_TAG('WAREHOUSE', 'CUSTOMER_WH', NULL,
    'RETENTION_CLASS', 'STANDARD_3Y', 'Misunderstanding', $TICKET, 'MANUAL');
-- → REJECTED: RETENTION_CLASS does not apply to WAREHOUSE.

-- ── 6. Verify ───────────────────────────────────────────────────────────────
CALL GOVERNANCE.AUTOMATION.SP_VALIDATE_COMPLIANCE('CUSTOMER_PROD', TRUE);

SELECT * FROM GOVERNANCE.REPORTING.VW_STEWARD_WORKLIST
 WHERE OBJECT_DATABASE = 'CUSTOMER_PROD';

SELECT * FROM GOVERNANCE.REPORTING.VW_COMPLIANCE_EVIDENCE
 WHERE OBJECT_DATABASE = 'CUSTOMER_PROD';

SELECT * FROM GOVERNANCE.REPORTING.VW_DATA_PRODUCT_CATALOG
 WHERE DATA_PRODUCT = 'CUSTOMER_360';
