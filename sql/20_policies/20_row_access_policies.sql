-- =============================================================================
-- 20_policies/20_row_access_policies.sql
-- Row access policies driven by the ROW_ACCESS_REQUIRED tag.
-- -----------------------------------------------------------------------------
-- THE CONSTRAINT THAT SHAPES THIS FILE
-- ------------------------------------
-- Snowflake supports tag-based MASKING policies. It does NOT support attaching a
-- row access policy to a tag. Every design that claims "tags drive row access"
-- has to close that gap somewhere; this framework closes it explicitly with a
-- reconciliation task (AUTOMATION.SP_APPLY_ROW_ACCESS_POLICIES) that reads the
-- ROW_ACCESS_REQUIRED tag and issues the ALTER TABLE statements.
--
-- Consequence to be honest about: row access enforcement is eventually
-- consistent, on the task's cadence, whereas masking is immediate on tag
-- assignment. A table created and populated between two task runs is
-- unprotected in that window. Two mitigations, both implemented here:
--   1. The task runs every 15 minutes, not nightly.
--   2. New objects are caught by the object-creation stream, not only by the
--      schedule - see sql/60_automation/20_tasks.sql.
-- Where that window is still unacceptable, the CI/CD pipeline applies the policy
-- in the same deployment that creates the table (see .github/workflows).
--
-- Run as: TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA POLICIES;

-- -----------------------------------------------------------------------------
-- RAP_OPERATING_COMPANY_SCOPE
-- -----------------------------------------------------------------------------
-- Restricts rows to the operating companies a session's roles are entitled to.
-- Operating company is the outermost allocation and jurisdiction boundary, which
-- makes it the right default axis for row-level scoping: it is the one dimension
-- every regulated dataset in the estate can be sliced on.
-- The entitlement table is the single mapping consulted by every row policy, so
-- an access review is one query rather than a policy-by-policy audit.
--
-- Performance note: Snowflake caches the policy predicate per query, not per
-- row, so the EXISTS lookup is evaluated once against a small table. Keep
-- ROW_ACCESS_ENTITLEMENT narrow - it is on the critical path of every scan of
-- every protected table in the account.
CREATE ROW ACCESS POLICY IF NOT EXISTS RAP_OPERATING_COMPANY_SCOPE
AS (OPERATING_COMPANY STRING) RETURNS BOOLEAN ->
    -- Full-estate roles bypass the lookup entirely.
    IS_ROLE_IN_SESSION('TAG_ADMIN')
    OR IS_ROLE_IN_SESSION('COMPLIANCE_AUDITOR')
    OR EXISTS (
        SELECT 1
        FROM GOVERNANCE.CONTROL.ROW_ACCESS_ENTITLEMENT e
        WHERE e.DIMENSION = 'OPERATING_COMPANY'
          AND e.IS_ACTIVE
          AND (e.EXPIRES_AT IS NULL OR e.EXPIRES_AT > CURRENT_TIMESTAMP())
          AND (e.DIMENSION_VALUE = OPERATING_COMPANY OR e.DIMENSION_VALUE = '*')
          AND IS_ROLE_IN_SESSION(e.ROLE_NAME)
    )
COMMENT = 'Row-level scoping by operating company, driven by CONTROL.ROW_ACCESS_ENTITLEMENT.';

-- -----------------------------------------------------------------------------
-- RAP_DOMAIN_SCOPE
-- -----------------------------------------------------------------------------
CREATE ROW ACCESS POLICY IF NOT EXISTS RAP_DOMAIN_SCOPE
AS (DOMAIN STRING) RETURNS BOOLEAN ->
    IS_ROLE_IN_SESSION('TAG_ADMIN')
    OR IS_ROLE_IN_SESSION('COMPLIANCE_AUDITOR')
    OR EXISTS (
        SELECT 1
        FROM GOVERNANCE.CONTROL.ROW_ACCESS_ENTITLEMENT e
        WHERE e.DIMENSION = 'DOMAIN'
          AND e.IS_ACTIVE
          AND (e.EXPIRES_AT IS NULL OR e.EXPIRES_AT > CURRENT_TIMESTAMP())
          AND (e.DIMENSION_VALUE = DOMAIN OR e.DIMENSION_VALUE = '*')
          AND IS_ROLE_IN_SESSION(e.ROLE_NAME)
    )
COMMENT = 'Row-level scoping by data mesh domain.';

-- -----------------------------------------------------------------------------
-- RAP_DATA_RESIDENCY
-- -----------------------------------------------------------------------------
-- Data residency is the one dimension where the framework does NOT allow a
-- wildcard entitlement: '*' is deliberately not honoured here, because "this
-- role may read data from every jurisdiction" is a statement no single grant
-- should be able to make. Each region must be granted explicitly.
CREATE ROW ACCESS POLICY IF NOT EXISTS RAP_DATA_RESIDENCY
AS (RESIDENCY_REGION STRING) RETURNS BOOLEAN ->
    EXISTS (
        SELECT 1
        FROM GOVERNANCE.CONTROL.ROW_ACCESS_ENTITLEMENT e
        WHERE e.DIMENSION = 'DATA_RESIDENCY'
          AND e.IS_ACTIVE
          AND (e.EXPIRES_AT IS NULL OR e.EXPIRES_AT > CURRENT_TIMESTAMP())
          AND e.DIMENSION_VALUE = RESIDENCY_REGION    -- no wildcard, by design
          AND IS_ROLE_IN_SESSION(e.ROLE_NAME)
    )
COMMENT = 'Row-level scoping by data residency region. Wildcard entitlements are not honoured.';

-- -----------------------------------------------------------------------------
-- AGG_RESTRICTED - aggregation policy
-- -----------------------------------------------------------------------------
-- Some RESTRICTED datasets should be analysable in aggregate but never row by
-- row (salary bands, health cohorts, meter-level consumption). An aggregation
-- policy forces a minimum group size, which a masking policy cannot express.
CREATE AGGREGATION POLICY IF NOT EXISTS AGG_RESTRICTED
AS () RETURNS AGGREGATION_CONSTRAINT ->
    CASE
        WHEN IS_ROLE_IN_SESSION('RESTRICTED_DATA_READER')
            THEN NO_AGGREGATION_CONSTRAINT()
        ELSE AGGREGATION_CONSTRAINT(MIN_GROUP_SIZE => 25)
    END
COMMENT = 'Forces a minimum group size of 25 for non-privileged readers of RESTRICTED data.';

-- -----------------------------------------------------------------------------
-- PROJ_PCI_COLUMNS - projection policy
-- -----------------------------------------------------------------------------
-- Prevents a cardholder-data column from being SELECTed into an output at all,
-- while still allowing it to be used in joins and predicates. This is the
-- control that stops "SELECT card_number" from succeeding even when masked
-- output would technically have been safe - PCI-DSS assessors ask for it.
CREATE PROJECTION POLICY IF NOT EXISTS PROJ_PCI_NO_OUTPUT
AS () RETURNS PROJECTION_CONSTRAINT ->
    CASE
        WHEN IS_ROLE_IN_SESSION('PCI_UNMASKED') THEN PROJECTION_CONSTRAINT(ALLOW => TRUE)
        ELSE PROJECTION_CONSTRAINT(ALLOW => FALSE)
    END
COMMENT = 'Blocks projection of cardholder-data columns for roles outside the CDE.';

SELECT 'Row access, aggregation and projection policies ready' AS status;
