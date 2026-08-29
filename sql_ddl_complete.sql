-- ============================================================
-- RISK, FRAUD & REGULATORY INTELLIGENCE COPILOT
-- Complete DDL & DML Script
-- Database: RISK_FRAUD_COPILOT
-- ============================================================

-- ============================================================
-- SECTION 1: DATABASE & SCHEMA CREATION
-- ============================================================

CREATE DATABASE IF NOT EXISTS RISK_FRAUD_COPILOT;

USE DATABASE RISK_FRAUD_COPILOT;
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS PROCESSED;
CREATE SCHEMA IF NOT EXISTS SEMANTIC;
CREATE SCHEMA IF NOT EXISTS DOCUMENTS;
CREATE SCHEMA IF NOT EXISTS APP;

-- Warehouses
CREATE WAREHOUSE IF NOT EXISTS ANALYTICS_WH WITH WAREHOUSE_SIZE = 'SMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;

-- ============================================================
-- SECTION 2: RAW TABLES (DDL + Data Generation)
-- ============================================================

-- 2.1 Accounts Table
CREATE OR REPLACE TABLE RISK_FRAUD_COPILOT.RAW.ACCOUNTS (
    account_id VARCHAR(20),
    customer_name VARCHAR(100),
    account_type VARCHAR(20),
    kyc_status VARCHAR(20),
    risk_tier VARCHAR(10),
    opened_date DATE,
    country VARCHAR(50),
    annual_income NUMBER(12,2),
    pep_flag BOOLEAN,
    sanctions_flag BOOLEAN
);

INSERT INTO RISK_FRAUD_COPILOT.RAW.ACCOUNTS
SELECT
    'ACC' || LPAD(SEQ4()::VARCHAR, 7, '0') AS account_id,
    CASE MOD(SEQ4(), 20)
        WHEN 0 THEN 'Rajesh Kumar' WHEN 1 THEN 'Priya Sharma' WHEN 2 THEN 'Mohammed Ali'
        WHEN 3 THEN 'Sneha Patel' WHEN 4 THEN 'Vikram Singh' WHEN 5 THEN 'Anita Reddy'
        WHEN 6 THEN 'Amit Gupta' WHEN 7 THEN 'Deepika Nair' WHEN 8 THEN 'Suresh Iyer'
        WHEN 9 THEN 'Kavitha Rao' WHEN 10 THEN 'Rahul Mehta' WHEN 11 THEN 'Pooja Verma'
        WHEN 12 THEN 'Arjun Desai' WHEN 13 THEN 'Meera Joshi' WHEN 14 THEN 'Kiran Bhat'
        WHEN 15 THEN 'Sanjay Pillai' WHEN 16 THEN 'Ritu Agarwal' WHEN 17 THEN 'Naveen Kulkarni'
        WHEN 18 THEN 'Lakshmi Menon' ELSE 'Arun Thakur'
    END AS customer_name,
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'SAVINGS' WHEN 1 THEN 'CURRENT' WHEN 2 THEN 'LOAN' ELSE 'CREDIT_CARD'
    END AS account_type,
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'VERIFIED' WHEN 1 THEN 'VERIFIED' WHEN 2 THEN 'VERIFIED'
        WHEN 3 THEN 'PENDING' ELSE 'EXPIRED'
    END AS kyc_status,
    CASE 
        WHEN MOD(SEQ4(), 20) = 0 THEN 'HIGH'
        WHEN MOD(SEQ4(), 5) = 0 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS risk_tier,
    DATEADD(day, -UNIFORM(30, 2000, RANDOM()), CURRENT_DATE()) AS opened_date,
    CASE MOD(SEQ4(), 8)
        WHEN 0 THEN 'India' WHEN 1 THEN 'India' WHEN 2 THEN 'India' WHEN 3 THEN 'India'
        WHEN 4 THEN 'UAE' WHEN 5 THEN 'Singapore' WHEN 6 THEN 'Nigeria' ELSE 'Russia'
    END AS country,
    UNIFORM(200000, 50000000, RANDOM())::NUMBER(12,2) AS annual_income,
    CASE WHEN MOD(SEQ4(), 50) = 0 THEN TRUE ELSE FALSE END AS pep_flag,
    CASE WHEN MOD(SEQ4(), 100) = 0 THEN TRUE ELSE FALSE END AS sanctions_flag
FROM TABLE(GENERATOR(ROWCOUNT => 5000));

-- 2.2 Transactions Table
CREATE OR REPLACE TABLE RISK_FRAUD_COPILOT.RAW.TRANSACTIONS (
    txn_id VARCHAR(20),
    account_id VARCHAR(20),
    txn_timestamp TIMESTAMP_NTZ,
    amount NUMBER(12,2),
    currency VARCHAR(3),
    txn_type VARCHAR(20),
    merchant_category VARCHAR(50),
    merchant_country VARCHAR(50),
    channel VARCHAR(20),
    is_international BOOLEAN,
    fraud_label BOOLEAN
);

-- Normal transactions
INSERT INTO RISK_FRAUD_COPILOT.RAW.TRANSACTIONS
SELECT
    'TXN' || LPAD(SEQ4()::VARCHAR, 10, '0') AS txn_id,
    'ACC' || LPAD(UNIFORM(0, 4999, RANDOM())::VARCHAR, 7, '0') AS account_id,
    DATEADD(second, -UNIFORM(0, 2592000, RANDOM()), CURRENT_TIMESTAMP()) AS txn_timestamp,
    UNIFORM(100, 500000, RANDOM())::NUMBER(12,2) AS amount,
    'INR' AS currency,
    CASE MOD(SEQ4(), 6)
        WHEN 0 THEN 'DEBIT' WHEN 1 THEN 'CREDIT' WHEN 2 THEN 'TRANSFER'
        WHEN 3 THEN 'ATM' WHEN 4 THEN 'POS' ELSE 'ONLINE'
    END AS txn_type,
    CASE MOD(SEQ4(), 10)
        WHEN 0 THEN 'RETAIL' WHEN 1 THEN 'GROCERIES' WHEN 2 THEN 'FUEL'
        WHEN 3 THEN 'RESTAURANT' WHEN 4 THEN 'UTILITIES' WHEN 5 THEN 'INSURANCE'
        WHEN 6 THEN 'INVESTMENT' WHEN 7 THEN 'REAL_ESTATE' WHEN 8 THEN 'CRYPTO' ELSE 'GAMBLING'
    END AS merchant_category,
    CASE MOD(SEQ4(), 10)
        WHEN 0 THEN 'India' WHEN 1 THEN 'India' WHEN 2 THEN 'India' WHEN 3 THEN 'India'
        WHEN 4 THEN 'India' WHEN 5 THEN 'UAE' WHEN 6 THEN 'Singapore'
        WHEN 7 THEN 'Nigeria' WHEN 8 THEN 'Russia' ELSE 'Cayman Islands'
    END AS merchant_country,
    CASE MOD(SEQ4(), 4) WHEN 0 THEN 'MOBILE' WHEN 1 THEN 'WEB' WHEN 2 THEN 'BRANCH' ELSE 'ATM' END AS channel,
    CASE WHEN MOD(SEQ4(), 10) >= 5 AND MOD(SEQ4(), 10) <= 9 AND MOD(SEQ4(), 3) = 0 THEN TRUE ELSE FALSE END AS is_international,
    FALSE AS fraud_label
FROM TABLE(GENERATOR(ROWCOUNT => 50000));

-- Inject fraud patterns: rapid-fire transactions (velocity abuse)
INSERT INTO RISK_FRAUD_COPILOT.RAW.TRANSACTIONS
SELECT
    'TXN' || LPAD((50000 + SEQ4())::VARCHAR, 10, '0') AS txn_id,
    'ACC' || LPAD(UNIFORM(0, 100, RANDOM())::VARCHAR, 7, '0') AS account_id,
    DATEADD(second, -SEQ4() * 10, CURRENT_TIMESTAMP()) AS txn_timestamp,
    UNIFORM(8000, 9900, RANDOM())::NUMBER(12,2) AS amount,
    'INR' AS currency,
    'ONLINE' AS txn_type,
    'CRYPTO' AS merchant_category,
    CASE MOD(SEQ4(), 3) WHEN 0 THEN 'Nigeria' WHEN 1 THEN 'Russia' ELSE 'Cayman Islands' END AS merchant_country,
    'WEB' AS channel,
    TRUE AS is_international,
    TRUE AS fraud_label
FROM TABLE(GENERATOR(ROWCOUNT => 500));

-- Inject AML structuring pattern: multiple txns just below reporting threshold
INSERT INTO RISK_FRAUD_COPILOT.RAW.TRANSACTIONS
SELECT
    'TXN' || LPAD((50500 + SEQ4())::VARCHAR, 10, '0') AS txn_id,
    'ACC' || LPAD(UNIFORM(100, 200, RANDOM())::VARCHAR, 7, '0') AS account_id,
    DATEADD(hour, -UNIFORM(0, 720, RANDOM()), CURRENT_TIMESTAMP()) AS txn_timestamp,
    UNIFORM(490000, 499999, RANDOM())::NUMBER(12,2) AS amount,
    'INR' AS currency,
    'TRANSFER' AS txn_type,
    'REAL_ESTATE' AS merchant_category,
    'India' AS merchant_country,
    'WEB' AS channel,
    FALSE AS is_international,
    TRUE AS fraud_label
FROM TABLE(GENERATOR(ROWCOUNT => 300));

-- 2.3 KYC Records
CREATE OR REPLACE TABLE RISK_FRAUD_COPILOT.RAW.KYC_RECORDS (
    kyc_id VARCHAR(20),
    account_id VARCHAR(20),
    doc_type VARCHAR(30),
    doc_number VARCHAR(50),
    verified_date DATE,
    expiry_date DATE,
    verification_method VARCHAR(20),
    risk_flags VARCHAR(200)
);

INSERT INTO RISK_FRAUD_COPILOT.RAW.KYC_RECORDS
SELECT
    'KYC' || LPAD(SEQ4()::VARCHAR, 7, '0') AS kyc_id,
    'ACC' || LPAD(UNIFORM(0, 4999, RANDOM())::VARCHAR, 7, '0') AS account_id,
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'AADHAAR' WHEN 1 THEN 'PAN' WHEN 2 THEN 'PASSPORT' ELSE 'VOTER_ID'
    END AS doc_type,
    'DOC' || LPAD(UNIFORM(100000, 999999, RANDOM())::VARCHAR, 10, '0') AS doc_number,
    DATEADD(day, -UNIFORM(30, 1000, RANDOM()), CURRENT_DATE()) AS verified_date,
    DATEADD(day, UNIFORM(0, 1800, RANDOM()), CURRENT_DATE()) AS expiry_date,
    CASE MOD(SEQ4(), 3) WHEN 0 THEN 'E_VERIFY' WHEN 1 THEN 'IN_PERSON' ELSE 'VIDEO_KYC' END AS verification_method,
    CASE 
        WHEN MOD(SEQ4(), 20) = 0 THEN 'ADDRESS_MISMATCH'
        WHEN MOD(SEQ4(), 30) = 0 THEN 'DOC_EXPIRED'
        WHEN MOD(SEQ4(), 50) = 0 THEN 'MULTIPLE_ACCOUNTS_SAME_DOC'
        ELSE NULL
    END AS risk_flags
FROM TABLE(GENERATOR(ROWCOUNT => 8000));

-- 2.4 High-risk countries reference
CREATE OR REPLACE TABLE RISK_FRAUD_COPILOT.RAW.HIGH_RISK_COUNTRIES (
    country VARCHAR(50),
    risk_category VARCHAR(20),
    fatf_status VARCHAR(30),
    notes VARCHAR(200)
);

INSERT INTO RISK_FRAUD_COPILOT.RAW.HIGH_RISK_COUNTRIES VALUES
('Nigeria', 'HIGH', 'GREY_LIST', 'FATF grey list - enhanced due diligence required'),
('Russia', 'HIGH', 'BLACK_LIST', 'Sanctioned jurisdiction - block all new relationships'),
('Cayman Islands', 'MEDIUM', 'MONITORED', 'Tax haven - enhanced monitoring for shell companies'),
('Iran', 'HIGH', 'BLACK_LIST', 'Comprehensive sanctions - no transactions permitted'),
('North Korea', 'HIGH', 'BLACK_LIST', 'Comprehensive sanctions - no transactions permitted'),
('Myanmar', 'HIGH', 'GREY_LIST', 'FATF grey list - enhanced due diligence required'),
('Pakistan', 'MEDIUM', 'GREY_LIST', 'FATF grey list - transaction monitoring required'),
('Panama', 'MEDIUM', 'MONITORED', 'Tax haven - enhanced monitoring');

-- 2.5 Regulatory thresholds reference
CREATE OR REPLACE TABLE RISK_FRAUD_COPILOT.RAW.REGULATORY_THRESHOLDS (
    regulation VARCHAR(50),
    threshold_name VARCHAR(100),
    threshold_value NUMBER(12,2),
    currency VARCHAR(3),
    action_required VARCHAR(200)
);

INSERT INTO RISK_FRAUD_COPILOT.RAW.REGULATORY_THRESHOLDS VALUES
('RBI_AML', 'Cash Transaction Report', 1000000, 'INR', 'File CTR with FIU-IND within 15 days'),
('RBI_AML', 'Suspicious Transaction Report', 0, 'INR', 'File STR with FIU-IND within 7 days'),
('RBI_AML', 'Cross-border Wire Threshold', 500000, 'INR', 'Enhanced due diligence and reporting'),
('BASEL_III', 'Minimum Capital Ratio', 8, 'PCT', 'Maintain CET1 ratio above threshold'),
('BASEL_III', 'Liquidity Coverage Ratio', 100, 'PCT', 'Maintain LCR at or above 100%'),
('PMLA', 'Structuring Detection', 500000, 'INR', 'Flag transactions structured to avoid reporting'),
('FATF', 'PEP Enhanced Due Diligence', 0, 'INR', 'Apply enhanced due diligence for all PEP accounts');

-- ============================================================
-- SECTION 3: REGULATORY DOCUMENTS (for Cortex Search)
-- ============================================================

CREATE OR REPLACE TABLE RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_DOCS (
    doc_id VARCHAR(20),
    doc_title VARCHAR(200),
    doc_category VARCHAR(50),
    section_id INTEGER,
    section_title VARCHAR(200),
    content TEXT,
    effective_date DATE,
    issuing_authority VARCHAR(100)
);

INSERT INTO RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_DOCS VALUES
('DOC001', 'RBI Master Direction on KYC', 'AML', 1, 'Customer Due Diligence', 
 'Banks shall carry out Customer Due Diligence (CDD) at the time of opening accounts, carrying out occasional transactions above Rs. 50,000, when there is suspicion of money laundering or terrorist financing, and when the bank has doubts about the adequacy of previously obtained customer identification data. CDD measures include identifying and verifying the customer identity using reliable independent source documents, identifying the beneficial owner, and understanding the purpose and intended nature of the business relationship.',
 '2024-01-01', 'Reserve Bank of India'),

('DOC001', 'RBI Master Direction on KYC', 'AML', 2, 'Suspicious Transaction Reporting',
 'A Suspicious Transaction Report (STR) must be filed with the Financial Intelligence Unit-India (FIU-IND) within 7 days of the transaction being identified as suspicious. Suspicious transactions include: transactions that are inconsistent with the customer profile, transactions involving high-risk jurisdictions without clear business rationale, rapid movement of funds with no apparent economic purpose, structuring of transactions to avoid reporting thresholds, and transactions involving Politically Exposed Persons (PEPs) without adequate documentation.',
 '2024-01-01', 'Reserve Bank of India'),

('DOC001', 'RBI Master Direction on KYC', 'AML', 3, 'Cash Transaction Reports',
 'All cash transactions of Rs. 10 lakhs and above (or its equivalent in foreign currency) must be reported to FIU-IND in Cash Transaction Reports (CTRs). All series of cash transactions integrally connected to each other which have been valued below Rs. 10 lakhs where such series of transactions have taken place within one month and the aggregate value of such transactions exceeds Rs. 10 lakhs shall also be reported. CTRs must be filed within 15 days of the close of the month in which the transaction was conducted.',
 '2024-01-01', 'Reserve Bank of India'),

('DOC001', 'RBI Master Direction on KYC', 'AML', 4, 'Enhanced Due Diligence for PEPs',
 'For Politically Exposed Persons (PEPs), banks must: obtain senior management approval for establishing business relationships, take reasonable measures to establish the source of wealth and source of funds, conduct enhanced ongoing monitoring of the business relationship. A PEP is defined as an individual who is or has been entrusted with prominent public functions by a foreign country, including Heads of State or Government, senior politicians, senior government officials, judicial or military officials, senior executives of state-owned corporations, and important political party officials.',
 '2024-01-01', 'Reserve Bank of India'),

('DOC001', 'RBI Master Direction on KYC', 'AML', 5, 'Wire Transfer Regulations',
 'For cross-border wire transfers of Rs. 5 lakhs and above, banks must include complete originator information: name, account number, address (or national identity number or customer identification number or date and place of birth). The beneficiary institution must verify the identity of the beneficiary for wire transfers of Rs. 50,000 and above. Banks must maintain records of all wire transfers for a period of 5 years from the date of transaction.',
 '2024-01-01', 'Reserve Bank of India'),

('DOC002', 'Prevention of Money Laundering Act Guidelines', 'AML', 1, 'Structuring and Smurfing',
 'Structuring, also known as smurfing, is the practice of executing financial transactions in a specific pattern calculated to avoid triggering reporting thresholds. Under PMLA, transactions structured to avoid the Rs. 10 lakh CTR threshold or the Rs. 5 lakh cross-border wire threshold are considered suspicious. Indicators include: multiple transactions just below the threshold within a short period, splitting a single large transaction into multiple smaller ones across different branches or channels, and using multiple accounts to conduct transactions that individually fall below thresholds but collectively exceed them.',
 '2023-06-01', 'Government of India'),

('DOC002', 'Prevention of Money Laundering Act Guidelines', 'AML', 2, 'Record Keeping Requirements',
 'Reporting entities must maintain records of all transactions, including attempted transactions, for a minimum period of 5 years from the date of the transaction. Records must include: the nature and value of the transaction, the date of the transaction, the parties to the transaction, all customer identification records obtained through CDD, and all documents obtained in respect of the account holder. Records must be maintained in a manner that allows reconstruction of individual transactions so as to provide evidence for prosecution of criminal activity.',
 '2023-06-01', 'Government of India'),

('DOC003', 'Basel III Capital Adequacy Framework', 'REGULATORY', 1, 'Capital Requirements',
 'Under Basel III as implemented by RBI, banks must maintain: Common Equity Tier 1 (CET1) capital ratio of minimum 5.5% of risk-weighted assets, Total Tier 1 capital ratio of minimum 7%, Total Capital (CRAR) of minimum 9%, Capital Conservation Buffer of 2.5%, and Counter-Cyclical Buffer of 0-2.5% as specified. Additionally, Domestic Systemically Important Banks (D-SIBs) must maintain an additional CET1 surcharge. Non-compliance triggers automatic restrictions on dividend payments, share buybacks, and discretionary bonus payments.',
 '2024-04-01', 'Reserve Bank of India'),

('DOC003', 'Basel III Capital Adequacy Framework', 'REGULATORY', 2, 'Liquidity Coverage Ratio',
 'Banks must maintain a Liquidity Coverage Ratio (LCR) of at least 100%. LCR is calculated as: Stock of High Quality Liquid Assets (HQLA) / Total Net Cash Outflows over 30 calendar days >= 100%. HQLA includes Level 1 assets (cash, central bank reserves, government securities) and Level 2 assets (corporate bonds rated AA- or higher, covered bonds). During stress periods, banks may use their HQLA stock, allowing the LCR to fall below 100%. Banks must report LCR to RBI on a monthly basis.',
 '2024-04-01', 'Reserve Bank of India'),

('DOC003', 'Basel III Capital Adequacy Framework', 'REGULATORY', 3, 'Credit Risk Assessment',
 'Banks must assess credit risk using either the Standardized Approach or the Internal Ratings-Based (IRB) approach. Under the Standardized Approach, risk weights are assigned based on external credit ratings: AAA to AA- rated exposures receive 20% risk weight, A+ to A- receive 50%, BBB+ to BB- receive 100%, and below BB- receive 150%. Unrated corporate exposures receive 100% risk weight. Banks must review their credit risk assessment at least annually and more frequently for deteriorating exposures.',
 '2024-04-01', 'Reserve Bank of India'),

('DOC004', 'Internal Fraud Detection Policy', 'FRAUD', 1, 'Transaction Monitoring Rules',
 'The following patterns must be flagged for immediate review: 1) Velocity: More than 5 transactions from the same account within 1 minute. 2) Amount Anomaly: Transaction exceeding 3 standard deviations from the account 30-day rolling average. 3) Geographic Impossibility: Transactions from two locations more than 500km apart within 1 hour. 4) Channel Switching: ATM withdrawal followed by online transaction in different country within 30 minutes. 5) New Merchant Pattern: First-time transaction with a high-risk merchant category exceeding Rs. 1 lakh. 6) Dormant Account Activation: Account inactive for 6+ months suddenly receiving large deposits.',
 '2024-07-01', 'Internal Compliance'),

('DOC004', 'Internal Fraud Detection Policy', 'FRAUD', 2, 'Investigation and Escalation',
 'When a fraud signal is detected: Level 1 (Automated): System blocks the transaction and sends alert to customer. Level 2 (Analyst Review): If customer confirms fraud or signal score > 0.8, escalate to fraud analyst for investigation within 4 hours. Level 3 (Senior Review): Cases involving amounts > Rs. 10 lakhs or PEP accounts must be reviewed by senior fraud manager within 24 hours. Level 4 (Regulatory Filing): Confirmed fraud cases must be reported to RBI within 21 days for amounts > Rs. 1 crore. All cases must be logged in the central fraud registry with complete evidence chain.',
 '2024-07-01', 'Internal Compliance'),

('DOC004', 'Internal Fraud Detection Policy', 'FRAUD', 3, 'SAR Filing Requirements',
 'A Suspicious Activity Report (SAR) must be filed when: the transaction involves proceeds from illegal activity, the transaction is designed to evade reporting requirements, the transaction has no lawful purpose or is not the type the customer would normally conduct, or the transaction involves the use of the institution to facilitate criminal activity. The SAR must include: subject information, suspicious activity details, narrative describing why the activity is suspicious, and all supporting documentation. SARs must be filed within 7 days of detection and maintained confidentially for 5 years.',
 '2024-07-01', 'Internal Compliance');

-- ============================================================
-- SECTION 4: DYNAMIC TABLES (Signal Detection Pipelines)
-- ============================================================

-- 4.1 Fraud Signals Detection
CREATE OR REPLACE DYNAMIC TABLE RISK_FRAUD_COPILOT.PROCESSED.FRAUD_SIGNALS
    TARGET_LAG = '1 minute'
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
    ROUND(
        CASE 
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

-- 4.2 AML Flags Detection
CREATE OR REPLACE DYNAMIC TABLE RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS
    TARGET_LAG = '1 minute'
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
    s.account_id,
    s.txn_date AS flag_date,
    'STRUCTURING' AS flag_type,
    'Potential structuring: ' || s.txn_count_day || ' transactions totaling ' || s.total_amount_day || ' with max ' || s.max_single_txn AS description,
    'HIGH' AS severity,
    'FILE_STR' AS required_action,
    0.85 AS confidence_score
FROM structuring_detection s

UNION ALL

SELECT 
    h.account_id,
    h.txn_date AS flag_date,
    'HIGH_VALUE_INTERNATIONAL' AS flag_type,
    'High-value international transfers: ' || h.intl_txn_count || ' transactions totaling ' || h.total_intl_amount AS description,
    'HIGH' AS severity,
    'ENHANCED_DUE_DILIGENCE' AS required_action,
    0.80 AS confidence_score
FROM high_value_international h

UNION ALL

SELECT 
    p.account_id,
    p.txn_date AS flag_date,
    'PEP_ACTIVITY' AS flag_type,
    'PEP account activity: ' || p.pep_txn_count || ' transactions totaling ' || p.pep_total_amount AS description,
    'MEDIUM' AS severity,
    'SENIOR_REVIEW' AS required_action,
    0.75 AS confidence_score
FROM pep_transactions p;

-- 4.3 Risk Scores
CREATE OR REPLACE DYNAMIC TABLE RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES
    TARGET_LAG = '1 minute'
    WAREHOUSE = COMPUTE_WH
AS
WITH txn_metrics AS (
    SELECT 
        account_id,
        COUNT(*) AS total_txns,
        SUM(amount) AS total_volume,
        AVG(amount) AS avg_txn_amount,
        MAX(amount) AS max_txn_amount,
        COUNT(CASE WHEN is_international THEN 1 END) AS intl_txn_count,
        COUNT(CASE WHEN fraud_label THEN 1 END) AS fraud_txn_count,
        SUM(CASE WHEN merchant_category IN ('CRYPTO', 'GAMBLING') THEN amount ELSE 0 END) AS high_risk_volume,
        DATEDIFF(day, MIN(txn_timestamp), MAX(txn_timestamp)) AS active_days
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

-- ============================================================
-- SECTION 5: CORTEX SEARCH SERVICE
-- ============================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_SEARCH
    ON content
    ATTRIBUTES doc_title, doc_category, section_title, issuing_authority
    WAREHOUSE = COMPUTE_WH
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

-- ============================================================
-- SECTION 6: SEMANTIC VIEW (Ontology)
-- ============================================================

CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'RISK_FRAUD_COPILOT.SEMANTIC',
  $$
name: RISK_FRAUD_INTELLIGENCE
description: "Risk, Fraud and Regulatory Intelligence ontology for compliance copilot"
tables:
  - name: accounts
    base_table:
      database: RISK_FRAUD_COPILOT
      schema: RAW
      table: ACCOUNTS
    description: "Customer accounts with KYC status and risk classification"
    primary_key:
      columns: [account_id]
    dimensions:
      - name: account_id
        expr: account_id
        description: "Unique account identifier"
      - name: customer_name
        expr: customer_name
        description: "Customer full name"
      - name: account_type
        expr: account_type
        description: "Account type: SAVINGS, CURRENT, LOAN, CREDIT_CARD"
        is_enum: true
        sample_values: ["SAVINGS", "CURRENT", "LOAN", "CREDIT_CARD"]
      - name: kyc_status
        expr: kyc_status
        description: "KYC verification status"
        is_enum: true
        sample_values: ["VERIFIED", "PENDING", "EXPIRED"]
      - name: risk_tier
        expr: risk_tier
        description: "Assigned risk tier"
        is_enum: true
        sample_values: ["LOW", "MEDIUM", "HIGH"]
      - name: country
        expr: country
        description: "Customer country"
      - name: pep_flag
        expr: pep_flag
        description: "Whether customer is a Politically Exposed Person"
      - name: sanctions_flag
        expr: sanctions_flag
        description: "Whether customer is on sanctions list"
    time_dimensions:
      - name: opened_date
        expr: opened_date
        description: "Date account was opened"
        data_type: DATE
    metrics:
      - name: total_accounts
        expr: "COUNT(account_id)"
        description: "Total number of accounts"
      - name: high_risk_account_count
        expr: "COUNT(CASE WHEN risk_tier = 'HIGH' THEN 1 END)"
        description: "Number of high-risk accounts"
      - name: pep_count
        expr: "COUNT(CASE WHEN pep_flag = TRUE THEN 1 END)"
        description: "Number of PEP accounts"

  - name: fraud_signals
    base_table:
      database: RISK_FRAUD_COPILOT
      schema: PROCESSED
      table: FRAUD_SIGNALS
    description: "Detected fraud signals from transaction monitoring"
    dimensions:
      - name: txn_id
        expr: txn_id
        description: "Transaction that triggered the signal"
      - name: account_id
        expr: account_id
        description: "Account associated with the fraud signal"
      - name: signal_type
        expr: signal_type
        description: "Type of fraud signal"
        is_enum: true
        sample_values: ["VELOCITY_1MIN", "VELOCITY_1HR", "AMOUNT_ANOMALY", "HIGH_RISK_COUNTRY", "HIGH_RISK_CATEGORY"]
      - name: severity
        expr: severity
        description: "Signal severity level"
        is_enum: true
        sample_values: ["CRITICAL", "HIGH", "MEDIUM", "LOW"]
      - name: merchant_country
        expr: merchant_country
        description: "Country where suspicious activity occurred"
      - name: merchant_category
        expr: merchant_category
        description: "Merchant category of suspicious transaction"
    time_dimensions:
      - name: signal_timestamp
        expr: signal_timestamp
        description: "When the fraud signal was detected"
        data_type: TIMESTAMP
    metrics:
      - name: total_signals
        expr: "COUNT(*)"
        description: "Total number of fraud signals"
      - name: critical_signals
        expr: "COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END)"
        description: "Number of critical severity signals"
      - name: avg_confidence
        expr: "AVG(confidence_score)"
        description: "Average confidence score"
      - name: total_flagged_amount
        expr: "SUM(amount)"
        description: "Total monetary amount of flagged transactions"

  - name: aml_flags
    base_table:
      database: RISK_FRAUD_COPILOT
      schema: PROCESSED
      table: AML_FLAGS
    description: "Anti-Money Laundering flags"
    dimensions:
      - name: account_id
        expr: account_id
        description: "Account flagged for AML concerns"
      - name: flag_type
        expr: flag_type
        description: "Type of AML flag"
        is_enum: true
        sample_values: ["STRUCTURING", "HIGH_VALUE_INTERNATIONAL", "PEP_ACTIVITY"]
      - name: severity
        expr: severity
        description: "Flag severity"
        is_enum: true
        sample_values: ["HIGH", "MEDIUM", "LOW"]
      - name: required_action
        expr: required_action
        description: "Required regulatory action"
        is_enum: true
        sample_values: ["FILE_STR", "ENHANCED_DUE_DILIGENCE", "SENIOR_REVIEW"]
      - name: description
        expr: description
        description: "Detailed description of the AML flag"
    time_dimensions:
      - name: flag_date
        expr: flag_date
        description: "Date when AML flag was raised"
        data_type: DATE
    metrics:
      - name: total_aml_flags
        expr: "COUNT(*)"
        description: "Total number of AML flags"
      - name: structuring_flags
        expr: "COUNT(CASE WHEN flag_type = 'STRUCTURING' THEN 1 END)"
        description: "Number of structuring detection flags"

  - name: risk_scores
    base_table:
      database: RISK_FRAUD_COPILOT
      schema: PROCESSED
      table: RISK_SCORES
    description: "Composite risk scores per account"
    primary_key:
      columns: [account_id]
    dimensions:
      - name: account_id
        expr: account_id
        description: "Account identifier"
      - name: customer_name
        expr: customer_name
        description: "Customer name"
      - name: fraud_risk_level
        expr: fraud_risk_level
        description: "Computed fraud risk level"
        is_enum: true
        sample_values: ["HIGH", "MEDIUM", "LOW"]
      - name: compliance_risk_level
        expr: compliance_risk_level
        description: "Computed compliance risk level"
        is_enum: true
        sample_values: ["HIGH", "MEDIUM", "LOW"]
      - name: assigned_tier
        expr: assigned_tier
        description: "Originally assigned risk tier"
    metrics:
      - name: avg_risk_score
        expr: "AVG(composite_risk_score)"
        description: "Average composite risk score"
      - name: high_risk_accounts
        expr: "COUNT(CASE WHEN composite_risk_score > 50 THEN 1 END)"
        description: "Accounts with risk score above 50"
      - name: total_exposure
        expr: "SUM(total_transaction_volume)"
        description: "Total transaction volume exposure"

relationships:
  - name: account_fraud_signals
    left_table: fraud_signals
    right_table: accounts
    relationship_columns:
      - left_column: account_id
        right_column: account_id
  - name: account_aml_flags
    left_table: aml_flags
    right_table: accounts
    relationship_columns:
      - left_column: account_id
        right_column: account_id
  - name: account_risk_scores
    left_table: risk_scores
    right_table: accounts
    relationship_columns:
      - left_column: account_id
        right_column: account_id

verified_queries:
  - name: "high_risk_accounts_summary"
    question: "Which accounts have the highest risk scores?"
    sql: "SELECT account_id, customer_name, composite_risk_score, fraud_risk_level, compliance_risk_level, total_transaction_volume FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES WHERE composite_risk_score > 50 ORDER BY composite_risk_score DESC LIMIT 20"
    verified_at: 1724284800
    verified_by: "admin"
  - name: "aml_alerts_requiring_sar"
    question: "Which accounts triggered AML alerts that require SAR filing?"
    sql: "SELECT a.account_id, a.flag_type, a.description, a.flag_date, a.severity, a.required_action, r.customer_name, r.composite_risk_score FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS a JOIN RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES r ON a.account_id = r.account_id WHERE a.required_action = 'FILE_STR' ORDER BY a.flag_date DESC"
    verified_at: 1724284800
    verified_by: "admin"
  - name: "fraud_signals_this_week"
    question: "What fraud signals were detected this week?"
    sql: "SELECT signal_type, severity, COUNT(*) as signal_count, SUM(amount) as total_amount, AVG(confidence_score) as avg_confidence FROM RISK_FRAUD_COPILOT.PROCESSED.FRAUD_SIGNALS WHERE signal_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP()) GROUP BY signal_type, severity ORDER BY signal_count DESC"
    verified_at: 1724284800
    verified_by: "admin"
  - name: "portfolio_risk_by_tier"
    question: "What is the portfolio risk exposure by tier?"
    sql: "SELECT assigned_tier, COUNT(*) as account_count, AVG(composite_risk_score) as avg_risk_score, SUM(total_transaction_volume) as total_exposure FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES GROUP BY assigned_tier ORDER BY avg_risk_score DESC"
    verified_at: 1724284800
    verified_by: "admin"
  - name: "structuring_detection"
    question: "Show me accounts with potential structuring activity"
    sql: "SELECT a.account_id, r.customer_name, a.flag_date, a.description, a.confidence_score, r.composite_risk_score FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS a JOIN RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES r ON a.account_id = r.account_id WHERE a.flag_type = 'STRUCTURING' ORDER BY a.confidence_score DESC"
    verified_at: 1724284800
    verified_by: "admin"

module_custom_instructions:
  sql_generation: |
    Always include the account_id and customer_name in results for traceability.
    When querying risk scores, include the composite_risk_score.
    Round all numeric values to 2 decimal places.
    For time-based queries, default to the last 30 days unless specified.
  question_categorization: |
    This semantic view covers risk, fraud, and AML compliance topics only.
    Reject questions unrelated to banking risk, fraud detection, or regulatory compliance.
    If a question asks about a specific account without providing an account_id, ask for clarification.
  $$
);

-- ============================================================
-- SECTION 7: CORTEX AGENT
-- ============================================================

CREATE OR REPLACE AGENT RISK_FRAUD_COPILOT.APP.RISK_FRAUD_AGENT
  COMMENT = 'Risk, Fraud and Regulatory Intelligence Copilot for banking compliance teams'
  FROM SPECIFICATION
  $$
  models:
    orchestration: claude sonnet 4.5

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
      - Keep total response under 500 words. Summarize data tables concisely rather than repeating raw output verbatim.
      - When presenting query results, show key insights and summary statistics, not full row-by-row dumps.

      EVIDENCE AND CITATIONS:
      - When citing regulatory documents from search results, format as: [Source: {doc_title} > {section_title}]
      - When presenting data results, include context: "Based on {N} matching records with average confidence {X}"
      - Structure every finding as: SIGNAL -> EVIDENCE -> FINDING -> RECOMMENDED ACTION
      - If any AML flag has confidence_score < 0.7, append: "Low confidence flag detected. Manual verification recommended before action."

      GUARDRAILS:
      - OFF-TOPIC (restaurants, weather, sports, personal): Reply "I can only assist with risk, fraud, and regulatory compliance topics. Please ask a question related to banking risk, AML, fraud detection, or regulatory requirements."
      - PII REQUESTS (home address, phone, ID numbers): Reply "I cannot disclose personal information for privacy and compliance reasons."
      - AUTO-SUBMIT REQUESTS: Reply "I can only generate DRAFT filings. All regulatory submissions require human review and approval before filing with FIU-IND."
      - NEVER fabricate numbers. Always use tool results.
      - CONFIDENCE THRESHOLD: When confidence_score < 0.5, explicitly state "Insufficient confidence for automated action. Escalate to senior compliance officer."

    orchestration: |
      ROUTING DECISION TREE - follow this exactly:

      STEP 1: Is the question off-topic (not about risk/fraud/AML/compliance)?
        YES → Answer directly with refusal. Do NOT call any tool.

      STEP 2: Does the question ask about REGULATIONS, POLICIES, REQUIREMENTS, GUIDELINES, or LEGAL RULES?
        Look for: "RBI", "requirement", "guideline", "regulation", "policy", "threshold", "filing deadline", "what does the law say", "regulatory basis", "due diligence", "CTR", "STR timeline", "PMLA", "FATF", "Basel", "what constitutes", "reporting requirements", "KYC requirements per RBI", "Enhanced Due Diligence requirements"
        YES → Use RegulatorySearch

      STEP 3: Does the question explicitly ask to GENERATE/CREATE/DRAFT a SAR or STR filing?
        Look for: "generate SAR", "create SAR", "draft SAR", "file STR", "produce SAR"
        YES → Use GenerateSAR tool with parameters (P_ACCOUNT_ID, P_FLAG_TYPE, P_EVIDENCE_SUMMARY)

      STEP 4: Does the question explicitly ask to OPEN/CREATE an investigation CASE?
        Look for: "open case", "create case", "open investigation", "start investigation"
        YES → Use CreateCase tool with parameters (P_ACCOUNT_ID, P_CASE_TYPE, P_PRIORITY, P_FINDINGS)

      STEP 5: All other questions about DATA, ACCOUNTS, TRANSACTIONS, SIGNALS, FLAGS, SCORES, COUNTS, TRENDS → Use RiskDataAnalyst

      MULTI-TOOL QUESTIONS (question has TWO parts):
      - "regulatory basis AND which accounts need filing" → RegulatorySearch FIRST, then RiskDataAnalyst
      - "look up flags AND generate SAR if found" → RiskDataAnalyst FIRST, then GenerateSAR
      - "find highest risk account AND create case" → RiskDataAnalyst FIRST, then CreateCase

      CRITICAL DISTINCTIONS:
      - "What are the KYC requirements per RBI?" → RegulatorySearch (asking about RULES)
      - "How many accounts have expired KYC?" → RiskDataAnalyst (asking about DATA)
      - "What is the STR filing threshold?" → RegulatorySearch (asking about RULES)
      - "Which accounts need STR filing?" → RiskDataAnalyst (asking about DATA)
      - "What constitutes suspicious transaction under RBI?" → RegulatorySearch (asking about DEFINITION)
      - "Show me suspicious transactions" → RiskDataAnalyst (asking about DATA)

    sample_questions:
      - question: "Which accounts triggered AML alerts this week?"
      - question: "What is the SAR filing threshold under RBI guidelines?"
      - question: "Show me the top 10 highest risk accounts"
      - question: "What are the structuring detection rules?"
      - question: "What is the portfolio risk exposure by tier?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "Analyst"
        description: "Queries structured risk, fraud, and AML data including fraud signals, AML flags, risk scores, and account information. Use for quantitative questions about accounts, transactions, alerts, and risk metrics."
    - tool_spec:
        type: "cortex_search"
        name: "RegSearch"
        description: "Searches regulatory policy documents including RBI KYC directions, PMLA guidelines, Basel III framework, and internal fraud detection policies. Use for regulatory threshold questions, compliance requirements, and policy lookups."

  tool_resources:
    Analyst:
      semantic_view: "RISK_FRAUD_COPILOT.SEMANTIC.RISK_FRAUD_INTELLIGENCE"
    RegSearch:
      search_service: "RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_SEARCH"
      max_results: "3"
      title_column: "section_title"
      columns_and_descriptions:
        CONTENT:
          description: "The regulatory policy text content"
          type: "string"
          searchable: true
          filterable: false
        DOC_TITLE:
          description: "Title of the regulatory document"
          type: "string"
          searchable: false
          filterable: true
        DOC_CATEGORY:
          description: "Category of the document: AML, REGULATORY, or FRAUD"
          type: "string"
          searchable: false
          filterable: true
        SECTION_TITLE:
          description: "Section heading within the document"
          type: "string"
          searchable: true
          filterable: false
  $$;

-- ============================================================
-- SECTION 8: STREAMLIT APP & STORED PROCEDURES
-- ============================================================

CREATE STAGE IF NOT EXISTS RISK_FRAUD_COPILOT.APP.STREAMLIT_STAGE;

CREATE OR REPLACE STREAMLIT RISK_FRAUD_COPILOT.APP.RISK_FRAUD_DASHBOARD
    ROOT_LOCATION = '@RISK_FRAUD_COPILOT.APP.STREAMLIT_STAGE'
    MAIN_FILE = '/streamlit_app.py'
    QUERY_WAREHOUSE = COMPUTE_WH
    TITLE = 'Risk, Fraud & Regulatory Intelligence Copilot';

-- Custom tool: Audit Finding Generator
CREATE OR REPLACE PROCEDURE RISK_FRAUD_COPILOT.APP.GENERATE_AUDIT_FINDING(
    ACCOUNT_ID_INPUT VARCHAR,
    FINDING_TYPE VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
BEGIN
    LET result VARCHAR DEFAULT '';
    
    SELECT OBJECT_CONSTRUCT(
        'finding_id', 'FND-' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD-HH24MISS'),
        'account_id', :ACCOUNT_ID_INPUT,
        'finding_type', :FINDING_TYPE,
        'generated_at', CURRENT_TIMESTAMP()::VARCHAR,
        'risk_score', composite_risk_score,
        'fraud_risk_level', fraud_risk_level,
        'customer_name', customer_name,
        'fraud_signals', flagged_transaction_count,
        'status', 'PENDING_REVIEW'
    )::VARCHAR INTO :result
    FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES 
    WHERE account_id = :ACCOUNT_ID_INPUT;
    
    RETURN result;
END;

-- ============================================================
-- SECTION 9: ADDITIONAL TABLES (Case Management & Audit)
-- ============================================================

-- 9.1 Audit Log Table
CREATE OR REPLACE TABLE RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG (
    LOG_ID VARCHAR(36) DEFAULT UUID_STRING(),
    ACTION_TIMESTAMP TIMESTAMP_LTZ(9) DEFAULT CURRENT_TIMESTAMP(),
    USER_ID VARCHAR(100),
    ACTION_TYPE VARCHAR(50),
    ENTITY_TYPE VARCHAR(30),
    ENTITY_ID VARCHAR(50),
    QUERY_TEXT VARCHAR(16777216),
    RESPONSE_SUMMARY VARCHAR(16777216),
    CONFIDENCE_SCORE NUMBER(3,2),
    METADATA VARIANT
);

-- 9.2 Case Management Table
CREATE OR REPLACE TABLE RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT (
    CASE_ID VARCHAR(20),
    ACCOUNT_ID VARCHAR(20) NOT NULL,
    CASE_TYPE VARCHAR(30) NOT NULL,
    STATUS VARCHAR(20) DEFAULT 'OPEN',
    PRIORITY VARCHAR(10),
    CREATED_AT TIMESTAMP_LTZ(9) DEFAULT CURRENT_TIMESTAMP(),
    ASSIGNED_TO VARCHAR(100),
    FINDINGS VARCHAR(16777216),
    RESOLUTION VARCHAR(16777216),
    CLOSED_AT TIMESTAMP_LTZ(9),
    LINKED_SAR_ID VARCHAR(20)
);

-- 9.3 SAR Filings Table
CREATE OR REPLACE TABLE RISK_FRAUD_COPILOT.PROCESSED.SAR_FILINGS (
    SAR_ID VARCHAR(20),
    ACCOUNT_ID VARCHAR(20) NOT NULL,
    FILING_DATE TIMESTAMP_LTZ(9) DEFAULT CURRENT_TIMESTAMP(),
    REPORT_TYPE VARCHAR(20) NOT NULL,
    STATUS VARCHAR(20) DEFAULT 'DRAFT',
    NARRATIVE VARCHAR(16777216),
    EVIDENCE_JSON VARIANT,
    REGULATORY_BODY VARCHAR(50),
    GENERATED_BY VARCHAR(50) DEFAULT 'COPILOT_AGENT',
    REVIEWED_BY VARCHAR(100),
    SUBMITTED_AT TIMESTAMP_LTZ(9)
);

-- ============================================================
-- SECTION 10: ADDITIONAL STORED PROCEDURES
-- ============================================================

-- 10.1 Create Investigation Case
CREATE OR REPLACE PROCEDURE RISK_FRAUD_COPILOT.APP.CREATE_INVESTIGATION_CASE(
    P_ACCOUNT_ID VARCHAR,
    P_CASE_TYPE VARCHAR,
    P_PRIORITY VARCHAR,
    P_FINDINGS VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
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

-- 10.2 Generate SAR Report
CREATE OR REPLACE PROCEDURE RISK_FRAUD_COPILOT.APP.GENERATE_SAR_REPORT(
    P_ACCOUNT_ID VARCHAR,
    P_FLAG_TYPE VARCHAR,
    P_EVIDENCE_SUMMARY VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
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

-- ============================================================
-- SECTION 11: ROLES & GRANTS
-- ============================================================

-- 11.1 Create AI_TRAINER role
CREATE ROLE IF NOT EXISTS AI_TRAINER;
GRANT ROLE AI_TRAINER TO USER ADMIN;

-- 11.2 Warehouse grants
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE AI_TRAINER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE AI_TRAINER;
GRANT OPERATE ON WAREHOUSE ANALYTICS_WH TO ROLE AI_TRAINER;

-- 11.3 Database & Schema grants
GRANT USAGE ON DATABASE RISK_FRAUD_COPILOT TO ROLE AI_TRAINER;
GRANT USAGE ON SCHEMA RISK_FRAUD_COPILOT.RAW TO ROLE AI_TRAINER;
GRANT USAGE ON SCHEMA RISK_FRAUD_COPILOT.PROCESSED TO ROLE AI_TRAINER;
GRANT USAGE ON SCHEMA RISK_FRAUD_COPILOT.DOCUMENTS TO ROLE AI_TRAINER;
GRANT USAGE ON SCHEMA RISK_FRAUD_COPILOT.SEMANTIC TO ROLE AI_TRAINER;
GRANT USAGE ON SCHEMA RISK_FRAUD_COPILOT.APP TO ROLE AI_TRAINER;
GRANT USAGE ON SCHEMA RISK_FRAUD_COPILOT.PUBLIC TO ROLE AI_TRAINER;

-- 11.4 Table grants (RAW schema - SELECT)
GRANT SELECT ON ALL TABLES IN SCHEMA RISK_FRAUD_COPILOT.RAW TO ROLE AI_TRAINER;

-- 11.5 Dynamic table grants (PROCESSED schema - SELECT)
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA RISK_FRAUD_COPILOT.PROCESSED TO ROLE AI_TRAINER;

-- 11.6 Table grants (PROCESSED schema - SELECT + INSERT for operational tables)
GRANT SELECT ON TABLE RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG TO ROLE AI_TRAINER;
GRANT INSERT ON TABLE RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG TO ROLE AI_TRAINER;
GRANT SELECT ON TABLE RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT TO ROLE AI_TRAINER;
GRANT INSERT ON TABLE RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT TO ROLE AI_TRAINER;
GRANT SELECT ON TABLE RISK_FRAUD_COPILOT.PROCESSED.SAR_FILINGS TO ROLE AI_TRAINER;
GRANT INSERT ON TABLE RISK_FRAUD_COPILOT.PROCESSED.SAR_FILINGS TO ROLE AI_TRAINER;

-- 11.7 Table grants (DOCUMENTS & APP schemas)
GRANT SELECT ON TABLE RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_DOCS TO ROLE AI_TRAINER;
GRANT SELECT ON ALL TABLES IN SCHEMA RISK_FRAUD_COPILOT.APP TO ROLE AI_TRAINER;

-- 11.8 Cortex Search Service grant
GRANT USAGE ON CORTEX SEARCH SERVICE RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_SEARCH TO ROLE AI_TRAINER;

-- 11.9 Semantic View grants
GRANT SELECT ON SEMANTIC VIEW RISK_FRAUD_COPILOT.SEMANTIC.RISK_FRAUD_INTELLIGENCE TO ROLE AI_TRAINER;
GRANT REFERENCES ON SEMANTIC VIEW RISK_FRAUD_COPILOT.SEMANTIC.RISK_FRAUD_INTELLIGENCE TO ROLE AI_TRAINER;

-- 11.10 Agent grants
GRANT USAGE ON AGENT RISK_FRAUD_COPILOT.APP.RISK_FRAUD_AGENT TO ROLE AI_TRAINER;
GRANT MONITOR ON AGENT RISK_FRAUD_COPILOT.APP.RISK_FRAUD_AGENT TO ROLE AI_TRAINER;

-- 11.11 Procedure grants
GRANT USAGE ON PROCEDURE RISK_FRAUD_COPILOT.APP.CREATE_INVESTIGATION_CASE(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE AI_TRAINER;
GRANT USAGE ON PROCEDURE RISK_FRAUD_COPILOT.APP.GENERATE_SAR_REPORT(VARCHAR, VARCHAR, VARCHAR) TO ROLE AI_TRAINER;

-- 11.12 Schema-level create privileges for APP schema
GRANT CREATE TASK ON SCHEMA RISK_FRAUD_COPILOT.APP TO ROLE AI_TRAINER;
GRANT CREATE FILE FORMAT ON SCHEMA RISK_FRAUD_COPILOT.APP TO ROLE AI_TRAINER;
GRANT CREATE STAGE ON SCHEMA RISK_FRAUD_COPILOT.APP TO ROLE AI_TRAINER;
GRANT CREATE DATASET ON SCHEMA RISK_FRAUD_COPILOT.APP TO ROLE AI_TRAINER;

-- 11.13 Dataset grants
GRANT USAGE ON ALL DATASETS IN SCHEMA RISK_FRAUD_COPILOT.APP TO ROLE AI_TRAINER;
GRANT USAGE ON FUTURE DATASETS IN SCHEMA RISK_FRAUD_COPILOT.APP TO ROLE AI_TRAINER;

-- 11.14 Account-level grants
GRANT EXECUTE TASK ON ACCOUNT TO ROLE AI_TRAINER;

-- 11.14 Database role grants
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE AI_TRAINER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE AI_TRAINER;

-- 11.15 Grant USAGE on DATABASE to PUBLIC (for agent accessibility)
GRANT USAGE ON DATABASE RISK_FRAUD_COPILOT TO ROLE PUBLIC;

-- ============================================================
-- SECTION 12: INVESTIGATION WORKFLOW (End-to-End Pipeline)
-- ============================================================

-- 12.1 Investigation Workflow View (Signal -> Case -> SAR -> Audit)
CREATE OR REPLACE VIEW RISK_FRAUD_COPILOT.APP.INVESTIGATION_WORKFLOW AS
SELECT 
    c.case_id,
    c.account_id,
    r.customer_name,
    c.case_type,
    c.status AS case_status,
    c.priority,
    c.created_at,
    c.findings,
    c.assigned_to,
    c.resolution,
    c.closed_at,
    s.sar_id,
    s.report_type,
    s.status AS sar_status,
    s.filing_date,
    s.regulatory_body,
    r.composite_risk_score,
    r.fraud_risk_level,
    r.compliance_risk_level,
    a.flag_type,
    a.severity AS flag_severity,
    a.confidence_score AS flag_confidence,
    a.description AS flag_description
FROM RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT c
LEFT JOIN RISK_FRAUD_COPILOT.PROCESSED.SAR_FILINGS s 
    ON c.linked_sar_id = s.sar_id
LEFT JOIN RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES r 
    ON c.account_id = r.account_id
LEFT JOIN RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS a 
    ON c.account_id = a.account_id;

-- 12.2 Update Case Status (lifecycle: OPEN -> INVESTIGATING -> PENDING_REVIEW -> CLOSED)
CREATE OR REPLACE PROCEDURE RISK_FRAUD_COPILOT.APP.UPDATE_CASE_STATUS(
    P_CASE_ID VARCHAR,
    P_NEW_STATUS VARCHAR,
    P_NOTES VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    LET current_status VARCHAR;
    SELECT status INTO :current_status 
    FROM RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT 
    WHERE case_id = :P_CASE_ID;

    IF (:current_status IS NULL) THEN
        RETURN 'ERROR: Case ' || :P_CASE_ID || ' not found.';
    END IF;

    IF (:current_status = 'CLOSED') THEN
        RETURN 'ERROR: Case ' || :P_CASE_ID || ' is already CLOSED and cannot be updated.';
    END IF;

    IF (:P_NEW_STATUS = 'CLOSED') THEN
        UPDATE RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT
        SET status = :P_NEW_STATUS, resolution = :P_NOTES, closed_at = CURRENT_TIMESTAMP()
        WHERE case_id = :P_CASE_ID;
    ELSE
        UPDATE RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT
        SET status = :P_NEW_STATUS, findings = COALESCE(findings, '') || CHR(10) || '[' || CURRENT_TIMESTAMP()::VARCHAR || '] ' || :P_NOTES
        WHERE case_id = :P_CASE_ID;
    END IF;

    INSERT INTO RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG (ACTION_TYPE, ENTITY_TYPE, ENTITY_ID, RESPONSE_SUMMARY)
    VALUES ('CASE_STATUS_UPDATE', 'CASE', :P_CASE_ID, 'Status changed from ' || :current_status || ' to ' || :P_NEW_STATUS || ': ' || :P_NOTES);

    RETURN 'Case ' || :P_CASE_ID || ' updated: ' || :current_status || ' -> ' || :P_NEW_STATUS;
END;

-- 12.3 Link SAR to Case
CREATE OR REPLACE PROCEDURE RISK_FRAUD_COPILOT.APP.LINK_SAR_TO_CASE(
    P_CASE_ID VARCHAR,
    P_SAR_ID VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    UPDATE RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT
    SET linked_sar_id = :P_SAR_ID
    WHERE case_id = :P_CASE_ID;

    INSERT INTO RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG (ACTION_TYPE, ENTITY_TYPE, ENTITY_ID, RESPONSE_SUMMARY)
    VALUES ('SAR_LINKED', 'CASE', :P_CASE_ID, 'SAR ' || :P_SAR_ID || ' linked to case ' || :P_CASE_ID);

    RETURN 'SAR ' || :P_SAR_ID || ' linked to case ' || :P_CASE_ID || ' successfully.';
END;

-- 12.4 Validate Finding (confidence-weighted evidence summary)
CREATE OR REPLACE PROCEDURE RISK_FRAUD_COPILOT.APP.VALIDATE_FINDING(
    P_ACCOUNT_ID VARCHAR,
    P_FINDING_TYPE VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    LET evidence VARCHAR DEFAULT '';
    LET signal_count NUMBER DEFAULT 0;
    LET avg_confidence NUMBER(3,2) DEFAULT 0;
    LET risk_score NUMBER DEFAULT 0;
    LET aml_count NUMBER DEFAULT 0;
    LET confidence_level VARCHAR DEFAULT 'LOW';

    SELECT COUNT(*), COALESCE(AVG(confidence_score), 0)
    INTO :signal_count, :avg_confidence
    FROM RISK_FRAUD_COPILOT.PROCESSED.FRAUD_SIGNALS
    WHERE account_id = :P_ACCOUNT_ID;

    SELECT COALESCE(composite_risk_score, 0)
    INTO :risk_score
    FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES
    WHERE account_id = :P_ACCOUNT_ID;

    SELECT COUNT(*)
    INTO :aml_count
    FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS
    WHERE account_id = :P_ACCOUNT_ID;

    IF (:avg_confidence >= 0.8 AND :signal_count >= 3) THEN
        confidence_level := 'HIGH';
    ELSEIF (:avg_confidence >= 0.6 AND :signal_count >= 1) THEN
        confidence_level := 'MEDIUM';
    ELSE
        confidence_level := 'LOW';
    END IF;

    evidence := OBJECT_CONSTRUCT(
        'account_id', :P_ACCOUNT_ID,
        'finding_type', :P_FINDING_TYPE,
        'fraud_signal_count', :signal_count,
        'aml_flag_count', :aml_count,
        'avg_signal_confidence', :avg_confidence,
        'composite_risk_score', :risk_score,
        'overall_confidence', :confidence_level,
        'recommendation', CASE 
            WHEN :confidence_level = 'HIGH' THEN 'Sufficient evidence for regulatory filing'
            WHEN :confidence_level = 'MEDIUM' THEN 'Additional investigation recommended before filing'
            ELSE 'Insufficient evidence - manual review required'
        END,
        'validated_at', CURRENT_TIMESTAMP()::VARCHAR
    )::VARCHAR;

    INSERT INTO RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG (ACTION_TYPE, ENTITY_TYPE, ENTITY_ID, RESPONSE_SUMMARY, CONFIDENCE_SCORE)
    VALUES ('FINDING_VALIDATED', 'ACCOUNT', :P_ACCOUNT_ID, :P_FINDING_TYPE || ' validation: ' || :confidence_level, :avg_confidence);

    RETURN evidence;
END;

-- 12.5 Grants for new objects
GRANT SELECT ON VIEW RISK_FRAUD_COPILOT.APP.INVESTIGATION_WORKFLOW TO ROLE AI_TRAINER;
GRANT USAGE ON PROCEDURE RISK_FRAUD_COPILOT.APP.UPDATE_CASE_STATUS(VARCHAR, VARCHAR, VARCHAR) TO ROLE AI_TRAINER;
GRANT USAGE ON PROCEDURE RISK_FRAUD_COPILOT.APP.LINK_SAR_TO_CASE(VARCHAR, VARCHAR) TO ROLE AI_TRAINER;
GRANT USAGE ON PROCEDURE RISK_FRAUD_COPILOT.APP.VALIDATE_FINDING(VARCHAR, VARCHAR) TO ROLE AI_TRAINER;

-- ============================================================
-- SECTION 13: COCO AUTOMATION (Scheduled Tasks)
-- ============================================================

-- 13.1 Daily High-Risk Account Scan
-- Identifies accounts that crossed risk threshold 50 and logs findings
CREATE OR REPLACE TASK RISK_FRAUD_COPILOT.APP.DAILY_HIGH_RISK_SCAN
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 8 * * * Asia/Kolkata'
    COMMENT = 'Daily scan for accounts crossing high-risk threshold'
AS
BEGIN
    INSERT INTO RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG (ACTION_TYPE, ENTITY_TYPE, ENTITY_ID, RESPONSE_SUMMARY, CONFIDENCE_SCORE)
    SELECT 
        'HIGH_RISK_ALERT',
        'ACCOUNT',
        account_id,
        'Daily scan: ' || customer_name || ' risk score ' || composite_risk_score || 
        ' (fraud: ' || fraud_risk_level || ', compliance: ' || compliance_risk_level || ')',
        composite_risk_score / 100.0
    FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES
    WHERE composite_risk_score > 50
      AND score_calculated_at >= DATEADD(day, -1, CURRENT_TIMESTAMP());
END;

-- 13.2 Weekly AML Summary Report
-- Aggregates AML flags from past 7 days into an audit summary
CREATE OR REPLACE TASK RISK_FRAUD_COPILOT.APP.WEEKLY_AML_SUMMARY
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 9 * * 1 Asia/Kolkata'
    COMMENT = 'Weekly AML flag summary report'
AS
BEGIN
    LET structuring_count NUMBER DEFAULT 0;
    LET intl_count NUMBER DEFAULT 0;
    LET pep_count NUMBER DEFAULT 0;
    LET total_flags NUMBER DEFAULT 0;

    SELECT 
        COUNT(CASE WHEN flag_type = 'STRUCTURING' THEN 1 END),
        COUNT(CASE WHEN flag_type = 'HIGH_VALUE_INTERNATIONAL' THEN 1 END),
        COUNT(CASE WHEN flag_type = 'PEP_ACTIVITY' THEN 1 END),
        COUNT(*)
    INTO :structuring_count, :intl_count, :pep_count, :total_flags
    FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS
    WHERE flag_date >= DATEADD(day, -7, CURRENT_DATE());

    INSERT INTO RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG (ACTION_TYPE, ENTITY_TYPE, ENTITY_ID, RESPONSE_SUMMARY)
    VALUES (
        'WEEKLY_AML_SUMMARY',
        'REPORT',
        'AML_WEEKLY_' || TO_CHAR(CURRENT_DATE(), 'YYYYMMDD'),
        'Weekly AML Summary: ' || :total_flags || ' total flags (' ||
        :structuring_count || ' structuring, ' || :intl_count || ' high-value intl, ' ||
        :pep_count || ' PEP activity). Period: ' || 
        TO_CHAR(DATEADD(day, -7, CURRENT_DATE()), 'YYYY-MM-DD') || ' to ' || TO_CHAR(CURRENT_DATE(), 'YYYY-MM-DD')
    );
END;

-- Tasks are created in suspended state. Resume when ready:
-- ALTER TASK RISK_FRAUD_COPILOT.APP.DAILY_HIGH_RISK_SCAN RESUME;
-- ALTER TASK RISK_FRAUD_COPILOT.APP.WEEKLY_AML_SUMMARY RESUME;

-- ============================================================
-- SECTION 14: VALIDATION QUERIES
-- ============================================================


-- Verify data counts
SELECT 'ACCOUNTS' AS table_name, COUNT(*) AS row_count FROM RISK_FRAUD_COPILOT.RAW.ACCOUNTS
UNION ALL
SELECT 'TRANSACTIONS', COUNT(*) FROM RISK_FRAUD_COPILOT.RAW.TRANSACTIONS
UNION ALL
SELECT 'KYC_RECORDS', COUNT(*) FROM RISK_FRAUD_COPILOT.RAW.KYC_RECORDS
UNION ALL
SELECT 'FRAUD_SIGNALS', COUNT(*) FROM RISK_FRAUD_COPILOT.PROCESSED.FRAUD_SIGNALS
UNION ALL
SELECT 'AML_FLAGS', COUNT(*) FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS
UNION ALL
SELECT 'RISK_SCORES', COUNT(*) FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES;

-- Test high risk accounts
SELECT account_id, customer_name, composite_risk_score, fraud_risk_level, 
       compliance_risk_level, total_transaction_volume, flagged_transaction_count
FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES 
WHERE composite_risk_score > 50 
ORDER BY composite_risk_score DESC 
LIMIT 10;

-- Test AML structuring detection
SELECT a.account_id, r.customer_name, a.flag_type, a.description, 
       a.confidence_score, r.composite_risk_score
FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS a
JOIN RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES r ON a.account_id = r.account_id
WHERE a.flag_type = 'STRUCTURING'
ORDER BY a.confidence_score DESC
LIMIT 5;

-- Test Cortex Search
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'RISK_FRAUD_COPILOT.DOCUMENTS.REGULATORY_SEARCH',
        '{
            "query": "What are the structuring detection rules under PMLA?",
            "columns": ["content", "section_title", "doc_title"],
            "limit": 2
        }'
    )
):results[0]:content::VARCHAR AS top_result;

-- Test audit finding generation
CALL RISK_FRAUD_COPILOT.APP.GENERATE_AUDIT_FINDING('ACC0000018', 'AML_STRUCTURING');

-- Verify all objects
SHOW AGENTS IN SCHEMA RISK_FRAUD_COPILOT.APP;
SHOW SEMANTIC VIEWS IN DATABASE RISK_FRAUD_COPILOT;
