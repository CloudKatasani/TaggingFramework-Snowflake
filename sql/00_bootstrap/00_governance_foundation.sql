-- =============================================================================
-- 00_governance_foundation.sql
-- Enterprise Snowflake Tagging Framework - governance foundation
-- -----------------------------------------------------------------------------
-- Creates the governance database, its schemas, the RBAC model and the
-- warehouse that runs all governance automation.
--
-- Run as        : ACCOUNTADMIN (once per Snowflake account)
-- Idempotent    : yes - safe to re-run
-- Prerequisite  : Snowflake Enterprise Edition or higher (object tagging)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- 1. Functional roles
-- -----------------------------------------------------------------------------
-- TAG_ADMIN          owns tags and policies; the only role that may CREATE /
--                    ALTER / DROP a tag or a policy. Platform governance team.
-- TAG_STEWARD        applies tags to objects inside its own domain. Domain data
--                    stewards. Cannot change the taxonomy itself.
-- TAG_READER         read-only on governance reporting.
-- FINOPS_ANALYST     read-only on FinOps reporting.
-- COMPLIANCE_AUDITOR read-only on compliance evidence. Deliberately separate
--                    from TAG_READER so audit access can be granted without
--                    exposing operational metadata, and vice versa.
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS TAG_ADMIN
    COMMENT = 'Owns the enterprise tag taxonomy and the policies bound to it.';
CREATE ROLE IF NOT EXISTS TAG_STEWARD
    COMMENT = 'Applies enterprise tags to objects within an owned domain.';
CREATE ROLE IF NOT EXISTS TAG_READER
    COMMENT = 'Read-only access to governance metadata reporting.';
CREATE ROLE IF NOT EXISTS FINOPS_ANALYST
    COMMENT = 'Read-only access to tag-driven cost allocation reporting.';
CREATE ROLE IF NOT EXISTS COMPLIANCE_AUDITOR
    COMMENT = 'Read-only access to compliance evidence and control attestation.';

-- Role hierarchy.
GRANT ROLE TAG_READER         TO ROLE TAG_STEWARD;
GRANT ROLE TAG_STEWARD        TO ROLE TAG_ADMIN;
GRANT ROLE TAG_READER         TO ROLE FINOPS_ANALYST;
GRANT ROLE TAG_READER         TO ROLE COMPLIANCE_AUDITOR;
GRANT ROLE TAG_ADMIN          TO ROLE SYSADMIN;
GRANT ROLE FINOPS_ANALYST     TO ROLE SYSADMIN;
GRANT ROLE COMPLIANCE_AUDITOR TO ROLE SYSADMIN;

-- -----------------------------------------------------------------------------
-- 2. Account-level privileges
-- -----------------------------------------------------------------------------
-- APPLY TAG is an ACCOUNT-level privilege: it cannot be scoped to a database.
-- This is the single most important RBAC consequence of Snowflake tagging, and
-- the reason stewards are constrained by the SP_APPLY_TAG stored procedure
-- (which enforces domain ownership) rather than by raw grants.
GRANT APPLY TAG                ON ACCOUNT TO ROLE TAG_ADMIN;
GRANT APPLY MASKING POLICY     ON ACCOUNT TO ROLE TAG_ADMIN;
GRANT APPLY ROW ACCESS POLICY  ON ACCOUNT TO ROLE TAG_ADMIN;
GRANT APPLY AGGREGATION POLICY ON ACCOUNT TO ROLE TAG_ADMIN;
GRANT APPLY PROJECTION POLICY  ON ACCOUNT TO ROLE TAG_ADMIN;
GRANT EXECUTE TASK             ON ACCOUNT TO ROLE TAG_ADMIN;
GRANT EXECUTE MANAGED TASK     ON ACCOUNT TO ROLE TAG_ADMIN;
GRANT EXECUTE ALERT            ON ACCOUNT TO ROLE TAG_ADMIN;
GRANT MONITOR USAGE            ON ACCOUNT TO ROLE FINOPS_ANALYST;

-- Metadata read access. Prefer the SNOWFLAKE database roles over blanket
-- IMPORTED PRIVILEGES: they grant exactly the ACCOUNT_USAGE surface each role
-- needs and nothing more.
GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_ADMIN  TO ROLE TAG_ADMIN;
GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER TO ROLE TAG_READER;
GRANT DATABASE ROLE SNOWFLAKE.OBJECT_VIEWER     TO ROLE TAG_READER;
GRANT DATABASE ROLE SNOWFLAKE.USAGE_VIEWER      TO ROLE FINOPS_ANALYST;
GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER TO ROLE COMPLIANCE_AUDITOR;

-- -----------------------------------------------------------------------------
-- 3. Governance warehouse
-- -----------------------------------------------------------------------------
-- Deliberately small and aggressively suspended: the governance workload is
-- metadata-bound, not data-bound. Sizing it larger hides inefficient scans in
-- the drift-detection queries instead of forcing them to be fixed.
CREATE WAREHOUSE IF NOT EXISTS GOVERNANCE_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Dedicated warehouse for tag governance automation and reporting.';

GRANT USAGE   ON WAREHOUSE GOVERNANCE_WH TO ROLE TAG_ADMIN;
GRANT USAGE   ON WAREHOUSE GOVERNANCE_WH TO ROLE TAG_STEWARD;
GRANT USAGE   ON WAREHOUSE GOVERNANCE_WH TO ROLE TAG_READER;
GRANT USAGE   ON WAREHOUSE GOVERNANCE_WH TO ROLE FINOPS_ANALYST;
GRANT USAGE   ON WAREHOUSE GOVERNANCE_WH TO ROLE COMPLIANCE_AUDITOR;
GRANT OPERATE ON WAREHOUSE GOVERNANCE_WH TO ROLE TAG_ADMIN;

-- -----------------------------------------------------------------------------
-- 4. Governance database and schemas
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS GOVERNANCE
    COMMENT = 'Enterprise data governance control plane. Owned by the EDGO.';

GRANT OWNERSHIP ON DATABASE GOVERNANCE TO ROLE TAG_ADMIN COPY CURRENT GRANTS;

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;

CREATE SCHEMA IF NOT EXISTS TAGS
    WITH MANAGED ACCESS
    COMMENT = 'The one and only home of enterprise tag objects. Managed access so that only the schema owner can grant on tags.';

CREATE SCHEMA IF NOT EXISTS POLICIES
    WITH MANAGED ACCESS
    COMMENT = 'Masking, row access, aggregation and projection policies.';

CREATE SCHEMA IF NOT EXISTS CONTROL
    COMMENT = 'Control plane: tag registry, reference data, exceptions, findings.';

CREATE SCHEMA IF NOT EXISTS REPORTING
    COMMENT = 'Governance, compliance and FinOps reporting views.';

CREATE SCHEMA IF NOT EXISTS AUTOMATION
    COMMENT = 'Stored procedures, tasks, streams and alerts that enforce the framework.';

-- Drop the default PUBLIC schema: an ungoverned schema inside the governance
-- database is the first place shadow objects appear.
DROP SCHEMA IF EXISTS PUBLIC;

-- -----------------------------------------------------------------------------
-- 5. Schema-level grants
-- -----------------------------------------------------------------------------
GRANT USAGE ON DATABASE GOVERNANCE TO ROLE TAG_STEWARD;
GRANT USAGE ON DATABASE GOVERNANCE TO ROLE TAG_READER;
GRANT USAGE ON DATABASE GOVERNANCE TO ROLE FINOPS_ANALYST;
GRANT USAGE ON DATABASE GOVERNANCE TO ROLE COMPLIANCE_AUDITOR;

-- Stewards must be able to READ tag definitions (to know what is legal) but
-- never to create or alter them.
GRANT USAGE ON SCHEMA GOVERNANCE.TAGS       TO ROLE TAG_STEWARD;
GRANT USAGE ON SCHEMA GOVERNANCE.TAGS       TO ROLE TAG_READER;
GRANT USAGE ON SCHEMA GOVERNANCE.CONTROL    TO ROLE TAG_STEWARD;
GRANT USAGE ON SCHEMA GOVERNANCE.CONTROL    TO ROLE TAG_READER;
GRANT USAGE ON SCHEMA GOVERNANCE.REPORTING  TO ROLE TAG_STEWARD;
GRANT USAGE ON SCHEMA GOVERNANCE.REPORTING  TO ROLE TAG_READER;
GRANT USAGE ON SCHEMA GOVERNANCE.REPORTING  TO ROLE FINOPS_ANALYST;
GRANT USAGE ON SCHEMA GOVERNANCE.REPORTING  TO ROLE COMPLIANCE_AUDITOR;
GRANT USAGE ON SCHEMA GOVERNANCE.AUTOMATION TO ROLE TAG_STEWARD;

GRANT SELECT ON FUTURE VIEWS  IN SCHEMA GOVERNANCE.REPORTING TO ROLE TAG_READER;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA GOVERNANCE.REPORTING TO ROLE FINOPS_ANALYST;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA GOVERNANCE.REPORTING TO ROLE COMPLIANCE_AUDITOR;
GRANT SELECT ON FUTURE TABLES IN SCHEMA GOVERNANCE.CONTROL   TO ROLE TAG_READER;
GRANT SELECT ON ALL    VIEWS  IN SCHEMA GOVERNANCE.REPORTING TO ROLE TAG_READER;
GRANT SELECT ON ALL    TABLES IN SCHEMA GOVERNANCE.CONTROL   TO ROLE TAG_READER;

-- -----------------------------------------------------------------------------
-- 6. Guard rail: tags may only ever be created in GOVERNANCE.TAGS
-- -----------------------------------------------------------------------------
-- CREATE TAG is granted on exactly one schema, to exactly one role. Any other
-- role attempting CREATE TAG anywhere in the account fails on privilege. This
-- is what makes "one tag namespace" structurally true rather than a convention
-- people are asked to remember.
GRANT CREATE TAG               ON SCHEMA GOVERNANCE.TAGS     TO ROLE TAG_ADMIN;
GRANT CREATE MASKING POLICY    ON SCHEMA GOVERNANCE.POLICIES TO ROLE TAG_ADMIN;
GRANT CREATE ROW ACCESS POLICY ON SCHEMA GOVERNANCE.POLICIES TO ROLE TAG_ADMIN;

SELECT 'Governance foundation ready' AS status;
