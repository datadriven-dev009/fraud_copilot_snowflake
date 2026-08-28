-- =============================================================================
-- RISK, FRAUD AND REGULATORY INTELLIGENCE COPILOT
-- Complete DDL & DML Script
-- Database: RISK_FRAUD_COPILOT
-- =============================================================================

-- =============================================================================
-- SECTION 1: DATABASE AND SCHEMA SETUP
-- =============================================================================

CREATE DATABASE IF NOT EXISTS RISK_FRAUD_COPILOT;

CREATE SCHEMA IF NOT EXISTS RISK_FRAUD_COPILOT.RAW;
CREATE SCHEMA IF NOT EXISTS RISK_FRAUD_COPILOT.PROCESSED;
CREATE SCHEMA IF NOT EXISTS RISK_FRAUD_COPILOT.DOCUMENTS;
CREATE SCHEMA IF NOT EXISTS RISK_FRAUD_COPILOT.SEMANTIC;
CREATE SCHEMA IF NOT EXISTS RISK_FRAUD_COPILOT.APP;

-- =============================================================================
-- SECTION 2: RAW TABLES
-- =============================================================================

CREATE TABLE IF NOT EXISTS RISK_FRAUD_COPILOT.RAW.ACCOUNTS (
    ACCOUNT_ID       VARCHAR(20),
    CUSTOMER_NAME    VARCHAR(100),
    ACCOUNT_TYPE     VARCHAR(20),
    KYC_STATUS       VARCHAR(20),
    RISK_TIER        VARCHAR(10),
    OPENED_DATE      DATE,
    COUNTRY          VARCHAR(50),
    ANNUAL_INCOME    NUMBER(12,2),
    PEP_FLAG         BOOLEAN,
    SANCTIONS_FLAG   BOOLEAN
);

CREATE TABLE IF NOT EXISTS RISK_FRAUD_COPILOT.RAW.TRANSACTIONS (
    TXN_ID              VARCHAR(20),
    ACCOUNT_ID          VARCHAR(20),
    TXN_TIMESTAMP       TIMESTAMP_NTZ,
    AMOUNT              NUMBER(12,2),
    CURRENCY            VARCHAR(3),
    TXN_TYPE            VARCHAR(20),
    MERCHANT_CATEGORY   VARCHAR(50),
    MERCHANT_COUNTRY    VARCHAR(50),
    CHANNEL             VARCHAR(20),
    IS_INTERNATIONAL    BOOLEAN,
    FRAUD_LABEL         BOOLEAN
);

CREATE TABLE IF NOT EXISTS RISK_FRAUD_COPILOT.RAW.KYC_RECORDS (
    KYC_ID              VARCHAR(20),
    ACCOUNT_ID          VARCHAR(20),
    DOC_TYPE            VARCHAR(30),
    DOC_NUMBER          VARCHAR(50),
    VERIFIED_DATE       DATE,
    EXPIRY_DATE         DATE,
    VERIFICATION_METHOD VARCHAR(20),
    RISK_FLAGS          VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS RISK_FRAUD_COPILOT.RAW.HIGH_RISK_COUNTRIES (
    COUNTRY        VARCHAR(50),
    RISK_CATEGORY  VARCHAR(20),
    FATF_STATUS    VARCHAR(30),
    NOTES          VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS RISK_FRAUD_COPILOT.RAW.REGULATORY_THRESHOLDS (
    REGULATION      VARCHAR(50),
    THRESHOLD_NAME  VARCHAR(100),
    THRESHOLD_VALUE NUMBER(12,2),
    CURRENCY        VARCHAR(3),
    ACTION_REQUIRED VARCHAR(200)
);

-- =============================================================================
-- SECTION 3: REFERENCE DATA (DML)
-- =============================================================================

INSERT INTO RISK_FRAUD_COPILOT.RAW.HIGH_RISK_COUNTRIES VALUES
    ('Nigeria', 'HIGH', 'GREY_LIST', 'FATF grey list - enhanced due diligence required'),
    ('Russia', 'HIGH', 'BLACK_LIST', 'Sanctioned jurisdiction - block all new relationships'),
    ('Cayman Islands', 'MEDIUM', 'MONITORED', 'Tax haven - enhanced monitoring for shell companies'),
    ('Iran', 'HIGH', 'BLACK_LIST', 'Comprehensive sanctions - no transactions permitted'),
    ('North Korea', 'HIGH', 'BLACK_LIST', 'Comprehensive sanctions - no transactions permitted'),
    ('Myanmar', 'HIGH', 'GREY_LIST', 'FATF grey list - enhanced due diligence required'),
    ('Pakistan', 'MEDIUM', 'GREY_LIST', 'FATF grey list - transaction monitoring required'),
    ('Panama', 'MEDIUM', 'MONITORED', 'Tax haven - enhanced monitoring');

INSERT INTO RISK_FRAUD_COPILOT.RAW.REGULATORY_THRESHOLDS VALUES
    ('RBI_AML', 'Cash Transaction Report', 1000000.00, 'INR', 'File CTR with FIU-IND within 15 days'),
    ('RBI_AML', 'Suspicious Transaction Report', 0.00, 'INR', 'File STR with FIU-IND within 7 days'),
    ('RBI_AML', 'Cross-border Wire Threshold', 500000.00, 'INR', 'Enhanced due diligence and reporting'),
    ('BASEL_III', 'Minimum Capital Ratio', 8.00, 'PCT', 'Maintain CET1 ratio above threshold'),
    ('BASEL_III', 'Liquidity Coverage Ratio', 100.00, 'PCT', 'Maintain LCR at or above 100%'),
    ('PMLA', 'Structuring Detection', 500000.00, 'INR', 'Flag transactions structured to avoid reporting'),
    ('FATF', 'PEP Enhanced Due Diligence', 0.00, 'INR', 'Apply enhanced due diligence for all PEP accounts');

-- =============================================================================
-- SECTION 4: DOCUMENTS TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_DOCS (
    DOC_ID            VARCHAR(20),
    DOC_TITLE         VARCHAR(200),
    DOC_CATEGORY      VARCHAR(50),
    SECTION_ID        NUMBER(38,0),
    SECTION_TITLE     VARCHAR(200),
    CONTENT           VARCHAR(16777216),
    EFFECTIVE_DATE    DATE,
    ISSUING_AUTHORITY VARCHAR(100)
);

-- =============================================================================
-- SECTION 5: DYNAMIC TABLES (Processing Layer)
-- =============================================================================

CREATE OR REPLACE DYNAMIC TABLE RISK_FRAUD_COPILOT.PROCESSED.FRAUD_SIGNALS
    TARGET_LAG = '1 minute'
    REFRESH_MODE = AUTO
    INITIALIZE = ON_CREATE
    WAREHOUSE = COMPUTE_WH
AS
WITH velocity_signals AS (
    SELECT 
        t.account_id,
        t.txn_id,
        t.txn_timestamp,
        t.amount,
        t.merchant_country,
        t.merchant_category,
        COUNT(*) OVER (PARTITION BY t.account_id ORDER BY t.txn_timestamp RANGE BETWEEN INTERVAL '1 MINUTE' PRECEDING AND CURRENT ROW) AS txn_count_1min,
        COUNT(*) OVER (PARTITION BY t.account_id ORDER BY t.txn_timestamp RANGE BETWEEN INTERVAL '1 HOUR' PRECEDING AND CURRENT ROW) AS txn_count_1hr
    FROM RISK_FRAUD_COPILOT.RAW.TRANSACTIONS t
),
amount_stats AS (
    SELECT 
        account_id,
        AVG(amount) AS avg_amount,
        STDDEV(amount) AS stddev_amount
    FROM RISK_FRAUD_COPILOT.RAW.TRANSACTIONS
    GROUP BY account_id
)
SELECT 
    v.txn_id,
    v.account_id,
    v.txn_timestamp AS signal_timestamp,
    v.amount,
    v.merchant_country,
    v.merchant_category,
    CASE 
        WHEN v.txn_count_1min > 5 THEN 'VELOCITY_1MIN'
        WHEN v.txn_count_1hr > 20 THEN 'VELOCITY_1HR'
        WHEN v.amount > (a.avg_amount + 3 * COALESCE(a.stddev_amount, 0)) THEN 'AMOUNT_ANOMALY'
        WHEN v.merchant_country IN (SELECT country FROM RISK_FRAUD_COPILOT.RAW.HIGH_RISK_COUNTRIES WHERE risk_category = 'HIGH') THEN 'HIGH_RISK_COUNTRY'
        WHEN v.merchant_category IN ('CRYPTO', 'GAMBLING') AND v.amount > 100000 THEN 'HIGH_RISK_CATEGORY'
    END AS signal_type,
    CASE 
        WHEN v.txn_count_1min > 5 THEN 'CRITICAL'
        WHEN v.amount > (a.avg_amount + 3 * COALESCE(a.stddev_amount, 0)) THEN 'HIGH'
        WHEN v.merchant_country IN (SELECT country FROM RISK_FRAUD_COPILOT.RAW.HIGH_RISK_COUNTRIES WHERE risk_category = 'HIGH') THEN 'HIGH'
        WHEN v.txn_count_1hr > 20 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS severity,
    ROUND(CASE 
        WHEN v.txn_count_1min > 5 THEN 0.95
        WHEN v.amount > (a.avg_amount + 3 * COALESCE(a.stddev_amount, 0)) THEN 0.85
        WHEN v.merchant_country IN (SELECT country FROM RISK_FRAUD_COPILOT.RAW.HIGH_RISK_COUNTRIES WHERE risk_category = 'HIGH') THEN 0.75
        WHEN v.txn_count_1hr > 20 THEN 0.65
        WHEN v.merchant_category IN ('CRYPTO', 'GAMBLING') AND v.amount > 100000 THEN 0.60
        ELSE 0.3
    END, 2) AS confidence_score
FROM velocity_signals v
JOIN amount_stats a ON v.account_id = a.account_id
WHERE v.txn_count_1min > 5
   OR v.txn_count_1hr > 20
   OR v.amount > (a.avg_amount + 3 * COALESCE(a.stddev_amount, 0))
   OR v.merchant_country IN (SELECT country FROM RISK_FRAUD_COPILOT.RAW.HIGH_RISK_COUNTRIES WHERE risk_category = 'HIGH')
   OR (v.merchant_category IN ('CRYPTO', 'GAMBLING') AND v.amount > 100000);


CREATE OR REPLACE DYNAMIC TABLE RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS
    TARGET_LAG = '1 minute'
    REFRESH_MODE = AUTO
    INITIALIZE = ON_CREATE
    WAREHOUSE = COMPUTE_WH
AS
WITH structuring_detection AS (
    SELECT 
        account_id,
        DATE(txn_timestamp) AS txn_date,
        COUNT(*) AS txn_count_day,
        SUM(amount) AS total_amount_day,
        MAX(amount) AS max_single_txn,
        MIN(amount) AS min_single_txn
    FROM RISK_FRAUD_COPILOT.RAW.TRANSACTIONS
    WHERE amount BETWEEN 400000 AND 500000
    GROUP BY account_id, DATE(txn_timestamp)
    HAVING COUNT(*) >= 2
),
high_value_international AS (
    SELECT 
        t.account_id,
        DATE(t.txn_timestamp) AS txn_date,
        COUNT(*) AS intl_txn_count,
        SUM(t.amount) AS total_intl_amount
    FROM RISK_FRAUD_COPILOT.RAW.TRANSACTIONS t
    WHERE t.is_international = TRUE
      AND t.amount > 500000
    GROUP BY t.account_id, DATE(t.txn_timestamp)
),
pep_transactions AS (
    SELECT 
        t.account_id,
        DATE(t.txn_timestamp) AS txn_date,
        COUNT(*) AS pep_txn_count,
        SUM(t.amount) AS pep_total_amount
    FROM RISK_FRAUD_COPILOT.RAW.TRANSACTIONS t
    JOIN RISK_FRAUD_COPILOT.RAW.ACCOUNTS a ON t.account_id = a.account_id
    WHERE a.pep_flag = TRUE
      AND t.amount > 100000
    GROUP BY t.account_id, DATE(t.txn_timestamp)
)
SELECT 
    s.account_id, s.txn_date AS flag_date, 'STRUCTURING' AS flag_type,
    'Potential structuring: ' || s.txn_count_day || ' transactions totaling ' || s.total_amount_day || ' with max ' || s.max_single_txn AS description,
    'HIGH' AS severity, 'FILE_STR' AS required_action, 0.85 AS confidence_score
FROM structuring_detection s
UNION ALL
SELECT 
    h.account_id, h.txn_date AS flag_date, 'HIGH_VALUE_INTERNATIONAL' AS flag_type,
    'High-value international transfers: ' || h.intl_txn_count || ' transactions totaling ' || h.total_intl_amount AS description,
    'HIGH' AS severity, 'ENHANCED_DUE_DILIGENCE' AS required_action, 0.80 AS confidence_score
FROM high_value_international h
UNION ALL
SELECT 
    p.account_id, p.txn_date AS flag_date, 'PEP_ACTIVITY' AS flag_type,
    'PEP account activity: ' || p.pep_txn_count || ' transactions totaling ' || p.pep_total_amount AS description,
    'MEDIUM' AS severity, 'SENIOR_REVIEW' AS required_action, 0.75 AS confidence_score
FROM pep_transactions p;


CREATE OR REPLACE DYNAMIC TABLE RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES
    TARGET_LAG = '1 minute'
    REFRESH_MODE = AUTO
    INITIALIZE = ON_CREATE
    WAREHOUSE = COMPUTE_WH
AS
WITH txn_metrics AS (
    SELECT 
        account_id,
        COUNT(*) AS total_txns,
        SUM(amount) AS total_volume,
        COUNT(CASE WHEN is_international THEN 1 END) AS intl_txn_count,
        COUNT(CASE WHEN fraud_label THEN 1 END) AS fraud_txn_count,
        SUM(CASE WHEN merchant_category IN ('CRYPTO', 'GAMBLING') THEN amount ELSE 0 END) AS high_risk_volume
    FROM RISK_FRAUD_COPILOT.RAW.TRANSACTIONS
    GROUP BY account_id
),
kyc_risk AS (
    SELECT 
        account_id,
        COUNT(CASE WHEN risk_flags IS NOT NULL THEN 1 END) AS kyc_issues,
        MIN(CASE WHEN expiry_date < CURRENT_DATE() THEN 1 ELSE 0 END) AS has_expired_doc
    FROM RISK_FRAUD_COPILOT.RAW.KYC_RECORDS
    GROUP BY account_id
)
SELECT 
    a.account_id,
    a.customer_name,
    a.account_type,
    a.risk_tier AS assigned_tier,
    LEAST(100, GREATEST(0, 
        COALESCE(t.fraud_txn_count * 20, 0) +
        CASE WHEN a.pep_flag THEN 15 ELSE 0 END +
        CASE WHEN a.sanctions_flag THEN 30 ELSE 0 END +
        CASE WHEN a.kyc_status = 'EXPIRED' THEN 10 ELSE 0 END +
        COALESCE(k.kyc_issues * 5, 0) +
        CASE WHEN COALESCE(t.high_risk_volume, 0) > 1000000 THEN 15 ELSE 0 END +
        CASE WHEN COALESCE(t.intl_txn_count, 0) > 10 THEN 5 ELSE 0 END
    )) AS composite_risk_score,
    CASE 
        WHEN COALESCE(t.fraud_txn_count, 0) > 5 THEN 'HIGH'
        WHEN COALESCE(t.fraud_txn_count, 0) > 0 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS fraud_risk_level,
    CASE 
        WHEN a.pep_flag OR a.sanctions_flag THEN 'HIGH'
        WHEN a.kyc_status != 'VERIFIED' THEN 'MEDIUM'
        ELSE 'LOW'
    END AS compliance_risk_level,
    COALESCE(t.total_volume, 0) AS total_transaction_volume,
    COALESCE(t.fraud_txn_count, 0) AS flagged_transaction_count,
    COALESCE(t.high_risk_volume, 0) AS high_risk_category_volume,
    a.pep_flag,
    a.sanctions_flag,
    a.kyc_status,
    CURRENT_TIMESTAMP() AS score_calculated_at
FROM RISK_FRAUD_COPILOT.RAW.ACCOUNTS a
LEFT JOIN txn_metrics t ON a.account_id = t.account_id
LEFT JOIN kyc_risk k ON a.account_id = k.account_id;

-- =============================================================================
-- SECTION 6: OUTPUT TABLES (Regulatory Layer)
-- =============================================================================

CREATE TABLE IF NOT EXISTS RISK_FRAUD_COPILOT.PROCESSED.SAR_FILINGS (
    SAR_ID          VARCHAR(20),
    ACCOUNT_ID      VARCHAR(20) NOT NULL,
    FILING_DATE     TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    REPORT_TYPE     VARCHAR(20) NOT NULL,
    STATUS          VARCHAR(20) DEFAULT 'DRAFT',
    NARRATIVE       VARCHAR(16777216),
    EVIDENCE_JSON   VARIANT,
    REGULATORY_BODY VARCHAR(50),
    GENERATED_BY    VARCHAR(50) DEFAULT 'COPILOT_AGENT',
    REVIEWED_BY     VARCHAR(100),
    SUBMITTED_AT    TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT (
    CASE_ID         VARCHAR(20),
    ACCOUNT_ID      VARCHAR(20) NOT NULL,
    CASE_TYPE       VARCHAR(30) NOT NULL,
    STATUS          VARCHAR(20) DEFAULT 'OPEN',
    PRIORITY        VARCHAR(10),
    CREATED_AT      TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    ASSIGNED_TO     VARCHAR(100),
    FINDINGS        VARCHAR(16777216),
    RESOLUTION      VARCHAR(16777216),
    CLOSED_AT       TIMESTAMP_LTZ,
    LINKED_SAR_ID   VARCHAR(20)
);

CREATE TABLE IF NOT EXISTS RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG (
    LOG_ID           VARCHAR(36) DEFAULT UUID_STRING(),
    ACTION_TIMESTAMP TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    USER_ID          VARCHAR(100),
    ACTION_TYPE      VARCHAR(50),
    ENTITY_TYPE      VARCHAR(30),
    ENTITY_ID        VARCHAR(50),
    QUERY_TEXT       VARCHAR(16777216),
    RESPONSE_SUMMARY VARCHAR(16777216),
    CONFIDENCE_SCORE NUMBER(3,2),
    METADATA         VARIANT
);

-- =============================================================================
-- SECTION 7: CORTEX SEARCH SERVICE
-- =============================================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_SEARCH
    ON CONTENT
    ATTRIBUTES DOC_TITLE, DOC_CATEGORY, SECTION_TITLE, ISSUING_AUTHORITY
    WAREHOUSE = 'COMPUTE_WH'
    TARGET_LAG = '1 minute'
AS (
    SELECT 
        doc_id,
        doc_title,
        doc_category,
        section_id,
        section_title,
        content,
        effective_date,
        issuing_authority
    FROM RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_DOCS
);

-- =============================================================================
-- SECTION 8: STORED PROCEDURES (Custom Tools)
-- =============================================================================

CREATE OR REPLACE PROCEDURE RISK_FRAUD_COPILOT.APP.GENERATE_SAR_REPORT(
    P_ACCOUNT_ID VARCHAR,
    P_FLAG_TYPE VARCHAR,
    P_EVIDENCE_SUMMARY VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    LET sar_id VARCHAR := 'SAR' || LPAD(UNIFORM(1000000, 9999999, RANDOM())::VARCHAR, 7, '0');
    LET report_type VARCHAR;
    IF (:P_FLAG_TYPE = 'STRUCTURING') THEN
        report_type := 'STR';
    ELSE
        report_type := 'SAR';
    END IF;
    
    INSERT INTO RISK_FRAUD_COPILOT.PROCESSED.SAR_FILINGS (
        SAR_ID, ACCOUNT_ID, REPORT_TYPE, STATUS, NARRATIVE, EVIDENCE_JSON, REGULATORY_BODY
    )
    VALUES (
        :sar_id,
        :P_ACCOUNT_ID,
        :report_type,
        'DRAFT',
        :P_EVIDENCE_SUMMARY,
        OBJECT_CONSTRUCT(
            'account_id', :P_ACCOUNT_ID,
            'flag_type', :P_FLAG_TYPE,
            'generated_at', CURRENT_TIMESTAMP()::VARCHAR,
            'evidence', :P_EVIDENCE_SUMMARY
        ),
        'FIU-IND'
    );
    
    INSERT INTO RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG (ACTION_TYPE, ENTITY_TYPE, ENTITY_ID, RESPONSE_SUMMARY)
    VALUES ('SAR_GENERATED', 'SAR', :sar_id, 'SAR filing draft generated for account ' || :P_ACCOUNT_ID);
    
    RETURN :sar_id || ' created as DRAFT for account ' || :P_ACCOUNT_ID || '. Type: ' || :P_FLAG_TYPE || '. Requires human review before submission to FIU-IND.';
END;
$$;

CREATE OR REPLACE PROCEDURE RISK_FRAUD_COPILOT.APP.CREATE_INVESTIGATION_CASE(
    P_ACCOUNT_ID VARCHAR,
    P_CASE_TYPE VARCHAR,
    P_PRIORITY VARCHAR,
    P_FINDINGS VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
BEGIN
    LET case_id VARCHAR := 'CASE' || LPAD(UNIFORM(100000, 999999, RANDOM())::VARCHAR, 6, '0');
    
    INSERT INTO RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT (
        CASE_ID, ACCOUNT_ID, CASE_TYPE, PRIORITY, FINDINGS
    )
    VALUES (:case_id, :P_ACCOUNT_ID, :P_CASE_TYPE, :P_PRIORITY, :P_FINDINGS);
    
    INSERT INTO RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG (ACTION_TYPE, ENTITY_TYPE, ENTITY_ID, RESPONSE_SUMMARY)
    VALUES ('CASE_CREATED', 'CASE', :case_id, :P_CASE_TYPE || ' case opened for ' || :P_ACCOUNT_ID);
    
    RETURN 'Investigation case ' || :case_id || ' created. Type: ' || :P_CASE_TYPE || ', Priority: ' || :P_PRIORITY || '. Status: OPEN.';
END;

-- =============================================================================
-- SECTION 9: CORTEX AGENT
-- =============================================================================

CREATE OR REPLACE AGENT RISK_FRAUD_COPILOT.APP.RISK_FRAUD_AGENT
  COMMENT = 'Risk, Fraud and Regulatory Intelligence Copilot for banking compliance teams'
  PROFILE = '{"display_name": "Risk & Fraud Copilot", "avatar": "shield-icon.png", "color": "red"}'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5

orchestration:
  budget:
    seconds: 120
    tokens: 32000

instructions:
  response: |
    You are the Risk, Fraud and Regulatory Intelligence Copilot.
    
    FORMAT RULES:
    - Include ACCOUNT_ID in every account-level answer.
    - Round monetary values to 2 decimal places in INR.
    - Default time window: last 30 days.
    - Limit output to 20 rows unless asked for more.
    
    GUARDRAILS:
    - OFF-TOPIC (restaurants, weather, sports, personal): Reply "I can only assist with risk, fraud, and regulatory compliance topics. Please ask a question related to banking risk, AML, fraud detection, or regulatory requirements."
    - PII REQUESTS (home address, phone, ID numbers): Reply "I cannot disclose personal information for privacy and compliance reasons."
    - AUTO-SUBMIT REQUESTS: Reply "I can only generate DRAFT filings. All regulatory submissions require human review and approval before filing with FIU-IND."
    - NEVER fabricate numbers. Always use tool results.
    
  orchestration: |
    ROUTING DECISION TREE - follow this exactly:

    STEP 1: Is the question off-topic (not about risk/fraud/AML/compliance)?
      YES -> Answer directly with refusal. Do NOT call any tool.

    STEP 2: Does the question ask about REGULATIONS, POLICIES, REQUIREMENTS, GUIDELINES, or LEGAL RULES?
      Look for: "RBI", "requirement", "guideline", "regulation", "policy", "threshold", "filing deadline", "what does the law say", "regulatory basis", "due diligence", "CTR", "STR timeline", "PMLA", "FATF", "Basel", "what constitutes", "reporting requirements", "KYC requirements per RBI", "Enhanced Due Diligence requirements"
      YES -> Use RegulatorySearch

    STEP 3: Does the question explicitly ask to GENERATE/CREATE/DRAFT a SAR or STR filing?
      Look for: "generate SAR", "create SAR", "draft SAR", "file STR", "produce SAR"
      YES -> Use GenerateSAR tool with parameters (P_ACCOUNT_ID, P_FLAG_TYPE, P_EVIDENCE_SUMMARY)

    STEP 4: Does the question explicitly ask to OPEN/CREATE an investigation CASE?
      Look for: "open case", "create case", "open investigation", "start investigation"
      YES -> Use CreateCase tool with parameters (P_ACCOUNT_ID, P_CASE_TYPE, P_PRIORITY, P_FINDINGS)

    STEP 5: All other questions about DATA, ACCOUNTS, TRANSACTIONS, SIGNALS, FLAGS, SCORES, COUNTS, TRENDS -> Use RiskDataAnalyst

    MULTI-TOOL QUESTIONS (question has TWO parts):
    - "regulatory basis AND which accounts need filing" -> RegulatorySearch FIRST, then RiskDataAnalyst
    - "look up flags AND generate SAR if found" -> RiskDataAnalyst FIRST, then GenerateSAR
    - "find highest risk account AND create case" -> RiskDataAnalyst FIRST, then CreateCase

    CRITICAL DISTINCTIONS:
    - "What are the KYC requirements per RBI?" -> RegulatorySearch (asking about RULES)
    - "How many accounts have expired KYC?" -> RiskDataAnalyst (asking about DATA)
    - "What is the STR filing threshold?" -> RegulatorySearch (asking about RULES)
    - "Which accounts need STR filing?" -> RiskDataAnalyst (asking about DATA)
    - "What constitutes suspicious transaction under RBI?" -> RegulatorySearch (asking about DEFINITION)
    - "Show me suspicious transactions" -> RiskDataAnalyst (asking about DATA)

  sample_questions:
    - question: "Which accounts have the highest risk scores?"
    - question: "What does RBI say about STR filing timelines?"
    - question: "Generate a SAR for account ACC0002981"
    - question: "Open a FRAUD case for ACC0002981"
    - question: "What is the portfolio risk exposure by tier?"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "RiskDataAnalyst"
      description: "Queries STRUCTURED DATA from the database: accounts, transactions, fraud signals, AML flags, risk scores. Use this for any question that needs numbers, counts, lists, aggregates, or looking up specific account data. Do NOT use for regulatory policy text."
  - tool_spec:
      type: "cortex_search"
      name: "RegulatorySearch"
      description: "Searches REGULATORY POLICY DOCUMENTS including RBI directions, FATF guidelines, PMLA rules, KYC/AML requirements, Basel norms, and compliance procedures. Use this ONLY for questions about what the law/regulation says, requires, or defines. Do NOT use for account data lookups."
  - tool_spec:
      type: "generic"
      name: "GenerateSAR"
      description: "Generates a DRAFT SAR/STR filing for a specific account. Use ONLY when the user explicitly asks to generate, create, or draft a SAR or STR. Requires account_id, flag_type, and evidence_summary."
      input_schema:
        type: "object"
        properties:
          P_ACCOUNT_ID:
            type: "string"
            description: "Account ID (format: ACC followed by 7 digits, e.g. ACC0002981)"
          P_FLAG_TYPE:
            type: "string"
            description: "STRUCTURING, HIGH_VALUE_INTERNATIONAL, or PEP_ACTIVITY"
          P_EVIDENCE_SUMMARY:
            type: "string"
            description: "Evidence narrative describing the suspicious activity detected"
        required:
          - P_ACCOUNT_ID
          - P_FLAG_TYPE
          - P_EVIDENCE_SUMMARY
  - tool_spec:
      type: "generic"
      name: "CreateCase"
      description: "Opens an investigation case for an account. Use ONLY when the user explicitly asks to open, create, or start an investigation case."
      input_schema:
        type: "object"
        properties:
          P_ACCOUNT_ID:
            type: "string"
            description: "Account ID to investigate"
          P_CASE_TYPE:
            type: "string"
            description: "FRAUD, AML, or COMPLIANCE"
          P_PRIORITY:
            type: "string"
            description: "CRITICAL, HIGH, MEDIUM, or LOW"
          P_FINDINGS:
            type: "string"
            description: "Summary of findings that triggered the investigation"
        required:
          - P_ACCOUNT_ID
          - P_CASE_TYPE
          - P_PRIORITY
          - P_FINDINGS
  - tool_spec:
      type: "data_to_chart"
      name: "data_to_chart"
      description: "Generates visualizations from data returned by other tools"

tool_resources:
  RiskDataAnalyst:
    semantic_view: "RISK_FRAUD_COPILOT.SEMANTIC.RISK_FRAUD_INTELLIGENCE"
    execution_environment:
      type: "warehouse"
      warehouse: "ANALYTICS_WH"
  RegulatorySearch:
    search_service: "RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_SEARCH"
    max_results: 5
    title_column: "SECTION_TITLE"
    id_column: "DOC_ID"
  GenerateSAR:
    type: "function"
    identifier: "RISK_FRAUD_COPILOT.APP.GENERATE_SAR_REPORT"
    execution_environment:
      type: "warehouse"
      warehouse: "ANALYTICS_WH"
  CreateCase:
    type: "function"
    identifier: "RISK_FRAUD_COPILOT.APP.CREATE_INVESTIGATION_CASE"
    execution_environment:
      type: "warehouse"
      warehouse: "ANALYTICS_WH"
$$;

-- =============================================================================
-- SECTION 10: ACCESS GRANTS
-- =============================================================================

GRANT USAGE ON DATABASE RISK_FRAUD_COPILOT TO ROLE ANALYST;
GRANT USAGE ON ALL SCHEMAS IN DATABASE RISK_FRAUD_COPILOT TO ROLE ANALYST;
GRANT USAGE ON WAREHOUSE ANALYST_WH TO ROLE ANALYST;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE ANALYST;
GRANT SELECT ON ALL TABLES IN DATABASE RISK_FRAUD_COPILOT TO ROLE ANALYST;
GRANT SELECT ON ALL DYNAMIC TABLES IN DATABASE RISK_FRAUD_COPILOT TO ROLE ANALYST;
GRANT REFERENCES, SELECT ON SEMANTIC VIEW RISK_FRAUD_COPILOT.SEMANTIC.RISK_FRAUD_INTELLIGENCE TO ROLE ANALYST;
GRANT USAGE ON CORTEX SEARCH SERVICE RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_SEARCH TO ROLE ANALYST;
GRANT USAGE ON AGENT RISK_FRAUD_COPILOT.APP.RISK_FRAUD_AGENT TO ROLE ANALYST;
GRANT USAGE ON PROCEDURE RISK_FRAUD_COPILOT.APP.GENERATE_SAR_REPORT(VARCHAR, VARCHAR, VARCHAR) TO ROLE ANALYST;
GRANT USAGE ON PROCEDURE RISK_FRAUD_COPILOT.APP.CREATE_INVESTIGATION_CASE(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE ANALYST;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ANALYST;
