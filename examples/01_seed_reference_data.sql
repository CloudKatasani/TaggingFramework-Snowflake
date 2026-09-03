-- =============================================================================
-- examples/01_seed_reference_data.sql
-- Illustrative reference data so a fresh deployment can be exercised end to end.
-- -----------------------------------------------------------------------------
-- In production these are loaded from the systems of record - ERP for operating
-- companies and cost centres, CMDB for applications, HR for teams, ITSM for
-- support groups - on a scheduled pipeline. Loading them by hand is a demo
-- convenience: the whole point of REFERENCE_VALUE is that the values stay in
-- step with the systems that own them.
--
-- Note which tags are NOT here. operating_company, department, domain,
-- workload_type and both classification tags are controlled vocabularies
-- enforced by Snowflake ALLOWED_VALUES, so they need no reference data at all.
-- Only the sets that are too large or too volatile for a 300-value ceiling -
-- teams, applications, cost centres - live in this table.
-- =============================================================================

USE ROLE TAG_ADMIN;
USE WAREHOUSE GOVERNANCE_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA CONTROL;

INSERT INTO REFERENCE_VALUE
    (REFERENCE_SET, VALUE_CODE, DISPLAY_NAME, PARENT_SET, PARENT_CODE,
     ATTRIBUTES, SOURCE_SYSTEM)
SELECT c1, c2, c3, c4, c5, PARSE_JSON(c6), c7
FROM VALUES
    -- Operating companies also exist as an ALLOWED_VALUES vocabulary; they are
    -- mirrored here so reports can resolve a display name and legal entity id.
    ('REF_OPERATING_COMPANY', 'OPCO_AEP_OHIO',   'AEP Ohio',            NULL, NULL, '{"legal_entity_id":"LE-1001","region":"US_EAST"}', 'ERP'),
    ('REF_OPERATING_COMPANY', 'OPCO_AEP_TEXAS',  'AEP Texas',           NULL, NULL, '{"legal_entity_id":"LE-1002","region":"US_SOUTH"}', 'ERP'),
    ('REF_OPERATING_COMPANY', 'OPCO_APPALACHIAN','Appalachian Power',   NULL, NULL, '{"legal_entity_id":"LE-1003","region":"US_EAST"}', 'ERP'),
    ('REF_OPERATING_COMPANY', 'SHARED',          'Shared / Enterprise', NULL, NULL, '{"legal_entity_id":"LE-1000"}', 'ERP'),

    -- Teams: too many and too volatile for a vocabulary, and a disbanded team
    -- must stop being a legal owner the day it is dissolved.
    ('REF_TEAM', 'team-customer-360',   'Customer 360 Platform', 'REF_DEPARTMENT', 'CUSTOMER',  '{"manager":"jane.doe@aep.com","support_group":"GRP-CUSTOMER-ENG"}', 'HR'),
    ('REF_TEAM', 'team-revenue-platform','Revenue Platform',     'REF_DEPARTMENT', 'FINANCE',   '{"manager":"sam.lee@aep.com","support_group":"GRP-FIN-ENG"}',      'HR'),
    ('REF_TEAM', 'team-mlops-core',     'MLOps Core',            'REF_DEPARTMENT', 'CORPORATE', '{"manager":"alex.kim@aep.com","support_group":"GRP-DATA-PLATFORM"}', 'HR'),
    ('REF_TEAM', 'team-data-governance','Data Governance',       'REF_DEPARTMENT', 'CORPORATE', '{"manager":"pat.ray@aep.com","support_group":"GRP-DATA-PLATFORM"}', 'HR'),

    ('REF_APPLICATION', 'app-cust360-api',   'Customer 360 API',        NULL, NULL, '{"owner":"jane.doe@aep.com","cmdb_id":"CI-10457"}', 'CMDB'),
    ('REF_APPLICATION', 'app-finmart-dbt',   'Finance Mart (dbt)',      NULL, NULL, '{"owner":"sam.lee@aep.com","cmdb_id":"CI-10891"}',  'CMDB'),
    ('REF_APPLICATION', 'app-pricing-ml',    'Pricing ML Service',      NULL, NULL, '{"owner":"alex.kim@aep.com","cmdb_id":"CI-11204"}', 'CMDB'),
    ('REF_APPLICATION', 'app-collibra-conn', 'Collibra Connector',      NULL, NULL, '{"owner":"pat.ray@aep.com","cmdb_id":"CI-11500"}',  'CMDB'),
    ('REF_APPLICATION', 'app-tag-governance','Enterprise Tag Framework',NULL, NULL, '{"owner":"pat.ray@aep.com","cmdb_id":"CI-11501"}',  'CMDB'),

    ('REF_DATA_PRODUCT', 'dp-customer-360',   'Customer 360',   'REF_DOMAIN', 'CUSTOMER', '{}', 'MANUAL'),
    ('REF_DATA_PRODUCT', 'dp-meter-telemetry','Meter Telemetry','REF_DOMAIN', 'METER',    '{}', 'MANUAL'),

    ('REF_COST_CENTER', 'CC-004120', 'Customer Data Platform', 'REF_OPERATING_COMPANY', 'OPCO_AEP_OHIO', '{"gl_account":"6100-4120"}', 'ERP'),
    ('REF_COST_CENTER', 'CC-009001', 'Enterprise Governance',  'REF_OPERATING_COMPANY', 'SHARED',        '{"gl_account":"6100-9001"}', 'ERP'),

    ('REF_SUPPORT_GROUP', 'GRP-DATA-PLATFORM', 'Data Platform On-Call', NULL, NULL, '{"itsm_queue_id":"Q-1187"}', 'ITSM'),
    ('REF_SUPPORT_GROUP', 'GRP-CUSTOMER-ENG',  'Customer Engineering',  NULL, NULL, '{"itsm_queue_id":"Q-2043"}', 'ITSM'),
    ('REF_SUPPORT_GROUP', 'GRP-FIN-ENG',       'Finance Engineering',   NULL, NULL, '{"itsm_queue_id":"Q-2210"}', 'ITSM')
AS v(c1, c2, c3, c4, c5, c6, c7);

-- Credit price is contractual and varies by edition, region and agreement.
-- A hard-coded rate produces numbers Finance rejects on sight.
INSERT INTO RATE_CARD (EFFECTIVE_FROM, EFFECTIVE_TO, CREDIT_PRICE, STORAGE_PRICE_TB, CURRENCY)
VALUES ('2026-01-01'::DATE, NULL, 3.00, 23.00, 'USD');

-- Which stewards may tag which namespaces. This is how APPLY TAG gets scoped,
-- since Snowflake cannot scope it by grant.
INSERT INTO DOMAIN_OWNERSHIP
    (DOMAIN, OPERATING_COMPANY, DATABASE_PATTERN, SCHEMA_PATTERN, STEWARD_ROLE, DOMAIN_OWNER)
VALUES
    ('CUSTOMER', NULL,            'CUSTOMER_%', '%', 'TAG_STEWARD_CUSTOMER', 'domain.owner@aep.com'),
    ('METER',    NULL,            'METER_%',    '%', 'TAG_STEWARD_METER',    'meter.owner@aep.com'),
    ('FINANCE',  'OPCO_AEP_OHIO', 'FIN_OH_%',   '%', 'TAG_STEWARD_FIN_OH',   'fin.oh.owner@aep.com');

-- Row access entitlements consumed by RAP_OPERATING_COMPANY_SCOPE.
INSERT INTO ROW_ACCESS_ENTITLEMENT
    (ROLE_NAME, DIMENSION, DIMENSION_VALUE, GRANTED_BY)
VALUES
    ('OHIO_ANALYST',    'OPERATING_COMPANY', 'OPCO_AEP_OHIO', CURRENT_USER()),
    ('TEXAS_ANALYST',   'OPERATING_COMPANY', 'OPCO_AEP_TEXAS', CURRENT_USER()),
    -- A wildcard is legitimate for consolidated group reporting, and is exactly
    -- the entitlement an access review should look at first.
    ('GROUP_REPORTING', 'OPERATING_COMPANY', '*',             CURRENT_USER()),
    -- DATA_RESIDENCY deliberately does not honour '*': each region is explicit.
    ('US_EAST_ANALYST', 'DATA_RESIDENCY',    'US_EAST',       CURRENT_USER());

SELECT 'Reference data seeded' AS status;
