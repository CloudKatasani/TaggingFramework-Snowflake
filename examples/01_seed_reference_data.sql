-- =============================================================================
-- examples/01_seed_reference_data.sql
-- Illustrative reference data so a fresh deployment can be exercised end to end.
-- -----------------------------------------------------------------------------
-- In production these tables are loaded from the systems of record - ERP for
-- cost centres, CMDB for applications, ITSM for support groups - on a scheduled
-- pipeline. Loading them by hand is a demo convenience and nothing more: the
-- whole point of REFERENCE_VALUE is that the values stay in step with the
-- systems that own them.
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
    ('REF_BUSINESS_UNIT', 'RETAIL_BANKING',    'Retail Banking',        NULL, NULL, '{"region":"GLOBAL"}', 'ERP'),
    ('REF_BUSINESS_UNIT', 'CORPORATE_TECHNOLOGY', 'Corporate Technology', NULL, NULL, '{"region":"GLOBAL"}', 'ERP'),
    ('REF_BUSINESS_UNIT', 'INSURANCE',         'Insurance',             NULL, NULL, '{"region":"EU"}',     'ERP'),

    ('REF_DOMAIN',        'CUSTOMER',          'Customer',              NULL, NULL, '{}', 'MANUAL'),
    ('REF_DOMAIN',        'FINANCE',           'Finance',               NULL, NULL, '{}', 'MANUAL'),
    ('REF_DOMAIN',        'PAYMENTS',          'Payments',              NULL, NULL, '{}', 'MANUAL'),

    ('REF_DATA_PRODUCT',  'CUSTOMER_360',      'Customer 360',          'REF_DOMAIN', 'CUSTOMER', '{}', 'MANUAL'),
    ('REF_DATA_PRODUCT',  'PAYMENT_LEDGER',    'Payment Ledger',        'REF_DOMAIN', 'PAYMENTS', '{}', 'MANUAL'),

    -- GL account travels with the cost centre so chargeback can post without a
    -- second lookup against a system the data platform may not reach.
    ('REF_COST_CENTER',   'CC-004120',         'Retail Data Platform',  'REF_BUSINESS_UNIT', 'RETAIL_BANKING',      '{"gl_account":"6100-4120"}', 'ERP'),
    ('REF_COST_CENTER',   'CC-009001',         'Enterprise Governance', 'REF_BUSINESS_UNIT', 'CORPORATE_TECHNOLOGY', '{"gl_account":"6100-9001"}', 'ERP'),

    ('REF_SUPPORT_GROUP', 'GRP-DATA-PLATFORM', 'Data Platform On-Call', NULL, NULL, '{"itsm_queue_id":"Q-1187"}', 'ITSM'),
    ('REF_SUPPORT_GROUP', 'GRP-CUSTOMER-ENG',  'Customer Engineering',  NULL, NULL, '{"itsm_queue_id":"Q-2043"}', 'ITSM'),

    ('REF_APPLICATION',   'APP-10457',         'Core Banking Platform', NULL, NULL, '{"owner":"app.owner@example.com"}', 'CMDB')
AS v(c1, c2, c3, c4, c5, c6, c7);

-- Credit price is contractual and varies by edition, region and agreement.
-- A hard-coded rate produces numbers Finance rejects on sight.
INSERT INTO RATE_CARD (EFFECTIVE_FROM, EFFECTIVE_TO, CREDIT_PRICE, STORAGE_PRICE_TB, CURRENCY)
VALUES ('2026-01-01'::DATE, NULL, 3.00, 23.00, 'USD');

-- Which stewards may tag which namespaces. This is how APPLY TAG gets scoped,
-- since Snowflake cannot scope it by grant.
INSERT INTO DOMAIN_OWNERSHIP
    (DOMAIN, DATABASE_PATTERN, SCHEMA_PATTERN, STEWARD_ROLE, DOMAIN_OWNER)
VALUES
    ('CUSTOMER', 'CUSTOMER_%', '%', 'TAG_STEWARD_CUSTOMER', 'domain.owner@example.com'),
    ('PAYMENTS', 'PAYMENT_%',  '%', 'TAG_STEWARD_PAYMENTS', 'payments.owner@example.com');

-- Row access entitlements consumed by RAP_BUSINESS_UNIT_SCOPE.
INSERT INTO ROW_ACCESS_ENTITLEMENT
    (ROLE_NAME, DIMENSION, DIMENSION_VALUE, GRANTED_BY)
VALUES
    ('RETAIL_ANALYST',   'BUSINESS_UNIT', 'RETAIL_BANKING', CURRENT_USER()),
    ('GROUP_REPORTING',  'BUSINESS_UNIT', '*',              CURRENT_USER()),
    -- DATA_RESIDENCY deliberately does not honour '*': each region is explicit.
    ('EU_ANALYST',       'DATA_RESIDENCY', 'EU',            CURRENT_USER());

SELECT 'Reference data seeded' AS status;
