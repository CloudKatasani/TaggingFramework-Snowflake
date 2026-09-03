-- =============================================================================
-- 20_policies/10_masking_policies.sql
-- The enterprise masking policy set - five policies, one per protected data type.
-- -----------------------------------------------------------------------------
-- ARCHITECTURE
-- ------------
-- Exactly one tag (DATA_CLASSIFICATION) carries masking attachments. Because
-- DATA_CLASSIFICATION is mandatory on every table and view, tag lineage puts one
-- of these policies on every column of a matching data type in the estate. The
-- policy body then branches on the finer-grained signals - PII, PHI, PCI,
-- SENSITIVE_DATA - read from the column itself.
--
-- Why not a policy per privacy tag: a column tagged both PII and RESTRICTED
-- would then have two candidate policies for the same data type, and which one
-- won would depend on tag-lineage proximity rather than on which is the stronger
-- control. Single attachment removes that class of ambiguity.
--
-- FAIL-CLOSED
-- -----------
-- Every branch defaults to masked. COALESCE(..., 'RESTRICTED') on the
-- classification read means an unreadable or absent tag masks the value rather
-- than exposing it. A governance framework that fails open is worse than none,
-- because it also carries an assurance claim.
--
-- CONSTRAINTS THIS CODE RESPECTS
-- ------------------------------
--  * A tag-attached masking policy takes exactly one argument. Conditional
--    columns (masking based on a second column) are NOT supported with tag-based
--    attachment - those few cases are attached directly to the column instead.
--  * The policy body must be deterministic and cheap: it runs per row.
--    Role checks and tag reads are metadata operations; table lookups are not,
--    which is why entitlement mapping lives in the row access policies only.
--
-- Run as: TAG_ADMIN
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA POLICIES;

-- -----------------------------------------------------------------------------
-- Helper: the classification of the column currently being evaluated.
-- Kept as a separate expression in every policy rather than a UDF, because a
-- UDF call inside a masking policy adds per-row overhead on very wide scans.
-- -----------------------------------------------------------------------------

-- =============================================================================
-- STRING
-- =============================================================================
CREATE MASKING POLICY IF NOT EXISTS MP_ENTERPRISE_STRING
AS (VAL STRING) RETURNS STRING ->
    CASE
        -- 1. Cardholder data: strictest. Reveal last four only to PCI holders.
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PCI'), 'NO') = 'YES'
            THEN CASE
                WHEN IS_ROLE_IN_SESSION('PCI_UNMASKED') THEN VAL
                WHEN VAL IS NULL OR LENGTH(VAL) < 4 THEN '****'
                ELSE REPEAT('*', LENGTH(VAL) - 4) || RIGHT(VAL, 4)
            END

        -- 2. Protected health information.
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PHI'), 'NO') = 'YES'
            THEN CASE
                WHEN IS_ROLE_IN_SESSION('PHI_UNMASKED') THEN VAL
                WHEN IS_ROLE_IN_SESSION('PSEUDONYM_ANALYST')
                    THEN 'PHI#' || SHA2(VAL, 256)
                ELSE '***PHI REDACTED***'
            END

        -- 3. GDPR Art. 9 special categories - never partially revealed, because
        --    a partial reveal of a special category is still a disclosure.
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.SENSITIVE_DATA'), 'NO') = 'YES'
            THEN CASE
                WHEN IS_ROLE_IN_SESSION('PII_UNMASKED')
                     AND IS_ROLE_IN_SESSION('HIGHLY_RESTRICTED_DATA_READER') THEN VAL
                ELSE '***SPECIAL CATEGORY***'
            END

        -- 4. General PII. Pseudonymised for analysts so cohort analysis and
        --    joins survive masking - the difference between a privacy control
        --    people work with and one they route around.
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PII'), 'NO') = 'YES'
            THEN CASE
                WHEN IS_ROLE_IN_SESSION('PII_UNMASKED') THEN VAL
                WHEN IS_ROLE_IN_SESSION('PSEUDONYM_ANALYST')
                    THEN 'PID#' || LEFT(SHA2(VAL, 256), 16)
                ELSE '***MASKED***'
            END

        -- 5. No privacy flag: fall back to the confidentiality level.
        ELSE CASE COALESCE(
                SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.DATA_CLASSIFICATION'),
                'RESTRICTED')                       -- fail closed
            WHEN 'PUBLIC'       THEN VAL
            WHEN 'INTERNAL'     THEN VAL
            WHEN 'CONFIDENTIAL' THEN VAL
            WHEN 'RESTRICTED'   THEN
                CASE WHEN IS_ROLE_IN_SESSION('RESTRICTED_DATA_READER')
                     THEN VAL ELSE '***RESTRICTED***' END
            ELSE
                CASE WHEN IS_ROLE_IN_SESSION('HIGHLY_RESTRICTED_DATA_READER')
                     THEN VAL ELSE '***HIGHLY RESTRICTED***' END
        END
    END
COMMENT = 'Enterprise masking policy for STRING columns. Attached to the DATA_CLASSIFICATION tag.';

-- =============================================================================
-- NUMBER
-- =============================================================================
-- Numeric masking must return a number, so redaction is expressed as NULL or as
-- a bucketed value rather than a literal. Returning 0 was rejected deliberately:
-- a masked 0 is indistinguishable from a real 0 and corrupts every aggregate
-- built on the column.
CREATE MASKING POLICY IF NOT EXISTS MP_ENTERPRISE_NUMBER
AS (VAL NUMBER) RETURNS NUMBER ->
    CASE
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PCI'), 'NO') = 'YES'
            THEN CASE WHEN IS_ROLE_IN_SESSION('PCI_UNMASKED') THEN VAL ELSE NULL END
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PHI'), 'NO') = 'YES'
            THEN CASE WHEN IS_ROLE_IN_SESSION('PHI_UNMASKED') THEN VAL ELSE NULL END
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PII'), 'NO') = 'YES'
            THEN CASE
                WHEN IS_ROLE_IN_SESSION('PII_UNMASKED') THEN VAL
                -- Order-preserving coarsening: analysts keep distribution shape
                -- without individual values.
                WHEN IS_ROLE_IN_SESSION('PSEUDONYM_ANALYST') THEN ROUND(VAL, -2)
                ELSE NULL
            END
        ELSE CASE COALESCE(
                SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.DATA_CLASSIFICATION'),
                'RESTRICTED')
            WHEN 'PUBLIC'       THEN VAL
            WHEN 'INTERNAL'     THEN VAL
            WHEN 'CONFIDENTIAL' THEN VAL
            WHEN 'RESTRICTED'   THEN
                CASE WHEN IS_ROLE_IN_SESSION('RESTRICTED_DATA_READER') THEN VAL ELSE NULL END
            ELSE
                CASE WHEN IS_ROLE_IN_SESSION('HIGHLY_RESTRICTED_DATA_READER') THEN VAL ELSE NULL END
        END
    END
COMMENT = 'Enterprise masking policy for NUMBER columns. Masks to NULL, never to 0.';

-- =============================================================================
-- DATE
-- =============================================================================
-- Dates are generalised rather than nulled. A date of birth truncated to the
-- year is still analytically useful and is no longer a HIPAA Safe Harbor
-- identifier for the great majority of the population.
CREATE MASKING POLICY IF NOT EXISTS MP_ENTERPRISE_DATE
AS (VAL DATE) RETURNS DATE ->
    CASE
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PHI'), 'NO') = 'YES'
            THEN CASE
                WHEN IS_ROLE_IN_SESSION('PHI_UNMASKED') THEN VAL
                ELSE DATE_TRUNC('YEAR', VAL)
            END
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PII'), 'NO') = 'YES'
            THEN CASE
                WHEN IS_ROLE_IN_SESSION('PII_UNMASKED') THEN VAL
                WHEN IS_ROLE_IN_SESSION('PSEUDONYM_ANALYST') THEN DATE_TRUNC('MONTH', VAL)
                ELSE DATE_TRUNC('YEAR', VAL)
            END
        ELSE CASE COALESCE(
                SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.DATA_CLASSIFICATION'),
                'RESTRICTED')
            WHEN 'PUBLIC'       THEN VAL
            WHEN 'INTERNAL'     THEN VAL
            WHEN 'CONFIDENTIAL' THEN VAL
            WHEN 'RESTRICTED'   THEN
                CASE WHEN IS_ROLE_IN_SESSION('RESTRICTED_DATA_READER')
                     THEN VAL ELSE DATE_TRUNC('MONTH', VAL) END
            ELSE
                CASE WHEN IS_ROLE_IN_SESSION('HIGHLY_RESTRICTED_DATA_READER')
                     THEN VAL ELSE NULL END
        END
    END
COMMENT = 'Enterprise masking policy for DATE columns. Generalises rather than nulls where possible.';

-- =============================================================================
-- TIMESTAMP_NTZ
-- =============================================================================
CREATE MASKING POLICY IF NOT EXISTS MP_ENTERPRISE_TIMESTAMP_NTZ
AS (VAL TIMESTAMP_NTZ) RETURNS TIMESTAMP_NTZ ->
    CASE
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PHI'), 'NO') = 'YES'
            THEN CASE WHEN IS_ROLE_IN_SESSION('PHI_UNMASKED')
                      THEN VAL ELSE DATE_TRUNC('DAY', VAL) END
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PII'), 'NO') = 'YES'
            THEN CASE
                WHEN IS_ROLE_IN_SESSION('PII_UNMASKED') THEN VAL
                -- Hour truncation defeats timing-based re-identification while
                -- preserving intra-day behavioural analysis.
                ELSE DATE_TRUNC('HOUR', VAL)
            END
        ELSE CASE COALESCE(
                SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.DATA_CLASSIFICATION'),
                'RESTRICTED')
            WHEN 'PUBLIC'       THEN VAL
            WHEN 'INTERNAL'     THEN VAL
            WHEN 'CONFIDENTIAL' THEN VAL
            WHEN 'RESTRICTED'   THEN
                CASE WHEN IS_ROLE_IN_SESSION('RESTRICTED_DATA_READER')
                     THEN VAL ELSE DATE_TRUNC('DAY', VAL) END
            ELSE
                CASE WHEN IS_ROLE_IN_SESSION('HIGHLY_RESTRICTED_DATA_READER')
                     THEN VAL ELSE NULL END
        END
    END
COMMENT = 'Enterprise masking policy for TIMESTAMP_NTZ columns.';

-- =============================================================================
-- VARIANT
-- =============================================================================
-- Semi-structured columns are the most common tagging blind spot: a single
-- VARIANT can hide every category of regulated data inside it, and no column
-- name reveals it. The policy therefore treats any privacy-flagged VARIANT as
-- all-or-nothing - selective redaction of unknown JSON shapes cannot be assured.
CREATE MASKING POLICY IF NOT EXISTS MP_ENTERPRISE_VARIANT
AS (VAL VARIANT) RETURNS VARIANT ->
    CASE
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PCI'), 'NO') = 'YES'
            THEN CASE WHEN IS_ROLE_IN_SESSION('PCI_UNMASKED')
                      THEN VAL ELSE TO_VARIANT('***PCI REDACTED***') END
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PHI'), 'NO') = 'YES'
            THEN CASE WHEN IS_ROLE_IN_SESSION('PHI_UNMASKED')
                      THEN VAL ELSE TO_VARIANT('***PHI REDACTED***') END
        WHEN COALESCE(SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.PII'), 'NO') = 'YES'
            THEN CASE WHEN IS_ROLE_IN_SESSION('PII_UNMASKED')
                      THEN VAL ELSE TO_VARIANT('***MASKED***') END
        ELSE CASE COALESCE(
                SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.TAGS.DATA_CLASSIFICATION'),
                'RESTRICTED')
            WHEN 'PUBLIC'       THEN VAL
            WHEN 'INTERNAL'     THEN VAL
            WHEN 'CONFIDENTIAL' THEN VAL
            WHEN 'RESTRICTED'   THEN
                CASE WHEN IS_ROLE_IN_SESSION('RESTRICTED_DATA_READER')
                     THEN VAL ELSE TO_VARIANT('***RESTRICTED***') END
            ELSE
                CASE WHEN IS_ROLE_IN_SESSION('HIGHLY_RESTRICTED_DATA_READER')
                     THEN VAL ELSE TO_VARIANT('***HIGHLY RESTRICTED***') END
        END
    END
COMMENT = 'Enterprise masking policy for VARIANT columns. All-or-nothing: partial redaction of unknown JSON cannot be assured.';

SELECT 'Masking policies ready' AS status;
