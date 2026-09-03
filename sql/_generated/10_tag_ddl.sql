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
-- TIER 1 - CORE MANDATORY  (10 tags)
-- ===========================================================================

-- operating_company  ->  Snowflake identifier OPERATING_COMPANY
-- Tier 1 | Operating Company | business | owner FINANCE_FINOPS | platforms: AWS, SNOWFLAKE, DENODO, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.OPERATING_COMPANY
    ALLOWED_VALUES 'OPCO_AEP_OHIO', 'OPCO_AEP_TEXAS', 'OPCO_APPALACHIAN', 'OPCO_AEP_INDIANA_MICHIGAN', 'OPCO_KENTUCKY_POWER', 'OPCO_PSC_OKLAHOMA', 'OPCO_SEPC', 'SHARED'
    COMMENT = 'Top-level legal and financial entity for chargeback and consolidation. The consolidation boundary for every cost report and the outermost jurisdiction boundary for data residency.';
ALTER TAG GOVERNANCE.TAGS.OPERATING_COMPANY ADD ALLOWED_VALUES 'OPCO_AEP_OHIO', 'OPCO_AEP_TEXAS', 'OPCO_APPALACHIAN', 'OPCO_AEP_INDIANA_MICHIGAN', 'OPCO_KENTUCKY_POWER', 'OPCO_PSC_OKLAHOMA', 'OPCO_SEPC', 'SHARED';
ALTER TAG GOVERNANCE.TAGS.OPERATING_COMPANY SET COMMENT = 'Top-level legal and financial entity for chargeback and consolidation. The consolidation boundary for every cost report and the outermost jurisdiction boundary for data residency.';

-- department  ->  Snowflake identifier DEPARTMENT
-- Tier 1 | Department | business | owner FINANCE_FINOPS | platforms: AWS, SNOWFLAKE, DENODO, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DEPARTMENT
    ALLOWED_VALUES 'FINANCE', 'HR', 'MARKETING', 'DISTRIBUTION', 'GENERATION', 'COMOPS', 'GIS', 'CORPORATE', 'CUSTOMER', 'SHARED_SERVICES'
    COMMENT = 'Business unit or cost centre within the operating company. The level at which departmental cost reports are produced and budgets are owned.';
ALTER TAG GOVERNANCE.TAGS.DEPARTMENT ADD ALLOWED_VALUES 'FINANCE', 'HR', 'MARKETING', 'DISTRIBUTION', 'GENERATION', 'COMOPS', 'GIS', 'CORPORATE', 'CUSTOMER', 'SHARED_SERVICES';
ALTER TAG GOVERNANCE.TAGS.DEPARTMENT SET COMMENT = 'Business unit or cost centre within the operating company. The level at which departmental cost reports are produced and budgets are owned.';

-- domain  ->  Snowflake identifier DOMAIN
-- Tier 1 | Data Domain | business | owner EDGO | platforms: AWS, SNOWFLAKE, DENODO, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DOMAIN
    ALLOWED_VALUES 'CUSTOMER', 'LOCATION', 'METER', 'FINANCE', 'SUPPLY_CHAIN', 'MARKETING', 'RISK', 'TELEMETRY'
    COMMENT = 'Logical data domain owning the workload, mesh-style. The unit of federated governance and of data-product publication. Independent of department: one domain routinely serves several departments.';
ALTER TAG GOVERNANCE.TAGS.DOMAIN ADD ALLOWED_VALUES 'CUSTOMER', 'LOCATION', 'METER', 'FINANCE', 'SUPPLY_CHAIN', 'MARKETING', 'RISK', 'TELEMETRY';
ALTER TAG GOVERNANCE.TAGS.DOMAIN SET COMMENT = 'Logical data domain owning the workload, mesh-style. The unit of federated governance and of data-product publication. Independent of department: one domain routinely serves several departments.';

-- team  ->  Snowflake identifier TEAM
-- Tier 1 | Team | ownership | owner PLATFORM_ENGINEERING | platforms: AWS, SNOWFLAKE, DENODO, COLLIBRA
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.TEAM
    COMMENT = 'Engineering team accountable for build and run. Validated against the team registry so a disbanded team cannot keep owning production workloads.';
ALTER TAG GOVERNANCE.TAGS.TEAM SET COMMENT = 'Engineering team accountable for build and run. Validated against the team registry so a disbanded team cannot keep owning production workloads.';

-- application  ->  Snowflake identifier APPLICATION
-- Tier 1 | Application | business | owner ENTERPRISE_ARCHITECTURE | platforms: AWS, SNOWFLAKE, DENODO, COLLIBRA
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.APPLICATION
    COMMENT = 'Discrete application or data product, aligned to the CMDB. The join key between Snowflake objects and the enterprise application portfolio, which is what makes cross-platform impact analysis possible at all.';
ALTER TAG GOVERNANCE.TAGS.APPLICATION SET COMMENT = 'Discrete application or data product, aligned to the CMDB. The join key between Snowflake objects and the enterprise application portfolio, which is what makes cross-platform impact analysis possible at all.';

-- workload_type  ->  Snowflake identifier WORKLOAD_TYPE
-- Tier 1 | Role / Workload Class | operational | owner PLATFORM_ENGINEERING | platforms: AWS, SNOWFLAKE, DENODO
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.WORKLOAD_TYPE
    ALLOWED_VALUES 'INGEST', 'TRANSFORM', 'ANALYTICS', 'ML_TRAIN', 'ML_SERVE', 'BI', 'GOVERNANCE', 'PLATFORM_OPS'
    COMMENT = 'Workload class, for resource-pattern rollups. Lets FinOps compare like with like across the estate - ML training spend against ML training spend, not against BI - and drives right-sizing recommendations per pattern.';
ALTER TAG GOVERNANCE.TAGS.WORKLOAD_TYPE ADD ALLOWED_VALUES 'INGEST', 'TRANSFORM', 'ANALYTICS', 'ML_TRAIN', 'ML_SERVE', 'BI', 'GOVERNANCE', 'PLATFORM_OPS';
ALTER TAG GOVERNANCE.TAGS.WORKLOAD_TYPE SET COMMENT = 'Workload class, for resource-pattern rollups. Lets FinOps compare like with like across the estate - ML training spend against ML training spend, not against BI - and drives right-sizing recommendations per pattern.';

-- owner_user  ->  Snowflake identifier OWNER_USER
-- Tier 1 | Owner / User | ownership | owner EDGO | platforms: AWS, SNOWFLAKE, DENODO, COLLIBRA
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.OWNER_USER
    COMMENT = 'Accountable individual by SSO email, or the named service account that owns an automated workload. Recommended rather than mandatory: an owner tag that is mandated before joiner-mover-leaver feeds are wired up fills with stale names, which is worse than an honest blank.';
ALTER TAG GOVERNANCE.TAGS.OWNER_USER SET COMMENT = 'Accountable individual by SSO email, or the named service account that owns an automated workload. Recommended rather than mandatory: an owner tag that is mandated before joiner-mover-leaver feeds are wired up fills with stale names, which is worse than an honest blank.';

-- environment  ->  Snowflake identifier ENVIRONMENT
-- Tier 1 | Environment | lifecycle | owner PLATFORM_ENGINEERING | platforms: AWS, SNOWFLAKE, DENODO, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.ENVIRONMENT
    ALLOWED_VALUES 'PRD', 'UAT', 'TST', 'DEV', 'TRAINING', 'BACKUP'
    COMMENT = 'Lifecycle stage, required alongside the core tags. Never inherited across a clone into a different environment - the clone-remediation job rewrites it.';
ALTER TAG GOVERNANCE.TAGS.ENVIRONMENT ADD ALLOWED_VALUES 'PRD', 'UAT', 'TST', 'DEV', 'TRAINING', 'BACKUP';
ALTER TAG GOVERNANCE.TAGS.ENVIRONMENT SET COMMENT = 'Lifecycle stage, required alongside the core tags. Never inherited across a clone into a different environment - the clone-remediation job rewrites it.';

-- data_classification_enterprise  ->  Snowflake identifier DATA_CLASSIFICATION_ENTERPRISE
-- Tier 1 | Data Classification | classification | owner CISO_DATA_SECURITY | platforms: AWS, SNOWFLAKE, DENODO, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE
    ALLOWED_VALUES 'NONE', 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED'
    COMMENT = 'Core enterprise confidentiality classification. The only tag carrying masking policy attachments, so it is the anchor of the whole protection model. Most restrictive value in the lineage wins.';
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE ADD ALLOWED_VALUES 'NONE', 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED';
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION_ENTERPRISE SET COMMENT = 'Core enterprise confidentiality classification. The only tag carrying masking policy attachments, so it is the anchor of the whole protection model. Most restrictive value in the lineage wins.';

-- data_classification_regulatory  ->  Snowflake identifier DATA_CLASSIFICATION_REGULATORY
-- Tier 1 | Data Classification | privacy | owner PRIVACY_OFFICE | platforms: AWS, SNOWFLAKE, DENODO, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_CLASSIFICATION_REGULATORY
    ALLOWED_VALUES 'NONE', 'PII', 'SPII', 'PHI', 'PCI'
    COMMENT = 'Regulatory-driven data classification. Holds the GOVERNING category - the one whose technical controls are most prescriptive - resolved by documented precedence. Where several categories apply, the full set is recorded in CONTROL.REGULATORY_SCOPE, because a Snowflake tag holds only one value.';
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION_REGULATORY ADD ALLOWED_VALUES 'NONE', 'PII', 'SPII', 'PHI', 'PCI';
ALTER TAG GOVERNANCE.TAGS.DATA_CLASSIFICATION_REGULATORY SET COMMENT = 'Regulatory-driven data classification. Holds the GOVERNING category - the one whose technical controls are most prescriptive - resolved by documented precedence. Where several categories apply, the full set is recorded in CONTROL.REGULATORY_SCOPE, because a Snowflake tag holds only one value.';


-- ===========================================================================
-- TIER 2 - GOVERNANCE  (15 tags)
-- ===========================================================================

-- data_product  ->  Snowflake identifier DATA_PRODUCT
-- Tier 2 | Data Product | business | owner DOMAIN_COUNCIL | platforms: SNOWFLAKE, DENODO, COLLIBRA
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_PRODUCT
    COMMENT = 'Named, versioned, independently consumable data product. Maps 1:1 to a schema, which is the publication boundary. Distinct from `application`: one application can publish several data products.';
ALTER TAG GOVERNANCE.TAGS.DATA_PRODUCT SET COMMENT = 'Named, versioned, independently consumable data product. Maps 1:1 to a schema, which is the publication boundary. Distinct from `application`: one application can publish several data products.';

-- data_owner  ->  Snowflake identifier DATA_OWNER
-- Tier 2 | Ownership | ownership | owner EDGO | platforms: SNOWFLAKE, DENODO, COLLIBRA
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_OWNER
    COMMENT = 'Accountable business owner (RACI ''A'') for the DATA, as distinct from owner_user who is accountable for the RESOURCE. Approves access, classification and retention decisions.';
ALTER TAG GOVERNANCE.TAGS.DATA_OWNER SET COMMENT = 'Accountable business owner (RACI ''A'') for the DATA, as distinct from owner_user who is accountable for the RESOURCE. Approves access, classification and retention decisions.';

-- data_steward  ->  Snowflake identifier DATA_STEWARD
-- Tier 2 | Ownership | ownership | owner EDGO | platforms: SNOWFLAKE, COLLIBRA
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_STEWARD
    COMMENT = 'Responsible steward (RACI ''R'') executing day-to-day governance: tagging, classification review, quality remediation, metadata curation.';
ALTER TAG GOVERNANCE.TAGS.DATA_STEWARD SET COMMENT = 'Responsible steward (RACI ''R'') executing day-to-day governance: tagging, classification review, quality remediation, metadata curation.';

-- support_group  ->  Snowflake identifier SUPPORT_GROUP
-- Tier 2 | Ownership | ownership | owner PLATFORM_ENGINEERING | platforms: AWS, SNOWFLAKE, DENODO
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SUPPORT_GROUP
    COMMENT = 'ITSM queue that owns break/fix. Complements `team`, which names the accountable engineers; support_group names where the ticket actually lands out of hours.';
ALTER TAG GOVERNANCE.TAGS.SUPPORT_GROUP SET COMMENT = 'ITSM queue that owns break/fix. Complements `team`, which names the accountable engineers; support_group names where the ticket actually lands out of hours.';

-- cost_center  ->  Snowflake identifier COST_CENTER
-- Tier 2 | Financial | financial | owner FINANCE_FINOPS | platforms: AWS, SNOWFLAKE
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.COST_CENTER
    COMMENT = 'GL cost centre code. `department` is the human-facing allocation level; cost_center is the posting key a journal entry actually needs. Required wherever cost_allocation_model is CHARGEBACK.';
ALTER TAG GOVERNANCE.TAGS.COST_CENTER SET COMMENT = 'GL cost centre code. `department` is the human-facing allocation level; cost_center is the posting key a journal entry actually needs. Required wherever cost_allocation_model is CHARGEBACK.';

-- criticality  ->  Snowflake identifier CRITICALITY
-- Tier 2 | Lifecycle | lifecycle | owner PLATFORM_ENGINEERING | platforms: AWS, SNOWFLAKE, DENODO
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.CRITICALITY
    ALLOWED_VALUES 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
    COMMENT = 'Business impact if the object is unavailable or incorrect. Drives DR scope, monitoring depth, change-control rigour and incident severity.';
ALTER TAG GOVERNANCE.TAGS.CRITICALITY ADD ALLOWED_VALUES 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL';
ALTER TAG GOVERNANCE.TAGS.CRITICALITY SET COMMENT = 'Business impact if the object is unavailable or incorrect. Drives DR scope, monitoring depth, change-control rigour and incident severity.';

-- data_lifecycle  ->  Snowflake identifier DATA_LIFECYCLE
-- Tier 2 | Lifecycle | lifecycle | owner EDGO | platforms: SNOWFLAKE, DENODO, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_LIFECYCLE
    ALLOWED_VALUES 'ACTIVE', 'DEPRECATED', 'ARCHIVED', 'PENDING_PURGE'
    COMMENT = 'Lifecycle state of the object itself. Drives deprecation comms, consumer warnings and the automated archive/purge pipeline. Deprecated data nobody deleted is consistently one of the largest recoverable cost lines.';
ALTER TAG GOVERNANCE.TAGS.DATA_LIFECYCLE ADD ALLOWED_VALUES 'ACTIVE', 'DEPRECATED', 'ARCHIVED', 'PENDING_PURGE';
ALTER TAG GOVERNANCE.TAGS.DATA_LIFECYCLE SET COMMENT = 'Lifecycle state of the object itself. Drives deprecation comms, consumer warnings and the automated archive/purge pipeline. Deprecated data nobody deleted is consistently one of the largest recoverable cost lines.';

-- retention_class  ->  Snowflake identifier RETENTION_CLASS
-- Tier 2 | Compliance | compliance | owner RECORDS_MANAGEMENT | platforms: AWS, SNOWFLAKE, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.RETENTION_CLASS
    ALLOWED_VALUES 'TRANSIENT_30D', 'SHORT_1Y', 'STANDARD_3Y', 'EXTENDED_7Y', 'REGULATORY_10Y', 'PERMANENT', 'INDEFINITE_REVIEW'
    COMMENT = 'Records-management retention class from the enterprise retention schedule. Drives the automated archive and purge pipeline. legal_hold always supersedes it.';
ALTER TAG GOVERNANCE.TAGS.RETENTION_CLASS ADD ALLOWED_VALUES 'TRANSIENT_30D', 'SHORT_1Y', 'STANDARD_3Y', 'EXTENDED_7Y', 'REGULATORY_10Y', 'PERMANENT', 'INDEFINITE_REVIEW';
ALTER TAG GOVERNANCE.TAGS.RETENTION_CLASS SET COMMENT = 'Records-management retention class from the enterprise retention schedule. Drives the automated archive and purge pipeline. legal_hold always supersedes it.';

-- legal_hold  ->  Snowflake identifier LEGAL_HOLD
-- Tier 2 | Compliance | compliance | owner LEGAL | platforms: SNOWFLAKE, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.LEGAL_HOLD
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Litigation hold. When YES, all retention-driven archive and purge automation is suppressed regardless of retention_class. Set only by Legal.';
ALTER TAG GOVERNANCE.TAGS.LEGAL_HOLD ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.LEGAL_HOLD SET COMMENT = 'Litigation hold. When YES, all retention-driven archive and purge automation is suppressed regardless of retention_class. Set only by Legal.';

-- regulation  ->  Snowflake identifier REGULATION
-- Tier 2 | Compliance | compliance | owner COMPLIANCE_OFFICE | platforms: SNOWFLAKE, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.REGULATION
    ALLOWED_VALUES 'NONE', 'SOX', 'GDPR', 'CCPA', 'HIPAA', 'PCI_DSS', 'GLBA', 'FERPA', 'NERC_CIP', 'MULTI'
    COMMENT = 'The governing regulatory REGIME, as distinct from data_classification_regulatory which states what the DATA IS. A financial ledger with no personal data at all is still in SOX scope; the two tags answer different questions and are both needed for evidence.';
ALTER TAG GOVERNANCE.TAGS.REGULATION ADD ALLOWED_VALUES 'NONE', 'SOX', 'GDPR', 'CCPA', 'HIPAA', 'PCI_DSS', 'GLBA', 'FERPA', 'NERC_CIP', 'MULTI';
ALTER TAG GOVERNANCE.TAGS.REGULATION SET COMMENT = 'The governing regulatory REGIME, as distinct from data_classification_regulatory which states what the DATA IS. A financial ledger with no personal data at all is still in SOX scope; the two tags answer different questions and are both needed for evidence.';

-- sla_tier  ->  Snowflake identifier SLA_TIER
-- Tier 2 | Operational | operational | owner PLATFORM_ENGINEERING | platforms: SNOWFLAKE, DENODO
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SLA_TIER
    ALLOWED_VALUES 'PLATINUM_15M', 'GOLD_1H', 'SILVER_4H', 'BRONZE_24H', 'BEST_EFFORT'
    COMMENT = 'Freshness and availability commitment published to consumers. Drives monitoring thresholds, alert routing and DR tiering.';
ALTER TAG GOVERNANCE.TAGS.SLA_TIER ADD ALLOWED_VALUES 'PLATINUM_15M', 'GOLD_1H', 'SILVER_4H', 'BRONZE_24H', 'BEST_EFFORT';
ALTER TAG GOVERNANCE.TAGS.SLA_TIER SET COMMENT = 'Freshness and availability commitment published to consumers. Drives monitoring thresholds, alert routing and DR tiering.';

-- masking_required  ->  Snowflake identifier MASKING_REQUIRED
-- Tier 2 | Security | security | owner CISO_DATA_SECURITY | platforms: SNOWFLAKE
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.MASKING_REQUIRED
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Declares that the column must carry a masking policy. This is DECLARED INTENT; the tag-based policy attachment is ENFORCEMENT. The drift detector reconciles the two, and divergence is the finding that matters most.';
ALTER TAG GOVERNANCE.TAGS.MASKING_REQUIRED ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.MASKING_REQUIRED SET COMMENT = 'Declares that the column must carry a masking policy. This is DECLARED INTENT; the tag-based policy attachment is ENFORCEMENT. The drift detector reconciles the two, and divergence is the finding that matters most.';

-- row_access_required  ->  Snowflake identifier ROW_ACCESS_REQUIRED
-- Tier 2 | Security | security | owner CISO_DATA_SECURITY | platforms: SNOWFLAKE
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.ROW_ACCESS_REQUIRED
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Declares that the table or view must carry a row access policy. Snowflake does NOT support attaching row access policies to tags, so enforcement runs through the SP_APPLY_ROW_ACCESS_POLICIES reconciliation task.';
ALTER TAG GOVERNANCE.TAGS.ROW_ACCESS_REQUIRED ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.ROW_ACCESS_REQUIRED SET COMMENT = 'Declares that the table or view must carry a row access policy. Snowflake does NOT support attaching row access policies to tags, so enforcement runs through the SP_APPLY_ROW_ACCESS_POLICIES reconciliation task.';

-- data_residency  ->  Snowflake identifier DATA_RESIDENCY
-- Tier 2 | Compliance | compliance | owner COMPLIANCE_OFFICE | platforms: AWS, SNOWFLAKE, DENODO
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_RESIDENCY
    ALLOWED_VALUES 'US', 'US_EAST', 'US_WEST', 'EU', 'UK', 'CANADA', 'APAC', 'GLOBAL'
    COMMENT = 'Region in which the data must remain. Drives replication scope and cross-region share eligibility.';
ALTER TAG GOVERNANCE.TAGS.DATA_RESIDENCY ADD ALLOWED_VALUES 'US', 'US_EAST', 'US_WEST', 'EU', 'UK', 'CANADA', 'APAC', 'GLOBAL';
ALTER TAG GOVERNANCE.TAGS.DATA_RESIDENCY SET COMMENT = 'Region in which the data must remain. Drives replication scope and cross-region share eligibility.';

-- data_quality_tier  ->  Snowflake identifier DATA_QUALITY_TIER
-- Tier 2 | Data Quality | data_quality | owner EDGO | platforms: SNOWFLAKE, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_QUALITY_TIER
    ALLOWED_VALUES 'BRONZE', 'SILVER', 'GOLD', 'PLATINUM'
    COMMENT = 'Certified quality level. Set only by the data-quality pipeline once data metric function results are evaluated; never inherited, because a table in a GOLD schema is not GOLD until its own measurements say so.';
ALTER TAG GOVERNANCE.TAGS.DATA_QUALITY_TIER ADD ALLOWED_VALUES 'BRONZE', 'SILVER', 'GOLD', 'PLATINUM';
ALTER TAG GOVERNANCE.TAGS.DATA_QUALITY_TIER SET COMMENT = 'Certified quality level. Set only by the data-quality pipeline once data metric function results are evaluated; never inherited, because a table in a GOLD schema is not GOLD until its own measurements say so.';


-- ===========================================================================
-- TIER 3 - OPTIONAL / DOMAIN  (15 tags)
-- ===========================================================================

-- sub_domain  ->  Snowflake identifier SUB_DOMAIN
-- Tier 3 | Data Domain | business | owner DOMAIN_COUNCIL | platforms: SNOWFLAKE, COLLIBRA
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SUB_DOMAIN
    COMMENT = 'Second-level decomposition of domain, for large domains only.';
ALTER TAG GOVERNANCE.TAGS.SUB_DOMAIN SET COMMENT = 'Second-level decomposition of domain, for large domains only.';

-- source_system  ->  Snowflake identifier SOURCE_SYSTEM
-- Tier 3 | Application | business | owner DOMAIN_COUNCIL | platforms: SNOWFLAKE, DENODO, COLLIBRA
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SOURCE_SYSTEM
    COMMENT = 'System of record the data originates from. Roots lineage at the edge.';
ALTER TAG GOVERNANCE.TAGS.SOURCE_SYSTEM SET COMMENT = 'System of record the data originates from. Roots lineage at the edge.';

-- application_owner  ->  Snowflake identifier APPLICATION_OWNER
-- Tier 3 | Ownership | ownership | owner ENTERPRISE_ARCHITECTURE | platforms: SNOWFLAKE, COLLIBRA
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.APPLICATION_OWNER
    COMMENT = 'Accountable owner of the application referenced by the object.';
ALTER TAG GOVERNANCE.TAGS.APPLICATION_OWNER SET COMMENT = 'Accountable owner of the application referenced by the object.';

-- platform_owner  ->  Snowflake identifier PLATFORM_OWNER
-- Tier 3 | Ownership | ownership | owner PLATFORM_ENGINEERING | platforms: AWS, SNOWFLAKE
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PLATFORM_OWNER
    COMMENT = 'Platform engineering team accountable for the infrastructure object.';
ALTER TAG GOVERNANCE.TAGS.PLATFORM_OWNER SET COMMENT = 'Platform engineering team accountable for the infrastructure object.';

-- domain_owner  ->  Snowflake identifier DOMAIN_OWNER
-- Tier 3 | Data Domain | data_mesh | owner DOMAIN_COUNCIL | platforms: SNOWFLAKE, COLLIBRA
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DOMAIN_OWNER
    COMMENT = 'Accountable owner of the mesh domain. Normally set once, on the domain''s database.';
ALTER TAG GOVERNANCE.TAGS.DOMAIN_OWNER SET COMMENT = 'Accountable owner of the mesh domain. Normally set once, on the domain''s database.';

-- data_product_owner  ->  Snowflake identifier DATA_PRODUCT_OWNER
-- Tier 3 | Data Product | data_mesh | owner DOMAIN_COUNCIL | platforms: SNOWFLAKE, COLLIBRA
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_PRODUCT_OWNER
    COMMENT = 'Product owner accountable for the data product''s roadmap, SLA and consumer contract. Distinct from data_owner, who is accountable for the data itself.';
ALTER TAG GOVERNANCE.TAGS.DATA_PRODUCT_OWNER SET COMMENT = 'Product owner accountable for the data product''s roadmap, SLA and consumer contract. Distinct from data_owner, who is accountable for the data itself.';

-- data_product_type  ->  Snowflake identifier DATA_PRODUCT_TYPE
-- Tier 3 | Data Product | data_mesh | owner DOMAIN_COUNCIL | platforms: SNOWFLAKE, COLLIBRA
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.DATA_PRODUCT_TYPE
    ALLOWED_VALUES 'SOURCE_ALIGNED', 'AGGREGATE', 'CONSUMER_ALIGNED', 'SHARED', 'PLATFORM'
    COMMENT = 'Mesh archetype; sets default quality and SLA expectations.';
ALTER TAG GOVERNANCE.TAGS.DATA_PRODUCT_TYPE ADD ALLOWED_VALUES 'SOURCE_ALIGNED', 'AGGREGATE', 'CONSUMER_ALIGNED', 'SHARED', 'PLATFORM';
ALTER TAG GOVERNANCE.TAGS.DATA_PRODUCT_TYPE SET COMMENT = 'Mesh archetype; sets default quality and SLA expectations.';

-- capability  ->  Snowflake identifier CAPABILITY
-- Tier 3 | Business Capability | business | owner ENTERPRISE_ARCHITECTURE | platforms: COLLIBRA
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.CAPABILITY
    COMMENT = 'Business capability from the enterprise capability model (L2).';
ALTER TAG GOVERNANCE.TAGS.CAPABILITY SET COMMENT = 'Business capability from the enterprise capability model (L2).';

-- project_code  ->  Snowflake identifier PROJECT_CODE
-- Tier 3 | Financial | financial | owner FINANCE_FINOPS | platforms: AWS, SNOWFLAKE
-- No ALLOWED_VALUES: reference_data, validated against CONTROL.REFERENCE_VALUE.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.PROJECT_CODE
    COMMENT = 'Capital or programme project funding the workload.';
ALTER TAG GOVERNANCE.TAGS.PROJECT_CODE SET COMMENT = 'Capital or programme project funding the workload.';

-- cost_allocation_model  ->  Snowflake identifier COST_ALLOCATION_MODEL
-- Tier 3 | Financial | financial | owner FINANCE_FINOPS | platforms: AWS, SNOWFLAKE
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.COST_ALLOCATION_MODEL
    ALLOWED_VALUES 'SHOWBACK', 'CHARGEBACK', 'SHARED_SERVICE', 'ABSORBED_PLATFORM'
    COMMENT = 'How this object''s consumption is settled with the business. SHOWBACK reports only; CHARGEBACK posts a journal entry to the ERP.';
ALTER TAG GOVERNANCE.TAGS.COST_ALLOCATION_MODEL ADD ALLOWED_VALUES 'SHOWBACK', 'CHARGEBACK', 'SHARED_SERVICE', 'ABSORBED_PLATFORM';
ALTER TAG GOVERNANCE.TAGS.COST_ALLOCATION_MODEL SET COMMENT = 'How this object''s consumption is settled with the business. SHOWBACK reports only; CHARGEBACK posts a journal entry to the ERP.';

-- encryption_required  ->  Snowflake identifier ENCRYPTION_REQUIRED
-- Tier 3 | Security | security | owner CISO_DATA_SECURITY | platforms: AWS, SNOWFLAKE
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.ENCRYPTION_REQUIRED
    ALLOWED_VALUES 'YES', 'NO'
    COMMENT = 'Declares that application-layer or client-side encryption is required in addition to transparent encryption at rest. Mainly external stages and columns holding secrets or key material.';
ALTER TAG GOVERNANCE.TAGS.ENCRYPTION_REQUIRED ADD ALLOWED_VALUES 'YES', 'NO';
ALTER TAG GOVERNANCE.TAGS.ENCRYPTION_REQUIRED SET COMMENT = 'Declares that application-layer or client-side encryption is required in addition to transparent encryption at rest. Mainly external stages and columns holding secrets or key material.';

-- sharing_scope  ->  Snowflake identifier SHARING_SCOPE
-- Tier 3 | Security | security | owner CISO_DATA_SECURITY | platforms: SNOWFLAKE, DENODO
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.SHARING_SCOPE
    ALLOWED_VALUES 'PROHIBITED', 'INTERNAL_ONLY', 'AFFILIATE', 'PARTNER', 'PUBLIC_MARKETPLACE'
    COMMENT = 'Maximum permitted distribution. Checked before any listing, share or reader-account grant is created.';
ALTER TAG GOVERNANCE.TAGS.SHARING_SCOPE ADD ALLOWED_VALUES 'PROHIBITED', 'INTERNAL_ONLY', 'AFFILIATE', 'PARTNER', 'PUBLIC_MARKETPLACE';
ALTER TAG GOVERNANCE.TAGS.SHARING_SCOPE SET COMMENT = 'Maximum permitted distribution. Checked before any listing, share or reader-account grant is created.';

-- refresh_type  ->  Snowflake identifier REFRESH_TYPE
-- Tier 3 | Operational | operational | owner PLATFORM_ENGINEERING | platforms: SNOWFLAKE, DENODO
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.REFRESH_TYPE
    ALLOWED_VALUES 'STREAMING', 'MICRO_BATCH', 'BATCH_HOURLY', 'BATCH_DAILY', 'BATCH_WEEKLY', 'BATCH_MONTHLY', 'ON_DEMAND', 'STATIC'
    COMMENT = 'How the object''s data is refreshed. Drives freshness monitoring logic.';
ALTER TAG GOVERNANCE.TAGS.REFRESH_TYPE ADD ALLOWED_VALUES 'STREAMING', 'MICRO_BATCH', 'BATCH_HOURLY', 'BATCH_DAILY', 'BATCH_WEEKLY', 'BATCH_MONTHLY', 'ON_DEMAND', 'STATIC';
ALTER TAG GOVERNANCE.TAGS.REFRESH_TYPE SET COMMENT = 'How the object''s data is refreshed. Drives freshness monitoring logic.';

-- rpo  ->  Snowflake identifier RPO
-- Tier 3 | Operational | operational | owner PLATFORM_ENGINEERING | platforms: AWS, SNOWFLAKE
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.RPO
    COMMENT = 'Recovery Point Objective as an ISO-8601 duration (e.g. PT15M, P1D).';
ALTER TAG GOVERNANCE.TAGS.RPO SET COMMENT = 'Recovery Point Objective as an ISO-8601 duration (e.g. PT15M, P1D).';

-- rto  ->  Snowflake identifier RTO
-- Tier 3 | Operational | operational | owner PLATFORM_ENGINEERING | platforms: AWS, SNOWFLAKE
-- No ALLOWED_VALUES: free_text, format-validated by SP_APPLY_TAG.
CREATE TAG IF NOT EXISTS GOVERNANCE.TAGS.RTO
    COMMENT = 'Recovery Time Objective as an ISO-8601 duration (e.g. PT4H, P1D).';
ALTER TAG GOVERNANCE.TAGS.RTO SET COMMENT = 'Recovery Time Objective as an ISO-8601 duration (e.g. PT4H, P1D).';

SELECT 'Tag DDL applied' AS status;
