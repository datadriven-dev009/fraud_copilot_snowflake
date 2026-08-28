# Risk, Fraud and Regulatory Intelligence Copilot

AI-powered compliance assistant for banking and NBFC teams built on Snowflake Cortex.

## Architecture

```
RAW (Accounts, Transactions, KYC, Thresholds)
    |
    v  [Dynamic Tables, 1-min lag]
PROCESSED (Fraud Signals, AML Flags, Risk Scores)
    |
    v  [Semantic View + Cortex Search]
INTELLIGENCE (Semantic View + Regulatory Search)
    |
    v  [Cortex Agent with 5 tools]
APP (Agent -> SAR Filings, Cases, Audit Log)
    |
    v  [Streamlit + CoCo Skill]
USER (Dashboard + Natural Language Chat)
```

## Components

| Component | Object | Description |
|-----------|--------|-------------|
| Database | `RISK_FRAUD_COPILOT` | All schemas and objects |
| Dynamic Tables | `PROCESSED.FRAUD_SIGNALS`, `AML_FLAGS`, `RISK_SCORES` | Near real-time processing (1-min lag) |
| Semantic View | `SEMANTIC.RISK_FRAUD_INTELLIGENCE` | Cortex Analyst ontology with 9 VQRs |
| Cortex Search | `DOCUMENTS.REGULATORY_SEARCH` | RAG over regulatory policy documents |
| Agent | `APP.RISK_FRAUD_AGENT` | Orchestrates all tools with Claude Sonnet 4.5 |
| Tools | `GenerateSAR`, `CreateCase` | Custom procedures for regulatory output |
| Dashboard | `APP.RISK_FRAUD_DASHBOARD` | Streamlit app with agent chat |
| Skill | `risk-fraud-copilot` | Reusable CoCo skill |

## Setup

1. Run `sql_ddl_complete.sql` to create all objects
2. Load synthetic data into RAW tables (see `synthetic_data/`)
3. Load regulatory documents into `DOCUMENTS.REGULATORY_DOCS`
4. Dynamic tables auto-refresh within 1 minute

## Agent Tools

| Tool | Type | Use Case |
|------|------|----------|
| RiskDataAnalyst | Cortex Analyst | Structured data queries (accounts, signals, scores) |
| RegulatorySearch | Cortex Search | Policy/regulation lookups (RBI, FATF, Basel) |
| GenerateSAR | Custom Procedure | Draft SAR/STR filings |
| CreateCase | Custom Procedure | Open investigation cases |
| data_to_chart | Built-in | Visualize query results |

## CoCo Skill

The `risk-fraud-copilot` skill is available in CoCo Desktop for natural language compliance queries.

### Description (Role)
Senior compliance analyst AI for banking AML officers, fraud investigators, and risk managers.

### Rules
- Always ground answers in data via semantic view
- Cite regulatory sources from Cortex Search
- Structure findings as: SIGNAL -> EVIDENCE -> FINDING -> ACTION
- Include ACCOUNT_ID for traceability

### Constraints
- Never provide legal advice
- Never auto-submit filings (DRAFT only)
- Never expose bulk PII
- Domain-restricted to risk/fraud/AML/compliance

## Evaluation

Evaluated on 30 questions across:
- Core Use Cases (data queries, regulatory lookups)
- Edge Cases (PEP + sanctions, country-specific)
- Instruction Compliance (off-topic rejection, PII protection)
- Multi-Tool routing (combined queries)
- Custom tool invocation (SAR generation, case creation)

## Files

- `sql_ddl_complete.sql` - Complete DDL/DML for all Snowflake objects
- `agent_specification.yaml` - Agent YAML specification
- `skill/SKILL.md` - CoCo reusable skill definition
