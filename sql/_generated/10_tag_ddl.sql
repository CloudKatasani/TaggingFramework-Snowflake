-- =========================================================================
-- GENERATED FILE - DO NOT EDIT.
-- Source : config/tag_catalog.yaml
-- Rebuild: make build   (scripts/generate_sql.py)
-- CI fails if this file differs from a fresh generation.
-- =========================================================================


-- -----------------------------------------------------------------------------
-- Enterprise tag object DDL
-- -----------------------------------------------------------------------------
-- WARNING: never use CREATE OR REPLACE TAG on a live account. Replacing a tag
-- DROPS every assignment of it across the estate, silently detaching any masking
-- policy bound to it. This file therefore only ever uses CREATE TAG IF NOT
-- EXISTS plus ALTER TAG, which are safe to re-run against a populated account.
--
-- Vocabulary changes: ADD ALLOWED_VALUES is additive and safe. REMOVING a value
-- is a breaking change - Snowflake rejects DROP ALLOWED_VALUES while any object
-- still carries that value, so run the retirement playbook first
-- (docs/08-enterprise-standards.md#tag-retirement-process).
-- -----------------------------------------------------------------------------

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA TAGS;


-- ===========================================================================
-- TIER 1 - CORE MANDATORY  (17 tags)
-- ===========================================================================

-- BUSINESS_UNIT (Tier 1, business) - owner EDGO
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.BUSINESS_UNIT
    COMMENT = 'Top-level legal/reporting entity accountable for the object. Anchors cost allocation, access boundaries and regulatory jurisdiction.';
ALTER TAG GOVERNANCE.TAGS.BUSINESS_UNIT SET COMMENT = 'Top-level legal/reporting entity accountable for the object. Anchors cost allocation, access boundaries and regulatory jurisdiction.';

-- DOMAIN (Tier 1, business) - owner EDGO
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DOMAIN
    COMMENT = 'Data Mesh domain that owns the object (e.g. CUSTOMER, FINANCE, SUPPLY_CHAIN). The unit of federated governance and of data-product publication.';
ALTER TAG GOVERNANCE.TAGS.DOMAIN SET COMMENT = 'Data Mesh domain that owns the object (e.g. CUSTOMER, FINANCE, SUPPLY_CHAIN). The unit of federated governance and of data-product publication.';

-- DATA_PRODUCT (Tier 1, business) - owner DOMAIN_COUNCIL
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_PRODUCT
    COMMENT = 'Named, versioned, independently consumable data product. In this framework a data product maps 1:1 to a schema (the publication boundary).';
ALTER TAG GOVERNANCE.TAGS.DATA_PRODUCT SET COMMENT = 'Named, versioned, independently consumable data product. In this framework a data product maps 1:1 to a schema (the publication boundary).';

-- DATA_OWNER (Tier 1, ownership) - owner EDGO
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_OWNER
    COMMENT = 'Accountable business owner (RACI ''A'') for the data. Named individual or enterprise group. Approves access, classification and retention decisions.';
ALTER TAG GOVERNANCE.TAGS.DATA_OWNER SET COMMENT = 'Accountable business owner (RACI ''A'') for the data. Named individual or enterprise group. Approves access, classification and retention decisions.';

-- DATA_STEWARD (Tier 1, ownership) - owner EDGO
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_STEWARD
    COMMENT = 'Responsible steward (RACI ''R'') executing day-to-day governance: tagging, classification review, quality remediation, metadata curation.';
ALTER TAG GOVERNANCE.TAGS.DATA_STEWARD SET COMMENT = 'Responsible steward (RACI ''R'') executing day-to-day governance: tagging, classification review, quality remediation, metadata curation.';

-- SUPPORT_GROUP (Tier 1, ownership) - owner PLATFORM_ENGINEERING
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SUPPORT_GROUP
    COMMENT = 'Operational on-call group that owns break/fix for the object. Must resolve to a real queue in the enterprise ITSM tool.';
ALTER TAG GOVERNANCE.TAGS.SUPPORT_GROUP SET COMMENT = 'Operational on-call group that owns break/fix for the object. Must resolve to a real queue in the enterprise ITSM tool.';

-- DATA_CLASSIFICATION (Tier 1, classification) - owner CISO_DATA_SECURITY
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_CLASSIFICATION
    ALLOWED_VALUES 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED', 'HIGHLY_RESTRICTED'
    COMMENT = 'Enterprise confidentiality level. The primary driver of masking, sharing eligibility and export controls. Most restrictive value in the lineage wins.';
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION ADD ALLOWED_VALUES 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED', 'HIGHLY_RESTRICTED';
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION SET COMMENT = 'Enterprise confidentiality level. The primary driver of masking, sharing eligibility and export controls. Most restrictive value in the lineage wins.';

-- PII (Tier 1, privacy) - owner PRIVACY_OFFICE
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PII
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Object contains Personally Identifiable Information as defined by the enterprise privacy standard. Set automatically at column level by the Snowflake classification reconciliation job; human-overridable with reason.';
ALTER TAG GOVERNANCE.TAGS.PII ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.PII SET COMMENT = 'Object contains Personally Identifiable Information as defined by the enterprise privacy standard. Set automatically at column level by the Snowflake classification reconciliation job; human-overridable with reason.';

-- ENVIRONMENT (Tier 1, lifecycle) - owner PLATFORM_ENGINEERING
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.ENVIRONMENT
    ALLOWED_VALUES 'DEV', 'TEST', 'UAT', 'PROD', 'SANDBOX', 'DR'
    COMMENT = 'Deployment environment of the object. Never inherited across a clone into a different environment - the clone-remediation task rewrites it.';
ALTER TAG GOVERNANCE.TAGS.ENVIRONMENT ADD ALLOWED_VALUES 'DEV', 'TEST', 'UAT', 'PROD', 'SANDBOX', 'DR';
ALTER TAG GOVERNANCE.TAGS.ENVIRONMENT SET COMMENT = 'Deployment environment of the object. Never inherited across a clone into a different environment - the clone-remediation task rewrites it.';

-- DATA_LIFECYCLE (Tier 1, lifecycle) - owner EDGO
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_LIFECYCLE
    ALLOWED_VALUES 'ACTIVE', 'DEPRECATED', 'ARCHIVED', 'PENDING_PURGE'
    COMMENT = 'Lifecycle state of the object itself. Drives deprecation comms, consumer warnings and the automated archive/purge pipeline.';
ALTER TAG GOVERNANCE.TAGS.DATA_LIFECYCLE ADD ALLOWED_VALUES 'ACTIVE', 'DEPRECATED', 'ARCHIVED', 'PENDING_PURGE';
ALTER TAG GOVERNANCE.TAGS.DATA_LIFECYCLE SET COMMENT = 'Lifecycle state of the object itself. Drives deprecation comms, consumer warnings and the automated archive/purge pipeline.';

-- CRITICALITY (Tier 1, lifecycle) - owner PLATFORM_ENGINEERING
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.CRITICALITY
    ALLOWED_VALUES 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
    COMMENT = 'Business impact if the object is unavailable or incorrect. Drives DR scope, monitoring depth, change-control rigour and incident severity.';
ALTER TAG GOVERNANCE.TAGS.CRITICALITY ADD ALLOWED_VALUES 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL';
ALTER TAG GOVERNANCE.TAGS.CRITICALITY SET COMMENT = 'Business impact if the object is unavailable or incorrect. Drives DR scope, monitoring depth, change-control rigour and incident severity.';

-- COST_CENTER (Tier 1, financial) - owner FINANCE_FINOPS
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.COST_CENTER
    COMMENT = 'GL cost centre charged for the compute and storage attributed to the object. Must exist and be open in the ERP chart of accounts.';
ALTER TAG GOVERNANCE.TAGS.COST_CENTER SET COMMENT = 'GL cost centre charged for the compute and storage attributed to the object. Must exist and be open in the ERP chart of accounts.';

-- RETENTION_CLASS (Tier 1, compliance) - owner RECORDS_MANAGEMENT
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.RETENTION_CLASS
    ALLOWED_VALUES 'TRANSIENT_30D', 'SHORT_1Y', 'STANDARD_3Y', 'EXTENDED_7Y', 'REGULATORY_10Y', 'PERMANENT', 'INDEFINITE_REVIEW'
    COMMENT = 'Records-management retention class from the enterprise retention schedule. Drives the automated archive/purge pipeline. LEGAL_HOLD always supersedes.';
ALTER TAG GOVERNANCE.TAGS.RETENTION_CLASS ADD ALLOWED_VALUES 'TRANSIENT_30D', 'SHORT_1Y', 'STANDARD_3Y', 'EXTENDED_7Y', 'REGULATORY_10Y', 'PERMANENT', 'INDEFINITE_REVIEW';
ALTER TAG GOVERNANCE.TAGS.RETENTION_CLASS SET COMMENT = 'Records-management retention class from the enterprise retention schedule. Drives the automated archive/purge pipeline. LEGAL_HOLD always supersedes.';

-- REGULATION (Tier 1, compliance) - owner COMPLIANCE_OFFICE
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.REGULATION
    ALLOWED_VALUES 'NONE', 'SOX', 'GDPR', 'CCPA', 'HIPAA', 'PCI_DSS', 'GLBA', 'FERPA', 'LGPD', 'PIPEDA', 'PDPA', 'MULTI'
    COMMENT = 'The GOVERNING regulatory regime - the single regime whose controls are the most stringent for this object, resolved by documented precedence. The full multi-regime scope lives in CONTROL.REGULATORY_SCOPE (Snowflake tags are single-valued); see docs/02-tag-taxonomy.md#multi-valued-attributes.';
ALTER TAG GOVERNANCE.TAGS.REGULATION ADD ALLOWED_VALUES 'NONE', 'SOX', 'GDPR', 'CCPA', 'HIPAA', 'PCI_DSS', 'GLBA', 'FERPA', 'LGPD', 'PIPEDA', 'PDPA', 'MULTI';
ALTER TAG GOVERNANCE.TAGS.REGULATION SET COMMENT = 'The GOVERNING regulatory regime - the single regime whose controls are the most stringent for this object, resolved by documented precedence. The full multi-regime scope lives in CONTROL.REGULATORY_SCOPE (Snowflake tags are single-valued); see docs/02-tag-taxonomy.md#multi-valued-attributes.';

-- MASKING_REQUIRED (Tier 1, security) - owner CISO_DATA_SECURITY
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.MASKING_REQUIRED
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Declares that the column must carry a masking policy. This is the DECLARED INTENT; SNOWFLAKE.CORE tag-based masking attachment is the ENFORCEMENT. The drift detector reconciles the two and raises on divergence.';
ALTER TAG GOVERNANCE.TAGS.MASKING_REQUIRED ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.MASKING_REQUIRED SET COMMENT = 'Declares that the column must carry a masking policy. This is the DECLARED INTENT; SNOWFLAKE.CORE tag-based masking attachment is the ENFORCEMENT. The drift detector reconciles the two and raises on divergence.';

-- ROW_ACCESS_REQUIRED (Tier 1, security) - owner CISO_DATA_SECURITY
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.ROW_ACCESS_REQUIRED
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Declares that the table/view must carry a row access policy. Snowflake does NOT support attaching row access policies to tags, so enforcement is via the SP_APPLY_ROW_ACCESS_POLICIES reconciliation task, not tag attachment.';
ALTER TAG GOVERNANCE.TAGS.ROW_ACCESS_REQUIRED ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.ROW_ACCESS_REQUIRED SET COMMENT = 'Declares that the table/view must carry a row access policy. Snowflake does NOT support attaching row access policies to tags, so enforcement is via the SP_APPLY_ROW_ACCESS_POLICIES reconciliation task, not tag attachment.';

-- SLA_TIER (Tier 1, operational) - owner PLATFORM_ENGINEERING
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SLA_TIER
    ALLOWED_VALUES 'PLATINUM_15M', 'GOLD_1H', 'SILVER_4H', 'BRONZE_24H', 'BEST_EFFORT'
    COMMENT = 'Freshness/availability commitment published to consumers of the data product. Drives monitoring thresholds, alert routing and DR tiering.';
ALTER TAG GOVERNANCE.TAGS.SLA_TIER ADD ALLOWED_VALUES 'PLATINUM_15M', 'GOLD_1H', 'SILVER_4H', 'BRONZE_24H', 'BEST_EFFORT';
ALTER TAG GOVERNANCE.TAGS.SLA_TIER SET COMMENT = 'Freshness/availability commitment published to consumers of the data product. Drives monitoring thresholds, alert routing and DR tiering.';


-- ===========================================================================
-- TIER 2 - GOVERNANCE  (14 tags)
-- ===========================================================================

-- SUB_DOMAIN (Tier 2, business) - owner DOMAIN_COUNCIL
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SUB_DOMAIN
    COMMENT = 'Second-level decomposition of DOMAIN, for large domains only.';
ALTER TAG GOVERNANCE.TAGS.SUB_DOMAIN SET COMMENT = 'Second-level decomposition of DOMAIN, for large domains only.';

-- APPLICATION (Tier 2, business) - owner ENTERPRISE_ARCHITECTURE
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.APPLICATION
    COMMENT = 'CMDB application identifier of the producing or consuming system. Enables impact analysis between Snowflake objects and the application portfolio.';
ALTER TAG GOVERNANCE.TAGS.APPLICATION SET COMMENT = 'CMDB application identifier of the producing or consuming system. Enables impact analysis between Snowflake objects and the application portfolio.';

-- APPLICATION_OWNER (Tier 2, ownership) - owner ENTERPRISE_ARCHITECTURE
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.APPLICATION_OWNER
    COMMENT = 'Accountable owner of the APPLICATION referenced by the object.';
ALTER TAG GOVERNANCE.TAGS.APPLICATION_OWNER SET COMMENT = 'Accountable owner of the APPLICATION referenced by the object.';

-- PLATFORM_OWNER (Tier 2, ownership) - owner PLATFORM_ENGINEERING
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PLATFORM_OWNER
    COMMENT = 'Platform engineering team accountable for the Snowflake infrastructure object (warehouse, integration, share, account-level construct).';
ALTER TAG GOVERNANCE.TAGS.PLATFORM_OWNER SET COMMENT = 'Platform engineering team accountable for the Snowflake infrastructure object (warehouse, integration, share, account-level construct).';

-- DOMAIN_OWNER (Tier 2, data_mesh) - owner DOMAIN_COUNCIL
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DOMAIN_OWNER
    COMMENT = 'Accountable owner of the mesh DOMAIN. Normally set once on the domain''s database and inherited; a per-object override is an exception.';
ALTER TAG GOVERNANCE.TAGS.DOMAIN_OWNER SET COMMENT = 'Accountable owner of the mesh DOMAIN. Normally set once on the domain''s database and inherited; a per-object override is an exception.';

-- DATA_PRODUCT_OWNER (Tier 2, data_mesh) - owner DOMAIN_COUNCIL
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_PRODUCT_OWNER
    COMMENT = 'Product owner accountable for the data product''s roadmap, SLA and consumer contract. Distinct from DATA_OWNER (who is accountable for the data itself).';
ALTER TAG GOVERNANCE.TAGS.DATA_PRODUCT_OWNER SET COMMENT = 'Product owner accountable for the data product''s roadmap, SLA and consumer contract. Distinct from DATA_OWNER (who is accountable for the data itself).';

-- DATA_PRODUCT_TYPE (Tier 2, data_mesh) - owner DOMAIN_COUNCIL
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_PRODUCT_TYPE
    ALLOWED_VALUES 'SOURCE_ALIGNED', 'AGGREGATE', 'CONSUMER_ALIGNED', 'SHARED', 'PLATFORM'
    COMMENT = 'Mesh archetype of the data product; sets default quality and SLA expectations.';
ALTER TAG GOVERNANCE.TAGS.DATA_PRODUCT_TYPE ADD ALLOWED_VALUES 'SOURCE_ALIGNED', 'AGGREGATE', 'CONSUMER_ALIGNED', 'SHARED', 'PLATFORM';
ALTER TAG GOVERNANCE.TAGS.DATA_PRODUCT_TYPE SET COMMENT = 'Mesh archetype of the data product; sets default quality and SLA expectations.';

-- PHI (Tier 2, privacy) - owner PRIVACY_OFFICE
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PHI
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Protected Health Information under HIPAA. Conditionally MANDATORY wherever REGULATION resolves to HIPAA. Drives the HIPAA masking policy set.';
ALTER TAG GOVERNANCE.TAGS.PHI ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.PHI SET COMMENT = 'Protected Health Information under HIPAA. Conditionally MANDATORY wherever REGULATION resolves to HIPAA. Drives the HIPAA masking policy set.';

-- PCI (Tier 2, privacy) - owner CISO_DATA_SECURITY
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PCI
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Cardholder data in PCI-DSS scope. Conditionally MANDATORY wherever REGULATION resolves to PCI_DSS. Drives tokenisation/masking and CDE scoping.';
ALTER TAG GOVERNANCE.TAGS.PCI ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.PCI SET COMMENT = 'Cardholder data in PCI-DSS scope. Conditionally MANDATORY wherever REGULATION resolves to PCI_DSS. Drives tokenisation/masking and CDE scoping.';

-- LEGAL_HOLD (Tier 2, compliance) - owner LEGAL
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.LEGAL_HOLD
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Litigation hold. When YES, all retention-driven archive and purge automation is suppressed regardless of RETENTION_CLASS. Set only by Legal.';
ALTER TAG GOVERNANCE.TAGS.LEGAL_HOLD ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.LEGAL_HOLD SET COMMENT = 'Litigation hold. When YES, all retention-driven archive and purge automation is suppressed regardless of RETENTION_CLASS. Set only by Legal.';

-- ENCRYPTION_REQUIRED (Tier 2, security) - owner CISO_DATA_SECURITY
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.ENCRYPTION_REQUIRED
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Declares that application-layer or client-side encryption is required in addition to Snowflake''s transparent encryption at rest. Applies mainly to external stages and to columns holding secrets or key material.';
ALTER TAG GOVERNANCE.TAGS.ENCRYPTION_REQUIRED ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.ENCRYPTION_REQUIRED SET COMMENT = 'Declares that application-layer or client-side encryption is required in addition to Snowflake''s transparent encryption at rest. Applies mainly to external stages and to columns holding secrets or key material.';

-- DATA_QUALITY_TIER (Tier 2, data_quality) - owner EDGO
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_QUALITY_TIER
    ALLOWED_VALUES 'BRONZE', 'SILVER', 'GOLD', 'PLATINUM'
    COMMENT = 'Certified quality level of the object. Set only by the data-quality pipeline after DMF results are evaluated; manual promotion requires an exception.';
ALTER TAG GOVERNANCE.TAGS.DATA_QUALITY_TIER ADD ALLOWED_VALUES 'BRONZE', 'SILVER', 'GOLD', 'PLATINUM';
ALTER TAG GOVERNANCE.TAGS.DATA_QUALITY_TIER SET COMMENT = 'Certified quality level of the object. Set only by the data-quality pipeline after DMF results are evaluated; manual promotion requires an exception.';

-- REFRESH_TYPE (Tier 2, operational) - owner PLATFORM_ENGINEERING
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.REFRESH_TYPE
    ALLOWED_VALUES 'STREAMING', 'MICRO_BATCH', 'BATCH_HOURLY', 'BATCH_DAILY', 'BATCH_WEEKLY', 'BATCH_MONTHLY', 'ON_DEMAND', 'STATIC'
    COMMENT = 'How the object''s data is refreshed. Drives freshness monitoring logic.';
ALTER TAG GOVERNANCE.TAGS.REFRESH_TYPE ADD ALLOWED_VALUES 'STREAMING', 'MICRO_BATCH', 'BATCH_HOURLY', 'BATCH_DAILY', 'BATCH_WEEKLY', 'BATCH_MONTHLY', 'ON_DEMAND', 'STATIC';
ALTER TAG GOVERNANCE.TAGS.REFRESH_TYPE SET COMMENT = 'How the object''s data is refreshed. Drives freshness monitoring logic.';

-- PROJECT_CODE (Tier 2, financial) - owner FINANCE_FINOPS
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PROJECT_CODE
    COMMENT = 'Capital or programme project funding the workload. Enables project-level cost attribution separate from the steady-state COST_CENTER.';
ALTER TAG GOVERNANCE.TAGS.PROJECT_CODE SET COMMENT = 'Capital or programme project funding the workload. Enables project-level cost attribution separate from the steady-state COST_CENTER.';


-- ===========================================================================
-- TIER 3 - OPTIONAL / DOMAIN  (11 tags)
-- ===========================================================================

-- CAPABILITY (Tier 3, business) - owner ENTERPRISE_ARCHITECTURE
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.CAPABILITY
    COMMENT = 'Business capability from the enterprise capability model (L2).';
ALTER TAG GOVERNANCE.TAGS.CAPABILITY SET COMMENT = 'Business capability from the enterprise capability model (L2).';

-- SOURCE_SYSTEM (Tier 3, business) - owner DOMAIN_COUNCIL
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SOURCE_SYSTEM
    COMMENT = 'System of record from which the data originates. Supports lineage rooting.';
ALTER TAG GOVERNANCE.TAGS.SOURCE_SYSTEM SET COMMENT = 'System of record from which the data originates. Supports lineage rooting.';

-- DATA_RESIDENCY (Tier 3, compliance) - owner COMPLIANCE_OFFICE
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_RESIDENCY
    ALLOWED_VALUES 'GLOBAL', 'US', 'EU', 'UK', 'APAC', 'CANADA', 'LATAM', 'CHINA', 'INDIA', 'JAPAN', 'AUSTRALIA'
    COMMENT = 'ISO-3166 region in which the data must remain. Drives replication and cross-region share eligibility checks.';
ALTER TAG GOVERNANCE.TAGS.DATA_RESIDENCY ADD ALLOWED_VALUES 'GLOBAL', 'US', 'EU', 'UK', 'APAC', 'CANADA', 'LATAM', 'CHINA', 'INDIA', 'JAPAN', 'AUSTRALIA';
ALTER TAG GOVERNANCE.TAGS.DATA_RESIDENCY SET COMMENT = 'ISO-3166 region in which the data must remain. Drives replication and cross-region share eligibility checks.';

-- SENSITIVE_DATA (Tier 3, privacy) - owner PRIVACY_OFFICE
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SENSITIVE_DATA
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Special-category / sensitive data beyond PII (e.g. biometric, union membership, religion, sexual orientation) per GDPR Art. 9.';
ALTER TAG GOVERNANCE.TAGS.SENSITIVE_DATA ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.SENSITIVE_DATA SET COMMENT = 'Special-category / sensitive data beyond PII (e.g. biometric, union membership, religion, sexual orientation) per GDPR Art. 9.';

-- PROGRAM (Tier 3, financial) - owner FINANCE_FINOPS
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PROGRAM
    COMMENT = 'Multi-project programme rollup for executive cost reporting.';
ALTER TAG GOVERNANCE.TAGS.PROGRAM SET COMMENT = 'Multi-project programme rollup for executive cost reporting.';

-- PRODUCT_CODE (Tier 3, financial) - owner FINANCE_FINOPS
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PRODUCT_CODE
    COMMENT = 'Commercial product/SKU whose P&L the workload supports.';
ALTER TAG GOVERNANCE.TAGS.PRODUCT_CODE SET COMMENT = 'Commercial product/SKU whose P&L the workload supports.';

-- PRODUCT_OWNER (Tier 3, ownership) - owner FINANCE_FINOPS
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PRODUCT_OWNER
    COMMENT = 'Commercial owner of the PRODUCT_CODE. Distinct from DATA_PRODUCT_OWNER.';
ALTER TAG GOVERNANCE.TAGS.PRODUCT_OWNER SET COMMENT = 'Commercial owner of the PRODUCT_CODE. Distinct from DATA_PRODUCT_OWNER.';

-- RPO (Tier 3, operational) - owner PLATFORM_ENGINEERING
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.RPO
    COMMENT = 'Recovery Point Objective as an ISO-8601 duration (e.g. PT15M, P1D).';
ALTER TAG GOVERNANCE.TAGS.RPO SET COMMENT = 'Recovery Point Objective as an ISO-8601 duration (e.g. PT15M, P1D).';

-- RTO (Tier 3, operational) - owner PLATFORM_ENGINEERING
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.RTO
    COMMENT = 'Recovery Time Objective as an ISO-8601 duration (e.g. PT4H, P1D).';
ALTER TAG GOVERNANCE.TAGS.RTO SET COMMENT = 'Recovery Time Objective as an ISO-8601 duration (e.g. PT4H, P1D).';

-- SHARING_SCOPE (Tier 3, security) - owner CISO_DATA_SECURITY
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SHARING_SCOPE
    ALLOWED_VALUES 'INTERNAL_ONLY', 'AFFILIATE', 'PARTNER', 'PUBLIC_MARKETPLACE', 'PROHIBITED'
    COMMENT = 'Maximum permitted distribution of the object. Checked before any listing, share or reader-account grant is created.';
ALTER TAG GOVERNANCE.TAGS.SHARING_SCOPE ADD ALLOWED_VALUES 'INTERNAL_ONLY', 'AFFILIATE', 'PARTNER', 'PUBLIC_MARKETPLACE', 'PROHIBITED';
ALTER TAG GOVERNANCE.TAGS.SHARING_SCOPE SET COMMENT = 'Maximum permitted distribution of the object. Checked before any listing, share or reader-account grant is created.';

-- COST_ALLOCATION_MODEL (Tier 3, financial) - owner FINANCE_FINOPS
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.COST_ALLOCATION_MODEL
    ALLOWED_VALUES 'SHOWBACK', 'CHARGEBACK', 'SHARED_SERVICE', 'ABSORBED_PLATFORM'
    COMMENT = 'How this object''s consumption is settled with the business. SHOWBACK reports only; CHARGEBACK posts a journal entry to the ERP.';
ALTER TAG GOVERNANCE.TAGS.COST_ALLOCATION_MODEL ADD ALLOWED_VALUES 'SHOWBACK', 'CHARGEBACK', 'SHARED_SERVICE', 'ABSORBED_PLATFORM';
ALTER TAG GOVERNANCE.TAGS.COST_ALLOCATION_MODEL SET COMMENT = 'How this object''s consumption is settled with the business. SHOWBACK reports only; CHARGEBACK posts a journal entry to the ERP.';

SELECT 'Tag DDL applied' AS status;
