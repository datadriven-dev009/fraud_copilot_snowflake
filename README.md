# Risk, Fraud & Regulatory Intelligence Copilot

An AI-powered compliance assistant for banking and NBFC teams, built entirely with **Snowflake CoCo CLI**. Surfaces fraud signals, AML alerts, and risk scores from natural language questions and produces audit-ready regulatory outputs with full evidence chains.

## Problem Statement

Banking and NBFC teams manage real-time fraud, liquidity and credit risk, and regulatory reporting (AML, Basel, and local regulations) -- largely manual today. This copilot:

- Combines transaction and account data with policy and filing text
- Lets a business or compliance user ask questions and get governed, explainable, evidence-backed answers
- Covers the flow from signal to evidence to a documented finding or report

## Architecture

```
+-------------------------------------------------------------------------+
|                        RISK_FRAUD_COPILOT DATABASE                      |
+-------------------------------------------------------------------------+
|                                                                         |
|  RAW LAYER                PROCESSING LAYER         APPLICATION LAYER    |
|  +-------------------+    +--------------------+   +------------------+ |
|  | ACCOUNTS    (5K)  |    | FRAUD_SIGNALS (DT) |   | RISK_FRAUD_AGENT | |
|  | TRANSACTIONS(51K+)|--->| AML_FLAGS     (DT) |-->| (Cortex Agent)   | |
|  | KYC_RECORDS  (8K) |    | RISK_SCORES   (DT) |   |  - NL Queries    | |
|  | HIGH_RISK_CTRY (8)|    | AUDIT_LOG          |   |  - Guardrails    | |
|  | REG_THRESHOLDS (7)|    | CASE_MANAGEMENT    |   |  - Citations     | |
|  +-------------------+    | SAR_FILINGS        |   |  - Multi-tool    | |
|                            +--------------------+   +------------------+ |
|  +-------------------+                              | SEMANTIC VIEW    | |
|  | REGULATORY_DOCS   |---------------------------->| (Ontology: 7 tbl)| |
|  | (13 documents)    |     CORTEX SEARCH SERVICE    +------------------+ |
|  +-------------------+     (REGULATORY_SEARCH)      | STREAMLIT        | |
|                                                      | DASHBOARD (7 tab)| |
|  AUTOMATION LAYER          EVALUATION LAYER          +------------------+ |
|  +-------------------+     +--------------------+   | INVESTIGATION    | |
|  | SYNTH_DATA_GEN    |     | EVAL_GROUND_TRUTH  |   | WORKFLOW (View)  | |
|  |  7AM IST daily    |     | EVAL_DS_V1 Dataset |   +------------------+ |
|  | HIGH_RISK_SCAN    |     | EVAL_CONFIG_STAGE  |   | SOLUTION_METRICS | |
|  |  8AM IST daily    |     | (Custom Metrics)   |   | (Scorecard View) | |
|  | WEEKLY_AML_SUM    |     +--------------------+   +------------------+ |
|  |  9AM IST Monday   |                                                   |
|  +-------------------+                                                   |
+-------------------------------------------------------------------------+
```

## Data Model

### RAW Schema (Source Tables)

| Table | Rows | Description |
|-------|------|-------------|
| `ACCOUNTS` | 5,000 | Customer accounts with KYC status, risk tier, PEP/sanctions flags |
| `TRANSACTIONS` | 51,800+ | Transaction records with amount, currency, merchant details, fraud labels. Grows daily via synthetic data task. |
| `KYC_RECORDS` | 8,000 | KYC verification records with document types, expiry dates, risk flags |
| `HIGH_RISK_COUNTRIES` | 8 | FATF high-risk and monitored jurisdictions |
| `REGULATORY_THRESHOLDS` | 7 | Regulatory reporting thresholds (STR, CTR, PEP) |

### DOCUMENTS Schema

| Table | Rows | Description |
|-------|------|-------------|
| `REGULATORY_DOCS` | 13 | RBI KYC Master Direction, PMLA rules, Basel III framework, FATF recommendations, internal fraud detection policies |

### PROCESSED Schema (Derived Tables)

| Table | Type | Description |
|-------|------|-------------|
| `FRAUD_SIGNALS` | Dynamic Table (1-min lag) | Velocity anomalies, amount outliers, high-risk country/category transactions |
| `AML_FLAGS` | Dynamic Table (1-min lag) | Structuring detection, high-value international transfers, PEP activity |
| `RISK_SCORES` | Dynamic Table (1-min lag) | Composite risk scores (0-100) with fraud/compliance risk levels per account |
| `AUDIT_LOG` | Table | Immutable log of all system actions with timestamps and confidence scores |
| `CASE_MANAGEMENT` | Table | Investigation cases with lifecycle tracking (OPEN -> CLOSED) |
| `SAR_FILINGS` | Table | SAR/STR draft filings with evidence JSON and regulatory body |

### SEMANTIC Schema

| Object | Description |
|--------|-------------|
| `RISK_FRAUD_INTELLIGENCE` | Semantic View (ontology) over 7 tables with 30+ dimensions, 20+ measures, and cross-table relationships. Enables natural language queries via Cortex Analyst. |

### APP Schema

| Object | Type | Description |
|--------|------|-------------|
| `RISK_FRAUD_AGENT` | Cortex Agent | Multi-tool NL interface with guardrails, evidence citations, and routing logic |
| `RISK_FRAUD_DASHBOARD` | Streamlit | 7-tab dashboard: Overview, AI Copilot, Fraud Signals, AML Alerts, Risk Scores, Investigation Pipeline, Audit Trail |
| `INVESTIGATION_WORKFLOW` | View | Joins CASE_MANAGEMENT + SAR_FILINGS + RISK_SCORES + AML_FLAGS for end-to-end tracking |
| `SOLUTION_METRICS` | View | Comprehensive scorecard: hackathon criteria, business KPIs, agent quality metrics |
| `CREATE_INVESTIGATION_CASE` | Procedure | Opens case with type, priority, findings. Logs to AUDIT_LOG |
| `UPDATE_CASE_STATUS` | Procedure | Transitions case through OPEN -> INVESTIGATING -> PENDING_REVIEW -> CLOSED |
| `LINK_SAR_TO_CASE` | Procedure | Links a SAR filing to an investigation case |
| `GENERATE_SAR_REPORT` | Procedure | Generates SAR/STR draft with structured evidence JSON |
| `GENERATE_AUDIT_FINDING` | Procedure | Produces structured finding with risk context |
| `VALIDATE_FINDING` | Procedure | Confidence-weighted evidence validation (HIGH/MEDIUM/LOW) |
| `DAILY_SYNTHETIC_DATA_GEN` | Scheduled Task | Daily 7 AM IST -- generates 1,000 new synthetic transactions |
| `DAILY_HIGH_RISK_SCAN` | Scheduled Task | Daily 8 AM IST -- scans for accounts crossing risk threshold >50 |
| `WEEKLY_AML_SUMMARY` | Scheduled Task | Weekly Monday 9 AM IST -- aggregates AML flags into audit report |
| `EVAL_GROUND_TRUTH` | Table | 12-question evaluation dataset with ground truth (VARIANT) |
| `RISK_FRAUD_EVAL_DS_V1` | Dataset | Registered Snowflake Dataset for agent evaluation |
| `EVAL_CONFIG_STAGE` | Stage | Hosts custom evaluation metrics YAML |
| `AGENT_EVAL_DATASET` | Table | 20-question evaluation dataset (extended) |
| `RISK_FRAUD_EVAL_DATASET` | Table | 30-question evaluation dataset with categories and difficulty levels |

## Synthetic Data Generation

All data is synthetically generated via CoCo -- no production data used.

### Initial Data (sql_ddl_complete.sql Sections 2-3)

| Table | Method | Key Characteristics |
|-------|--------|---------------------|
| ACCOUNTS | `GENERATOR(ROWCOUNT => 5000)` | 20 Indian names, 4 account types, 5 KYC statuses, PEP (2%), sanctions (1%) |
| TRANSACTIONS | `GENERATOR(ROWCOUNT => 50000)` + 800 suspicious | Normal + structuring-range (Rs.4-5L) + high-value international |
| KYC_RECORDS | `GENERATOR(ROWCOUNT => 8000)` | 5 document types, randomized expiry, risk flags |
| HIGH_RISK_COUNTRIES | Manual INSERT | Nigeria, Iran, Myanmar, North Korea, Afghanistan, Syria, Yemen, Russia |
| REGULATORY_THRESHOLDS | Manual INSERT | STR Rs.10L, CTR Rs.50L, PEP Rs.1L |
| REGULATORY_DOCS | Manual INSERT | 13 sections across RBI, PMLA, Basel III, FATF, internal policies |

### Ongoing Data (Scheduled Task)

| Task | Schedule | Output |
|------|----------|--------|
| `DAILY_SYNTHETIC_DATA_GEN` | 7 AM IST daily | 1,000 new transactions with ~5% structuring-range, ~10% high-value, ~8% fraud-labeled |

The task runs before the daily risk scan (8 AM), ensuring dynamic tables pick up new signals. This simulates a live data feed without needing external connectors.

## Signal-to-Report Workflow

The complete end-to-end flow from signal detection to regulatory filing:

```
1. DATA INGESTION            2. SIGNAL DETECTION          3. EVIDENCE VALIDATION
   +------------------+         +------------------+         +------------------+
   | DAILY_SYNTHETIC  |         | Dynamic tables   |         | VALIDATE_FINDING |
   | _DATA_GEN task   |-------->| detect fraud     |-------->| scores evidence  |
   | 1000 txns/day    |         | signals, AML     |         | as HIGH/MED/LOW  |
   | at 7 AM IST      |         | flags, risk      |         | with confidence  |
   +------------------+         | score changes    |         +------------------+
                                | (1-min refresh)  |                |
                                +------------------+                v
4. INVESTIGATION             5. REGULATORY FILING         6. AUDIT TRAIL
   +------------------+         +------------------+         +------------------+
   | CREATE_CASE      |         | GENERATE_SAR     |         | Every action     |
   | assigns priority |-------->| creates DRAFT    |-------->| logged to        |
   | tracks lifecycle |         | with evidence    |         | AUDIT_LOG with   |
   | OPEN -> CLOSED   |         | JSON + citations |         | timestamps and   |
   +------------------+         | for FIU-IND      |         | confidence       |
                                +------------------+         +------------------+
```

## Scheduled Automation Pipeline

Three tasks run in sequence daily, forming an automated monitoring pipeline:

```
7:00 AM IST                 8:00 AM IST                 9:00 AM IST (Monday)
+-------------------+       +-------------------+       +-------------------+
| DAILY_SYNTHETIC   |       | DAILY_HIGH_RISK   |       | WEEKLY_AML        |
| _DATA_GEN         |------>| _SCAN             |------>| _SUMMARY          |
|                   |       |                   |       |                   |
| Generates 1,000   | DT    | Scans accounts    |       | Aggregates AML    |
| new transactions  | auto- | crossing risk     |       | flags from past   |
| with fraud        | refresh| threshold >50    |       | 7 days into       |
| patterns          | (1min)| Logs to AUDIT_LOG |       | AUDIT_LOG report  |
+-------------------+       +-------------------+       +-------------------+
```

All tasks are created in **suspended state**. Resume for demo:
```sql
ALTER TASK RISK_FRAUD_COPILOT.APP.DAILY_SYNTHETIC_DATA_GEN RESUME;
ALTER TASK RISK_FRAUD_COPILOT.APP.DAILY_HIGH_RISK_SCAN RESUME;
ALTER TASK RISK_FRAUD_COPILOT.APP.WEEKLY_AML_SUMMARY RESUME;
```

## Cortex Agent Design

### Tool Routing

The agent uses a 5-step decision tree to route questions to the right tool:

| Step | Question Type | Tool | Examples |
|------|---------------|------|---------|
| 1 | Off-topic | NONE (refuse) | "What's the weather?" |
| 2 | Regulatory rules, policies, thresholds | Cortex Search (`RegSearch`) | "What is the STR filing threshold under RBI?" |
| 3 | SAR/STR generation requests | `GENERATE_SAR_REPORT` procedure | "Generate a SAR for ACC0000018" |
| 4 | Investigation case creation | `CREATE_INVESTIGATION_CASE` procedure | "Open a case for ACC0000018" |
| 5 | Data queries (default) | Cortex Analyst (`Analyst`) | "Which accounts have risk score > 50?" |

Multi-tool chaining supported: Regulatory + Data, Data + SAR, Data + Case creation.

### Guardrails

| Guardrail | Behavior |
|-----------|----------|
| Off-topic rejection | Refuses non-compliance questions (weather, sports, personal) |
| PII protection | Refuses bulk PII disclosure requests |
| Auto-submit prevention | All filings are DRAFT only, requires human review before FIU-IND submission |
| Data grounding | Never fabricates numbers -- always uses tool results |
| Confidence warning | Flags results with confidence < 0.7: "Manual verification recommended" |
| Low confidence escalation | Confidence < 0.5: "Escalate to senior compliance officer" |
| Evidence citations | Cites regulatory sources as `[Source: doc_title > section_title]` |
| Structured output | Findings follow: SIGNAL -> EVIDENCE -> FINDING -> RECOMMENDED ACTION |

### Orchestration Model

- Model: Claude Sonnet 4.5
- Budget: 120 seconds, 32K tokens
- Response limit: 500 words, 20 rows default
- Response format: INR currency, 2 decimal places, ACCOUNT_ID in every account-level answer

## Streamlit Dashboard

### 7-Tab Layout

| Tab | Features |
|-----|----------|
| **Overview** | 6 KPI metrics bar, risk score distribution chart, 30-day fraud signal trend (area chart by severity), top-10 risk accounts with progress bar scores |
| **AI Copilot** | Natural language interface to Cortex Agent with collapsible suggested questions, fallback to COMPLETE model on error |
| **Fraud Signals** | Filter by severity/type/lookback days, 4 summary KPIs, dual charts (by type + severity), confidence progress bars, sortable data table |
| **AML Alerts** | Urgent STR callout banner, 4 KPIs, flag type + action breakdown charts, cross-reference with risk scores, confidence columns |
| **Risk Scores** | Filter by score/fraud level/KYC status, 5 KPIs, distribution chart, PEP/sanctions checkbox columns, high-risk volume column |
| **Investigation Pipeline** | 4 sub-tabs: Case Tracker (status counts + lifecycle updates), Create Case (with evidence validation button), SAR Pipeline (DRAFT/REVIEW/SUBMITTED counts + generate), Export Report (CSV download) |
| **Audit Trail** | Chronological AUDIT_LOG with multi-select filters by action type, entity type, and lookback days. Confidence progress bars. |

### Dashboard Features

- `@st.cache_data(ttl=120)` on all summary queries for performance
- `st.column_config.ProgressColumn` for risk scores (0-100) and confidence (0-1)
- `st.column_config.CheckboxColumn` for PEP/sanctions flags
- Refresh button in sidebar to clear cache
- `hide_index=True` on all dataframes

## Agent Evaluation Framework

### Evaluation Datasets

| Dataset | Questions | Format | Purpose |
|---------|-----------|--------|---------|
| `RISK_FRAUD_EVAL_DATASET` | 30 | question + expected_answer + category + difficulty | Comprehensive eval across 5 categories |
| `EVAL_GROUND_TRUTH` | 12 | input_query + VARIANT ground_truth | Snowflake-native eval with tool invocation ground truth |
| `RISK_FRAUD_EVAL_DS_V1` | 12 | Registered Dataset | Ready for Snowsight Evaluations tab |
| `AGENT_EVAL_DATASET` | 20 | question + expected_response | Extended eval dataset |

### Evaluation Metrics (evaluation_metrics.yaml)

**System Metrics (4):**
- `answer_correctness` (v3) -- ground-truth comparison
- `logical_consistency` (v3) -- reference-free reasoning check
- `tool_selection_accuracy` (v3) -- correct tool routing
- `tool_execution_accuracy` (v3) -- tool input/output quality

**Custom Metrics (3):**
- `guardrail_compliance` -- scores off-topic rejection, PII protection, auto-submit prevention
- `evidence_citation` -- scores [Source: doc > section] format, ACCOUNT_ID inclusion, structured output
- `regulatory_accuracy` -- scores correct framework citation (RBI, PMLA, Basel, FATF)

### Running an Evaluation

**From Snowsight:**
1. AI & ML -> Agents -> RISK_FRAUD_AGENT -> Evaluations tab
2. Create evaluation run -> Select dataset `RISK_FRAUD_EVAL_DS_V1`
3. Enable system metrics + custom metrics from `EVAL_CONFIG_STAGE/evaluation_metrics.yaml`

**From SQL:**
```sql
CALL EXECUTE_AI_EVALUATION(
  'START',
  OBJECT_CONSTRUCT('run_name', 'hackathon_eval_v1'),
  '@RISK_FRAUD_COPILOT.APP.EVAL_CONFIG_STAGE/evaluation_metrics.yaml'
);
```

### Solution Metrics View

Live scorecard queryable at any time:
```sql
SELECT * FROM RISK_FRAUD_COPILOT.APP.SOLUTION_METRICS ORDER BY section, metric_id;
```

Covers 44 metrics across 3 sections:
- **A. Hackathon Criteria** -- 17 sub-metrics mapped to judging weights (30/40/30)
- **B. Business KPIs** -- 17 live operational metrics (fraud detection rate, signal confidence, etc.)
- **C. Agent Quality** -- 10 metrics on tools, guardrails, routing, semantic view coverage

## Roles & Access Control

| Role | Purpose | Key Grants |
|------|---------|------------|
| `AI_TRAINER` | Agent evaluation and operational use | USAGE on all schemas, SELECT on all tables/views/dynamic tables, USAGE on agent/search/semantic view, INSERT on operational tables, USAGE on all procedures, CREATE TASK/STAGE/DATASET/FILE FORMAT, EXECUTE TASK, database roles (CORTEX_USER, CORTEX_AGENT_USER) |
| `ACCOUNTADMIN` | Ownership of all objects | Full ownership |
| `PUBLIC` | Agent accessibility | USAGE on DATABASE |

## Risk Score Formula

Composite risk score (0-100) calculated from:

| Factor | Points |
|--------|--------|
| Fraud transactions count | x 20 each |
| PEP flag | +15 |
| Sanctions flag | +30 |
| Expired KYC | +10 |
| KYC issues | +5 each |
| High-risk volume > Rs. 10 lakh | +15 |
| International transactions > 10 | +5 |

## Signal Types

| Signal | Detection Logic | Severity |
|--------|----------------|----------|
| VELOCITY_1MIN | >5 transactions in 1 minute window | CRITICAL |
| VELOCITY_1HR | >20 transactions in 1 hour window | MEDIUM |
| AMOUNT_ANOMALY | >3 standard deviations from account mean | HIGH |
| HIGH_RISK_COUNTRY | Transaction to FATF HIGH-risk jurisdiction | HIGH |
| HIGH_RISK_CATEGORY | Crypto/Gambling transactions > Rs. 1 lakh | MEDIUM |

## AML Flag Types

| Flag | Detection Logic | Required Action |
|------|----------------|-----------------|
| STRUCTURING | Multiple Rs. 4-5 lakh transactions on same day | FILE_STR |
| HIGH_VALUE_INTERNATIONAL | International transfers > Rs. 5 lakh | ENHANCED_DUE_DILIGENCE |
| PEP_ACTIVITY | PEP account transactions > Rs. 1 lakh | SENIOR_REVIEW |

## Setup Instructions

### Prerequisites
- Snowflake account with ACCOUNTADMIN access
- COMPUTE_WH warehouse available
- Cross-region inference enabled (for Claude models in agent)

### Deployment Steps

1. Run `sql_ddl_complete.sql` sections 1-14 in order:
   ```sql
   -- Section 1:  Database, schemas, ANALYTICS_WH warehouse
   -- Section 2:  RAW tables with synthetic data generation
   -- Section 3:  REGULATORY_DOCS with 13 policy documents
   -- Section 4:  Dynamic tables (FRAUD_SIGNALS, AML_FLAGS, RISK_SCORES)
   -- Section 5:  Cortex Search service (REGULATORY_SEARCH)
   -- Section 6:  Semantic View (RISK_FRAUD_INTELLIGENCE ontology)
   -- Section 7:  Cortex Agent (RISK_FRAUD_AGENT with guardrails)
   -- Section 8:  Streamlit app + GENERATE_AUDIT_FINDING procedure
   -- Section 9:  Operational tables (AUDIT_LOG, CASE_MANAGEMENT, SAR_FILINGS)
   -- Section 10: Procedures (CREATE_INVESTIGATION_CASE, GENERATE_SAR_REPORT)
   -- Section 11: Roles, grants, and access control (AI_TRAINER role)
   -- Section 12: Investigation workflow (view + UPDATE_CASE_STATUS + LINK_SAR_TO_CASE + VALIDATE_FINDING)
   -- Section 13: Scheduled automation tasks (data gen + risk scan + AML summary)
   -- Section 14: Validation queries
   ```

2. Upload Streamlit app:
   ```sql
   PUT file://streamlit_app.py @RISK_FRAUD_COPILOT.APP.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   PUT file://environment.yml @RISK_FRAUD_COPILOT.APP.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   ```

3. Upload evaluation config:
   ```sql
   CREATE OR REPLACE FILE FORMAT RISK_FRAUD_COPILOT.APP.YAML_FILE_FORMAT
     TYPE = 'CSV' FIELD_DELIMITER = NONE RECORD_DELIMITER = '\n'
     SKIP_HEADER = 0 FIELD_OPTIONALLY_ENCLOSED_BY = NONE ESCAPE_UNENCLOSED_FIELD = NONE;
   CREATE OR REPLACE STAGE RISK_FRAUD_COPILOT.APP.EVAL_CONFIG_STAGE
     FILE_FORMAT = RISK_FRAUD_COPILOT.APP.YAML_FILE_FORMAT;
   PUT file://evaluation_metrics.yaml @RISK_FRAUD_COPILOT.APP.EVAL_CONFIG_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   ```

4. Register evaluation dataset:
   ```sql
   CALL SYSTEM$CREATE_EVALUATION_DATASET(
     'Cortex Agent',
     'RISK_FRAUD_COPILOT.APP.EVAL_GROUND_TRUTH',
     'RISK_FRAUD_COPILOT.APP.RISK_FRAUD_EVAL_DS_V1',
     OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'GROUND_TRUTH')
   );
   ```

5. Verify deployment:
   ```sql
   SHOW AGENTS IN SCHEMA RISK_FRAUD_COPILOT.APP;
   SHOW SEMANTIC VIEWS IN DATABASE RISK_FRAUD_COPILOT;
   SHOW STREAMLITS IN DATABASE RISK_FRAUD_COPILOT;
   SHOW TASKS IN SCHEMA RISK_FRAUD_COPILOT.APP;
   SHOW DATASETS IN SCHEMA RISK_FRAUD_COPILOT.APP;
   ```

6. Resume scheduled tasks (optional, for demo):
   ```sql
   ALTER TASK RISK_FRAUD_COPILOT.APP.DAILY_SYNTHETIC_DATA_GEN RESUME;
   ALTER TASK RISK_FRAUD_COPILOT.APP.DAILY_HIGH_RISK_SCAN RESUME;
   ALTER TASK RISK_FRAUD_COPILOT.APP.WEEKLY_AML_SUMMARY RESUME;
   ```

## CoCo CLI Usage Across All Phases

### Planning Phase
- Explored the RISK_FRAUD_COPILOT database schema and table structures via CoCo
- Framed the solution design, data model, and ontology through CoCo conversations
- Drafted the semantic view relationships and agent specification interactively
- Designed the investigation workflow and case lifecycle model
- Planned evaluation strategy and metrics framework

### Development Phase
- Built all SQL DDL (16 tables, 3 dynamic tables, 2 views, 6 procedures, 3 tasks) through CoCo
- Generated synthetic data (5K accounts, 51K+ transactions, 8K KYC records, 13 regulatory documents) via CoCo
- Authored the Cortex Agent specification with multi-tool routing, guardrails, and evidence citations
- Created the Streamlit dashboard with 7 tabs and 20+ visualizations
- Developed the CoCo skill (SKILL.md) for reusable compliance workflows
- Authored the Semantic View with 30+ dimensions, 20+ measures, and cross-table relationships
- Created evaluation datasets (12 + 20 + 30 questions) with ground truth VARIANT
- Defined 7 evaluation metrics (4 system + 3 custom) in YAML

### Execution Phase
- Deployed all objects to Snowflake through CoCo SQL execution
- Scheduled 3 automated tasks (data gen + risk scan + AML summary) via CoCo
- Ran end-to-end workflow tests: signal detection -> evidence validation -> case creation -> SAR filing -> audit trail
- Managed git branches and repository through CoCo terminal
- Uploaded evaluation config and registered datasets via CoCo

### Testing & Validation Phase
- Validated agent responses against regulatory questions (RBI, PMLA, FATF)
- Tested case lifecycle transitions (OPEN -> INVESTIGATING -> PENDING_REVIEW -> CLOSED)
- Verified confidence-based guardrails trigger at < 0.7 and < 0.5 thresholds
- Confirmed evidence citations appear in agent output with source document references
- Ran VALIDATE_FINDING procedure and confirmed HIGH/MEDIUM/LOW confidence scoring
- Verified audit trail entries for all system actions with correct timestamps
- Ran agent evaluation with Snowflake's built-in evaluation framework (7 metrics)
- Queried SOLUTION_METRICS view to confirm 44 metrics across all 3 scoring dimensions

## File Structure

```
H:\Snowflake CoCo\
  sql_ddl_complete.sql            -- Complete DDL/DML (14 sections, all objects + grants)
  streamlit_app.py                -- Streamlit dashboard (7 tabs, 600+ lines)
  risk_fraud_semantic_model.yaml  -- Semantic view YAML definition
  evaluation_metrics.yaml         -- Custom evaluation metrics (7 metrics for agent eval)
  environment.yml                 -- Streamlit dependencies
  README.md                       -- This file
  skill\
    SKILL.md                      -- CoCo reusable skill for compliance workflows
```

## Complete Snowflake Objects Inventory

| # | Schema | Object | Type |
|---|--------|--------|------|
| 1 | RAW | ACCOUNTS | Table (5,000 rows) |
| 2 | RAW | TRANSACTIONS | Table (51,800+ rows, growing daily) |
| 3 | RAW | KYC_RECORDS | Table (8,000 rows) |
| 4 | RAW | HIGH_RISK_COUNTRIES | Table (8 rows) |
| 5 | RAW | REGULATORY_THRESHOLDS | Table (7 rows) |
| 6 | DOCUMENTS | REGULATORY_DOCS | Table (13 rows) |
| 7 | DOCUMENTS | REGULATORY_SEARCH | Cortex Search Service |
| 8 | PROCESSED | FRAUD_SIGNALS | Dynamic Table (1-min lag) |
| 9 | PROCESSED | AML_FLAGS | Dynamic Table (1-min lag) |
| 10 | PROCESSED | RISK_SCORES | Dynamic Table (1-min lag) |
| 11 | PROCESSED | AUDIT_LOG | Table |
| 12 | PROCESSED | CASE_MANAGEMENT | Table |
| 13 | PROCESSED | SAR_FILINGS | Table |
| 14 | SEMANTIC | RISK_FRAUD_INTELLIGENCE | Semantic View |
| 15 | APP | RISK_FRAUD_AGENT | Cortex Agent |
| 16 | APP | RISK_FRAUD_DASHBOARD | Streamlit App |
| 17 | APP | INVESTIGATION_WORKFLOW | View |
| 18 | APP | SOLUTION_METRICS | View |
| 19 | APP | CREATE_INVESTIGATION_CASE | Stored Procedure |
| 20 | APP | UPDATE_CASE_STATUS | Stored Procedure |
| 21 | APP | LINK_SAR_TO_CASE | Stored Procedure |
| 22 | APP | GENERATE_SAR_REPORT | Stored Procedure |
| 23 | APP | GENERATE_AUDIT_FINDING | Stored Procedure |
| 24 | APP | VALIDATE_FINDING | Stored Procedure |
| 25 | APP | DAILY_SYNTHETIC_DATA_GEN | Scheduled Task (7 AM IST) |
| 26 | APP | DAILY_HIGH_RISK_SCAN | Scheduled Task (8 AM IST) |
| 27 | APP | WEEKLY_AML_SUMMARY | Scheduled Task (Mon 9 AM IST) |
| 28 | APP | EVAL_GROUND_TRUTH | Table (12 rows) |
| 29 | APP | RISK_FRAUD_EVAL_DS_V1 | Registered Dataset |
| 30 | APP | EVAL_CONFIG_STAGE | Stage (custom metrics YAML) |
| 31 | APP | AGENT_EVAL_DATASET | Table (20 rows) |
| 32 | APP | RISK_FRAUD_EVAL_DATASET | Table (30 rows) |
| 33 | APP | STREAMLIT_STAGE | Stage (Streamlit files) |
| -- | -- | AI_TRAINER | Role (45+ grants) |

## Evaluation Criteria Coverage

| Criterion | Weight | Coverage |
|-----------|--------|----------|
| **Real-World Relevance** | 30% | Banking AML/fraud use case grounded in RBI, PMLA, FATF, Basel regulatory frameworks. End-to-end signal-to-report workflow mirrors real compliance operations. Synthetic data with realistic fraud patterns. |
| **Technical Execution** | 40% | Cortex Agent (multi-tool routing + 8 guardrails) + Semantic View (ontology over 7 tables) + Cortex Search (13 regulatory docs) + Dynamic Tables (3, 1-min lag) + Scheduled Tasks (3, automated pipeline) + Streamlit (7-tab dashboard) + Stored Procedures (6 workflow actions) + CoCo Skill (reusable) + Agent Evaluation (7 metrics, 4 system + 3 custom). |
| **Solution Completeness** | 30% | Complete lifecycle: Synthetic data generation -> Signal detection -> Evidence validation -> Investigation case management -> SAR filing -> Audit trail. Confidence-based guardrails. Role-based access control. Scheduled automation pipeline. Evaluation framework with datasets and custom metrics. Solution metrics scorecard. |
