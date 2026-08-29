# Risk, Fraud & Regulatory Intelligence Copilot

An AI-powered compliance assistant for banking and NBFC teams, built entirely with **Snowflake CoCo CLI**. Surfaces fraud signals, AML alerts, and risk scores from natural language questions and produces audit-ready regulatory outputs with full evidence chains.

## Problem Statement

Banking and NBFC teams manage real-time fraud, liquidity and credit risk, and regulatory reporting (AML, Basel, and local regulations) -- largely manual today. This copilot surfaces risk and fraud signals and produces audit-ready regulatory outputs from natural language questions.

## Architecture

```
+---------------------------------------------------------------------+
|                        RISK_FRAUD_COPILOT                           |
+---------------------------------------------------------------------+
|                                                                     |
|  RAW LAYER              PROCESSING LAYER       APPLICATION LAYER    |
|  +-----------------+    +------------------+   +------------------+ |
|  | ACCOUNTS  (5K)  |    | FRAUD_SIGNALS    |   | RISK_FRAUD_AGENT | |
|  | TRANSACTIONS    |--->| (Dynamic Table)  |-->| (Cortex Agent)   | |
|  |   (50K+)        |    | AML_FLAGS        |   |  - NL Queries    | |
|  | KYC_RECORDS(8K) |    | (Dynamic Table)  |   |  - Guardrails    | |
|  | HIGH_RISK_CTRY  |    | RISK_SCORES      |   |  - Citations     | |
|  | REG_THRESHOLDS  |    | (Dynamic Table)  |   |  - Multi-tool    | |
|  +-----------------+    +------------------+   +------------------+ |
|                         | AUDIT_LOG        |   | SEMANTIC VIEW    | |
|  +-----------------+    | CASE_MANAGEMENT  |   | (Ontology over   | |
|  | REGULATORY_DOCS |--->| SAR_FILINGS      |   |  7 tables)       | |
|  | (13 documents)  |    +------------------+   +------------------+ |
|  +-----------------+                           | CORTEX SEARCH    | |
|        |                                       | (Regulatory docs)| |
|        +-------------------------------------->+------------------+ |
|                                                | STREAMLIT        | |
|  AUTOMATION LAYER                              | DASHBOARD        | |
|  +-----------------+                           | (7 tabs)         | |
|  | DAILY_HIGH_RISK | 8AM IST daily             +------------------+ |
|  | WEEKLY_AML_SUM  | 9AM IST Monday            | INVESTIGATION    | |
|  +-----------------+                           | WORKFLOW (View)  | |
|                                                +------------------+ |
+---------------------------------------------------------------------+
```

## Data Model

### RAW Schema (Source Tables)

| Table | Rows | Description |
|-------|------|-------------|
| `ACCOUNTS` | 5,000 | Customer accounts with KYC status, risk tier, PEP/sanctions flags |
| `TRANSACTIONS` | 50,800 | Transaction records with amount, currency, merchant details, fraud labels |
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
| `CREATE_INVESTIGATION_CASE` | Procedure | Opens case with type, priority, findings. Logs to AUDIT_LOG |
| `UPDATE_CASE_STATUS` | Procedure | Transitions case through OPEN -> INVESTIGATING -> PENDING_REVIEW -> CLOSED |
| `LINK_SAR_TO_CASE` | Procedure | Links a SAR filing to an investigation case |
| `GENERATE_SAR_REPORT` | Procedure | Generates SAR/STR draft with structured evidence JSON |
| `GENERATE_AUDIT_FINDING` | Procedure | Produces structured finding with risk context |
| `VALIDATE_FINDING` | Procedure | Confidence-weighted evidence validation (HIGH/MEDIUM/LOW) |
| `DAILY_HIGH_RISK_SCAN` | Task | Daily 8 AM IST scan for accounts crossing risk threshold >50 |
| `WEEKLY_AML_SUMMARY` | Task | Weekly Monday 9 AM IST aggregation of AML flags |

## Signal-to-Report Workflow

The complete end-to-end flow from signal detection to regulatory filing:

```
1. SIGNAL DETECTION           2. EVIDENCE VALIDATION       3. INVESTIGATION
   +-------------------+         +------------------+         +------------------+
   | Dynamic tables    |         | VALIDATE_FINDING |         | CREATE_CASE      |
   | detect fraud      |-------->| scores evidence  |-------->| assigns priority |
   | signals, AML      |         | as HIGH/MED/LOW  |         | tracks lifecycle |
   | flags, risk       |         | with confidence  |         | OPEN -> CLOSED   |
   | score changes     |         +------------------+         +------------------+
   +-------------------+                                             |
                                                                     v
4. REGULATORY FILING          5. AUDIT TRAIL
   +-------------------+         +------------------+
   | GENERATE_SAR      |         | Every action     |
   | creates DRAFT     |<--------| logged to        |
   | with evidence     |         | AUDIT_LOG with   |
   | JSON + citations  |         | timestamps and   |
   | for FIU-IND       |         | confidence       |
   +-------------------+         +------------------+
```

## Cortex Agent Design

### Tool Routing

The agent uses a decision tree to route questions to the right tool:

| Question Type | Tool | Examples |
|---------------|------|---------|
| Regulatory rules, policies, thresholds | Cortex Search (`REGULATORY_SEARCH`) | "What is the STR filing threshold under RBI?" |
| Data queries about accounts, signals, flags | Cortex Analyst (`RISK_FRAUD_INTELLIGENCE`) | "Which accounts have risk score > 50?" |
| SAR/STR generation requests | `GENERATE_SAR_REPORT` procedure | "Generate a SAR for ACC0000018" |
| Investigation case creation | `CREATE_INVESTIGATION_CASE` procedure | "Open an investigation case for ACC0000018" |

### Guardrails

| Guardrail | Behavior |
|-----------|----------|
| Off-topic rejection | Refuses non-compliance questions (weather, sports, personal) |
| PII protection | Refuses bulk PII disclosure requests |
| Auto-submit prevention | All filings are DRAFT only, requires human review |
| Data grounding | Never fabricates numbers -- always uses tool results |
| Confidence threshold | Flags results with confidence < 0.7 for manual review |
| Low confidence escalation | Escalates to senior officer when confidence < 0.5 |
| Evidence citations | Cites regulatory sources as `[Source: doc_title > section_title]` |

### Orchestration Model

- Model: Claude Sonnet 4.5
- Budget: 120 seconds, 32K tokens
- Response limit: 500 words, 20 rows default

## Streamlit Dashboard

### 7-Tab Layout

| Tab | Features |
|-----|----------|
| **Overview** | 6 KPI metrics, risk distribution chart, 30-day fraud trend (area chart), top-10 risk accounts with progress bars |
| **AI Copilot** | Natural language interface to Cortex Agent with suggested questions, fallback to COMPLETE model |
| **Fraud Signals** | Filterable by severity/type/days, dual charts (by type + severity), confidence progress bars |
| **AML Alerts** | Urgent STR callout banner, flag type + action breakdown charts, cross-reference with risk scores |
| **Risk Scores** | Filter by score/fraud level/KYC status, 5 KPIs, distribution chart, PEP/sanctions checkboxes |
| **Investigation Pipeline** | Case Tracker (status counts + lifecycle updates), Create Case with evidence validation, SAR Pipeline (DRAFT/REVIEW/SUBMITTED), Export Report |
| **Audit Trail** | Chronological AUDIT_LOG with filters by action type, entity type, and date range |

## Roles & Access Control

| Role | Purpose | Key Grants |
|------|---------|------------|
| `AI_TRAINER` | Agent evaluation and operational use | USAGE on all schemas, SELECT on all tables/views, USAGE on agent/search/semantic view, INSERT on operational tables, CREATE TASK/STAGE/DATASET, EXECUTE TASK |
| `ACCOUNTADMIN` | Ownership of all objects | Full ownership |
| `PUBLIC` | Agent accessibility | USAGE on DATABASE |

## Scheduled Automation

| Task | Schedule | Action |
|------|----------|--------|
| `DAILY_HIGH_RISK_SCAN` | 8:00 AM IST daily | Identifies accounts with risk score > 50 and logs to AUDIT_LOG |
| `WEEKLY_AML_SUMMARY` | 9:00 AM IST every Monday | Aggregates AML flags from past 7 days into AUDIT_LOG summary |

## CoCo CLI Usage Across All Phases

### Planning Phase
- Explored the RISK_FRAUD_COPILOT database schema and table structures via CoCo
- Framed the solution design, data model, and ontology through CoCo conversations
- Drafted the semantic view relationships and agent specification interactively
- Designed the investigation workflow and case lifecycle model

### Development Phase
- Built all SQL DDL (16 tables, 3 dynamic tables, 1 view, 6 procedures, 2 tasks) through CoCo
- Generated synthetic data (5K accounts, 50K transactions, 8K KYC records, 13 regulatory documents) via CoCo
- Authored the Cortex Agent specification with multi-tool routing, guardrails, and evidence citations
- Created the Streamlit dashboard with 7 tabs and 20+ visualizations
- Developed the CoCo skill (SKILL.md) for reusable compliance workflows
- Authored the Semantic View with 30+ dimensions, 20+ measures, and cross-table relationships

### Execution Phase
- Deployed all objects to Snowflake through CoCo SQL execution
- Scheduled automated tasks (daily risk scan, weekly AML summary) via CoCo
- Ran end-to-end workflow tests: signal detection -> evidence validation -> case creation -> SAR filing -> audit trail
- Managed git branches and repository through CoCo terminal

### Testing & Validation Phase
- Validated agent responses against regulatory questions (RBI, PMLA, FATF)
- Tested case lifecycle transitions (OPEN -> INVESTIGATING -> PENDING_REVIEW -> CLOSED)
- Verified confidence-based guardrails trigger at < 0.7 and < 0.5 thresholds
- Confirmed evidence citations appear in agent output with source document references
- Ran VALIDATE_FINDING procedure and confirmed HIGH/MEDIUM/LOW confidence scoring
- Verified audit trail entries for all system actions with correct timestamps

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
- Cross-region inference enabled (for Claude models)

### Deployment Steps

1. Run `sql_ddl_complete.sql` sections 1-14 in order:
   ```sql
   -- Sections 1-3: Database, schemas, raw tables with synthetic data
   -- Section 4: Dynamic tables (fraud signals, AML flags, risk scores)
   -- Section 5: Cortex Search service
   -- Section 6: Semantic View
   -- Section 7: Cortex Agent
   -- Section 8: Streamlit app + GENERATE_AUDIT_FINDING procedure
   -- Section 9: Operational tables (AUDIT_LOG, CASE_MANAGEMENT, SAR_FILINGS)
   -- Section 10: Procedures (CREATE_INVESTIGATION_CASE, GENERATE_SAR_REPORT)
   -- Section 11: Roles and grants
   -- Section 12: Investigation workflow (view + lifecycle procedures)
   -- Section 13: Scheduled automation tasks
   -- Section 14: Validation queries
   ```

2. Upload Streamlit app:
   ```sql
   PUT file://streamlit_app.py @RISK_FRAUD_COPILOT.APP.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   ```

3. Upload environment file:
   ```sql
   PUT file://environment.yml @RISK_FRAUD_COPILOT.APP.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
   ```

4. Verify deployment:
   ```sql
   SHOW AGENTS IN SCHEMA RISK_FRAUD_COPILOT.APP;
   SHOW SEMANTIC VIEWS IN DATABASE RISK_FRAUD_COPILOT;
   SHOW STREAMLITS IN DATABASE RISK_FRAUD_COPILOT;
   SHOW TASKS IN SCHEMA RISK_FRAUD_COPILOT.APP;
   ```

5. Optional: Resume scheduled tasks:
   ```sql
   ALTER TASK RISK_FRAUD_COPILOT.APP.DAILY_HIGH_RISK_SCAN RESUME;
   ALTER TASK RISK_FRAUD_COPILOT.APP.WEEKLY_AML_SUMMARY RESUME;
   ```

## File Structure

```
H:\Snowflake CoCo\
  sql_ddl_complete.sql          -- Complete DDL/DML (14 sections, all objects + grants)
  streamlit_app.py              -- Streamlit dashboard (7 tabs, 600+ lines)
  risk_fraud_semantic_model.yaml -- Semantic view YAML definition
  environment.yml               -- Streamlit dependencies
  README.md                     -- This file
  skill\
    SKILL.md                    -- CoCo reusable skill for compliance workflows
```

## Evaluation Criteria Coverage

| Criterion | Weight | Coverage |
|-----------|--------|----------|
| **Real-World Relevance** | 30% | Banking AML/fraud use case grounded in RBI, PMLA, FATF, Basel regulatory frameworks. End-to-end signal-to-report workflow mirrors real compliance operations. |
| **Technical Execution** | 40% | Cortex Agent (multi-tool routing + guardrails) + Semantic View (ontology) + Cortex Search (regulatory docs) + Dynamic Tables (real-time signals) + Scheduled Tasks (automation) + Streamlit (7-tab dashboard) + Stored Procedures (6 workflow actions) + CoCo Skill (reusable). |
| **Solution Completeness** | 30% | Complete lifecycle: Signal detection -> Evidence validation -> Investigation case management -> SAR filing -> Audit trail. Confidence-based guardrails. Role-based access control. Scheduled automation. |
