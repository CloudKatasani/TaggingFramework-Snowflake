-- =============================================================================
-- 20_policies/00_entitlement_roles.sql
-- Unmasking entitlement roles referenced by the enterprise masking policies.
-- -----------------------------------------------------------------------------
-- The policies test role membership with IS_ROLE_IN_SESSION() rather than
-- CURRENT_ROLE(). This matters: IS_ROLE_IN_SESSION honours the role hierarchy
-- and secondary roles, so a user who inherits PII_UNMASKED through a business
-- role is correctly recognised. CURRENT_ROLE() compares one string and quietly
-- masks data for users who genuinely hold the entitlement.
--
-- Environment strategy: these roles are granted ONLY in the production account.
-- Lower environments deploy identical policy code with no unmask grants, so
-- non-production is unmasked-by-nobody without a single environment branch in
-- the policy body.
--
-- Run as: ACCOUNTADMIN (role creation), then TAG_ADMIN
-- =============================================================================

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS PII_UNMASKED
    COMMENT = 'Sees unmasked PII. Granted per named individual, time-boxed, re-attested quarterly.';
CREATE ROLE IF NOT EXISTS SPII_UNMASKED
    COMMENT = 'Sees unmasked sensitive PII (SSN, financial account, biometric). Strictly need-to-know.';
CREATE ROLE IF NOT EXISTS PHI_UNMASKED
    COMMENT = 'Sees unmasked PHI. HIPAA minimum-necessary review required before grant.';
CREATE ROLE IF NOT EXISTS PCI_UNMASKED
    COMMENT = 'Sees unmasked cardholder data. In PCI-DSS CDE scope; annual assessor evidence.';
CREATE ROLE IF NOT EXISTS RESTRICTED_DATA_READER
    COMMENT = 'Sees RESTRICTED classified data in clear. The top enterprise classification; break-glass, alerted on use.';
CREATE ROLE IF NOT EXISTS PSEUDONYM_ANALYST
    COMMENT = 'Sees deterministic pseudonyms instead of clear values - can join and cohort, cannot identify.';

-- These roles convey visibility, never object access. They are additive to the
-- normal access model: holding PII_UNMASKED without SELECT on the table shows
-- the holder nothing at all.
GRANT ROLE PII_UNMASKED           TO ROLE ACCOUNTADMIN;
GRANT ROLE SPII_UNMASKED          TO ROLE ACCOUNTADMIN;
GRANT ROLE PHI_UNMASKED           TO ROLE ACCOUNTADMIN;
GRANT ROLE PCI_UNMASKED           TO ROLE ACCOUNTADMIN;
GRANT ROLE RESTRICTED_DATA_READER TO ROLE ACCOUNTADMIN;
GRANT ROLE PSEUDONYM_ANALYST      TO ROLE ACCOUNTADMIN;

SELECT 'Entitlement roles ready' AS status;
