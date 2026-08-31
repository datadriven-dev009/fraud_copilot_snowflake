import streamlit as st
import json
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(
    page_title="Risk & Fraud Intelligence Copilot",
    page_icon="\u26a0\ufe0f",
    layout="wide",
    initial_sidebar_state="expanded",
)

session = get_active_session()


# --- Cached data loaders ---
@st.cache_data(ttl=120)
def load_risk_summary():
    return session.sql("""
        SELECT 
            COUNT(*) AS total_accounts,
            COUNT(CASE WHEN composite_risk_score > 50 THEN 1 END) AS high_risk_count,
            COUNT(CASE WHEN composite_risk_score > 75 THEN 1 END) AS critical_count,
            ROUND(AVG(composite_risk_score), 1) AS avg_score,
            ROUND(MAX(composite_risk_score), 1) AS max_score,
            COUNT(CASE WHEN pep_flag = TRUE THEN 1 END) AS pep_count,
            COUNT(CASE WHEN sanctions_flag = TRUE THEN 1 END) AS sanctions_count
        FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES
    """).collect()[0]


@st.cache_data(ttl=120)
def load_fraud_summary():
    return session.sql("""
        SELECT 
            COUNT(*) AS total_signals,
            COUNT(CASE WHEN severity = 'CRITICAL' THEN 1 END) AS critical,
            COUNT(CASE WHEN severity = 'HIGH' THEN 1 END) AS high,
            COUNT(CASE WHEN severity = 'MEDIUM' THEN 1 END) AS medium
        FROM RISK_FRAUD_COPILOT.PROCESSED.FRAUD_SIGNALS
        WHERE signal_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP())
    """).collect()[0]


@st.cache_data(ttl=120)
def load_aml_summary():
    return session.sql("""
        SELECT 
            COUNT(*) AS total_flags,
            COUNT(CASE WHEN required_action = 'FILE_STR' THEN 1 END) AS pending_str,
            COUNT(CASE WHEN required_action = 'ENHANCED_DUE_DILIGENCE' THEN 1 END) AS edd_required
        FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS
    """).collect()[0]


@st.cache_data(ttl=120)
def load_risk_distribution():
    return session.sql("""
        SELECT 
            CASE 
                WHEN composite_risk_score >= 75 THEN 'Critical (75-100)'
                WHEN composite_risk_score >= 50 THEN 'High (50-74)'
                WHEN composite_risk_score >= 25 THEN 'Medium (25-49)'
                ELSE 'Low (0-24)'
            END AS risk_band,
            COUNT(*) AS account_count
        FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES
        GROUP BY risk_band
        ORDER BY MIN(composite_risk_score) DESC
    """).to_pandas()


@st.cache_data(ttl=120)
def load_fraud_trend():
    return session.sql("""
        SELECT 
            DATE(signal_timestamp) AS signal_date,
            severity,
            COUNT(*) AS signal_count
        FROM RISK_FRAUD_COPILOT.PROCESSED.FRAUD_SIGNALS
        WHERE signal_timestamp >= DATEADD(day, -30, CURRENT_TIMESTAMP())
        GROUP BY signal_date, severity
        ORDER BY signal_date
    """).to_pandas()


@st.cache_data(ttl=120)
def load_top_risk_accounts(limit=10):
    return session.sql(f"""
        SELECT account_id, customer_name, composite_risk_score,
               fraud_risk_level, compliance_risk_level, 
               total_transaction_volume, flagged_transaction_count,
               pep_flag, sanctions_flag, kyc_status
        FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES
        ORDER BY composite_risk_score DESC
        LIMIT {limit}
    """).to_pandas()


# --- Header ---
st.title("Risk, Fraud & Regulatory Intelligence Copilot")
st.caption("Real-time compliance monitoring | Powered by Snowflake Cortex AI")

# --- Executive KPI Bar ---
risk_summary = load_risk_summary()
fraud_summary = load_fraud_summary()
aml_summary = load_aml_summary()

kpi1, kpi2, kpi3, kpi4, kpi5, kpi6 = st.columns(6)
kpi1.metric("Accounts Monitored", f"{int(risk_summary['TOTAL_ACCOUNTS']):,}")
kpi2.metric("High Risk (>50)", int(risk_summary['HIGH_RISK_COUNT']))
kpi3.metric("Avg Risk Score", float(risk_summary['AVG_SCORE']))
kpi4.metric("Fraud Signals (7d)", int(fraud_summary['TOTAL_SIGNALS']))
kpi5.metric("AML Flags", int(aml_summary['TOTAL_FLAGS']))
kpi6.metric("Pending STR Filing", int(aml_summary['PENDING_STR']))

st.divider()

# --- Main Tabs ---
tab_overview, tab_copilot, tab_fraud, tab_aml, tab_risk, tab_actions, tab_audit = st.tabs([
    "Overview", "AI Copilot", "Fraud Signals", "AML Alerts", "Risk Scores",
    "Investigation Pipeline", "Audit Trail"
])

# ==================== TAB: OVERVIEW ====================
with tab_overview:
    col_left, col_right = st.columns([3, 2])

    with col_left:
        st.subheader("Risk Score Distribution")
        dist_df = load_risk_distribution()
        st.bar_chart(dist_df, x="RISK_BAND", y="ACCOUNT_COUNT")

    with col_right:
        st.subheader("Threat Summary")
        st.markdown(f"""
        | Indicator | Count |
        |-----------|-------|
        | PEP Accounts | **{risk_summary['PEP_COUNT']}** |
        | Sanctioned Entities | **{risk_summary['SANCTIONS_COUNT']}** |
        | Critical Risk (>75) | **{risk_summary['CRITICAL_COUNT']}** |
        | Fraud Signals (Critical) | **{fraud_summary['CRITICAL']}** |
        | EDD Required | **{aml_summary['EDD_REQUIRED']}** |
        """)

    st.subheader("Fraud Signal Trend (30 Days)")
    trend_df = load_fraud_trend()
    if not trend_df.empty:
        pivot_trend = trend_df.pivot_table(
            index="SIGNAL_DATE", columns="SEVERITY", values="SIGNAL_COUNT", fill_value=0
        ).reset_index()
        st.area_chart(pivot_trend, x="SIGNAL_DATE")
    else:
        st.info("No fraud signals in the past 30 days.")

    st.subheader("Top 10 Highest Risk Accounts")
    top_accounts = load_top_risk_accounts(10)
    st.dataframe(
        top_accounts,
        use_container_width=True,
        
    )

# ==================== TAB: AI COPILOT ====================
with tab_copilot:
    st.subheader("Compliance Intelligence Assistant")
    st.markdown("Ask questions about fraud patterns, AML compliance, regulatory requirements, or account risk profiles.")

    suggested_questions = [
        "Which accounts triggered AML structuring alerts this week?",
        "What is the SAR filing threshold under PMLA/RBI guidelines?",
        "Show me accounts with velocity-based fraud signals",
        "What are the top risk factors for PEP accounts?",
        "Summarize regulatory requirements for cross-border transactions over 5 lakh",
    ]

    with st.expander("Suggested Questions", expanded=False):
        cols = st.columns(2)
        for i, q in enumerate(suggested_questions):
            if cols[i % 2].button(q, key=f"suggest_{i}", use_container_width=True):
                st.session_state["copilot_input"] = q

    user_input = st.text_area(
        "Your question:",
        value=st.session_state.get("copilot_input", ""),
        height=80,
        placeholder="e.g., Which accounts show structuring behavior with amounts just below the reporting threshold?",
    )

    if st.button("Ask Copilot", type="primary", use_container_width=False):
        if not user_input.strip():
            st.warning("Please enter a question.")
        else:
            with st.spinner("Analyzing with Cortex Agent..."):
                try:
                    safe_input = user_input.replace("'", "''").replace("\\", "\\\\").replace('"', '\\"')
                    result = session.sql(f"""
                        SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
                            'RISK_FRAUD_COPILOT.APP.RISK_FRAUD_AGENT',
                            '{{"messages": [{{"role": "user", "content": [{{"type": "text", "text": "{safe_input}"}}]}}]}}'
                        ) AS response
                    """).collect()

                    response = json.loads(result[0]["RESPONSE"])
                    if response.get("code"):
                        st.warning("Agent returned an error. Using fallback model...")
                        fallback = session.sql(f"""
                            SELECT SNOWFLAKE.CORTEX.COMPLETE(
                                'llama3.1-70b',
                                'You are a risk and compliance analyst at a bank. Answer concisely: {safe_input}'
                            ) AS answer
                        """).collect()
                        st.markdown(fallback[0]["ANSWER"])
                    else:
                        content = response.get("content", "")
                        if isinstance(content, list):
                            for block in content:
                                if isinstance(block, dict) and block.get("type") == "text":
                                    st.markdown(block["text"])
                        else:
                            st.markdown(str(content) if content else str(response))
                except Exception as e:
                    st.error(f"Error communicating with agent: {e}")

# ==================== TAB: FRAUD SIGNALS ====================
with tab_fraud:
    st.subheader("Fraud Signal Monitor")

    filter_col1, filter_col2, filter_col3 = st.columns(3)
    with filter_col1:
        severity_filter = st.multiselect(
            "Severity", ["CRITICAL", "HIGH", "MEDIUM", "LOW"],
            default=["CRITICAL", "HIGH"], key="fraud_sev"
        )
    with filter_col2:
        signal_types = ["VELOCITY_1MIN", "VELOCITY_1HR", "AMOUNT_ANOMALY", "HIGH_RISK_COUNTRY", "HIGH_RISK_CATEGORY"]
        signal_filter = st.multiselect("Signal Type", signal_types, key="fraud_type")
    with filter_col3:
        days_back = st.slider("Lookback (days)", 1, 30, 7, key="fraud_days")

    severity_clause = ",".join(f"'{s}'" for s in severity_filter) if severity_filter else "'CRITICAL','HIGH'"

    query = f"""
        SELECT account_id, signal_type, severity, amount, merchant_country,
               merchant_category, confidence_score, signal_timestamp
        FROM RISK_FRAUD_COPILOT.PROCESSED.FRAUD_SIGNALS
        WHERE severity IN ({severity_clause})
          AND signal_timestamp >= DATEADD(day, -{days_back}, CURRENT_TIMESTAMP())
    """
    if signal_filter:
        signal_clause = ",".join(f"'{s}'" for s in signal_filter)
        query += f" AND signal_type IN ({signal_clause})"
    query += " ORDER BY signal_timestamp DESC LIMIT 200"

    fraud_df = session.sql(query).to_pandas()

    if not fraud_df.empty:
        summary_cols = st.columns(4)
        summary_cols[0].metric("Total Signals", len(fraud_df))
        summary_cols[1].metric("Critical", len(fraud_df[fraud_df["SEVERITY"] == "CRITICAL"]))
        summary_cols[2].metric("Unique Accounts", fraud_df["ACCOUNT_ID"].nunique())
        summary_cols[3].metric("Avg Confidence", f"{fraud_df['CONFIDENCE_SCORE'].mean():.2f}")

        chart_col1, chart_col2 = st.columns(2)
        with chart_col1:
            st.markdown("**Signals by Type**")
            type_counts = fraud_df["SIGNAL_TYPE"].value_counts().reset_index()
            type_counts.columns = ["SIGNAL_TYPE", "COUNT"]
            st.bar_chart(type_counts, x="SIGNAL_TYPE", y="COUNT")
        with chart_col2:
            st.markdown("**Signals by Severity**")
            sev_counts = fraud_df["SEVERITY"].value_counts().reset_index()
            sev_counts.columns = ["SEVERITY", "COUNT"]
            st.bar_chart(sev_counts, x="SEVERITY", y="COUNT")

        st.dataframe(
            fraud_df,
            use_container_width=True,
            
        )
    else:
        st.info("No fraud signals matching the selected filters.")

# ==================== TAB: AML ALERTS ====================
with tab_aml:
    st.subheader("Anti-Money Laundering Alerts")

    aml_col1, aml_col2 = st.columns(2)
    with aml_col1:
        aml_type = st.multiselect(
            "Flag Type",
            ["STRUCTURING", "HIGH_VALUE_INTERNATIONAL", "PEP_ACTIVITY"],
            default=["STRUCTURING", "HIGH_VALUE_INTERNATIONAL", "PEP_ACTIVITY"],
            key="aml_type",
        )
    with aml_col2:
        action_filter = st.multiselect(
            "Required Action",
            ["FILE_STR", "ENHANCED_DUE_DILIGENCE", "SENIOR_REVIEW"],
            key="aml_action",
        )

    aml_type_clause = ",".join(f"'{t}'" for t in aml_type) if aml_type else "'STRUCTURING'"
    aml_query = f"""
        SELECT a.account_id, a.flag_type, a.severity, a.required_action,
               a.description, a.confidence_score, a.flag_date,
               r.customer_name, r.composite_risk_score
        FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS a
        JOIN RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES r ON a.account_id = r.account_id
        WHERE a.flag_type IN ({aml_type_clause})
    """
    if action_filter:
        action_clause = ",".join(f"'{a}'" for a in action_filter)
        aml_query += f" AND a.required_action IN ({action_clause})"
    aml_query += " ORDER BY a.flag_date DESC, a.confidence_score DESC LIMIT 200"

    aml_df = session.sql(aml_query).to_pandas()

    if not aml_df.empty:
        # Urgent alerts callout
        str_filings = aml_df[aml_df["REQUIRED_ACTION"] == "FILE_STR"]
        if not str_filings.empty:
            st.error(f"URGENT: {len(str_filings)} accounts require STR/SAR filing action")

        metric_cols = st.columns(4)
        metric_cols[0].metric("Total AML Flags", len(aml_df))
        metric_cols[1].metric("STR Required", len(str_filings))
        metric_cols[2].metric("EDD Required", len(aml_df[aml_df["REQUIRED_ACTION"] == "ENHANCED_DUE_DILIGENCE"]))
        metric_cols[3].metric("Unique Accounts", aml_df["ACCOUNT_ID"].nunique())

        chart_col1, chart_col2 = st.columns(2)
        with chart_col1:
            st.markdown("**Flags by Type**")
            flag_counts = aml_df["FLAG_TYPE"].value_counts().reset_index()
            flag_counts.columns = ["FLAG_TYPE", "COUNT"]
            st.bar_chart(flag_counts, x="FLAG_TYPE", y="COUNT")
        with chart_col2:
            st.markdown("**Required Actions**")
            action_counts = aml_df["REQUIRED_ACTION"].value_counts().reset_index()
            action_counts.columns = ["REQUIRED_ACTION", "COUNT"]
            st.bar_chart(action_counts, x="REQUIRED_ACTION", y="COUNT")

        st.dataframe(
            aml_df,
            use_container_width=True,
            
        )
    else:
        st.info("No AML alerts matching the selected filters.")

# ==================== TAB: RISK SCORES ====================
with tab_risk:
    st.subheader("Account Risk Scores")

    risk_col1, risk_col2, risk_col3 = st.columns(3)
    with risk_col1:
        min_score = st.slider("Min Risk Score", 0, 100, 30, key="risk_min")
    with risk_col2:
        risk_level = st.multiselect(
            "Fraud Risk Level", ["HIGH", "MEDIUM", "LOW"],
            default=["HIGH", "MEDIUM"], key="risk_level"
        )
    with risk_col3:
        kyc_filter = st.multiselect(
            "KYC Status", ["VERIFIED", "PENDING", "EXPIRED"],
            default=["VERIFIED", "PENDING", "EXPIRED"], key="risk_kyc"
        )

    risk_level_clause = ",".join(f"'{r}'" for r in risk_level) if risk_level else "'HIGH','MEDIUM'"
    kyc_clause = ",".join(f"'{k}'" for k in kyc_filter) if kyc_filter else "'VERIFIED','PENDING','EXPIRED'"

    risk_query = f"""
        SELECT account_id, customer_name, account_type, assigned_tier,
               composite_risk_score, fraud_risk_level, compliance_risk_level,
               total_transaction_volume, flagged_transaction_count,
               high_risk_category_volume, pep_flag, sanctions_flag, kyc_status
        FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES
        WHERE composite_risk_score >= {min_score}
          AND fraud_risk_level IN ({risk_level_clause})
          AND kyc_status IN ({kyc_clause})
        ORDER BY composite_risk_score DESC
        LIMIT 100
    """
    risk_df = session.sql(risk_query).to_pandas()

    if not risk_df.empty:
        stat_cols = st.columns(5)
        stat_cols[0].metric("Accounts", len(risk_df))
        stat_cols[1].metric("Avg Score", f"{risk_df['COMPOSITE_RISK_SCORE'].mean():.1f}")
        stat_cols[2].metric("PEP Accounts", int(risk_df["PEP_FLAG"].sum()))
        stat_cols[3].metric("Sanctioned", int(risk_df["SANCTIONS_FLAG"].sum()))
        stat_cols[4].metric("KYC Expired", len(risk_df[risk_df["KYC_STATUS"] == "EXPIRED"]))

        st.markdown("**Risk Score Distribution (filtered accounts)**")
        st.bar_chart(risk_df, x="ACCOUNT_ID", y="COMPOSITE_RISK_SCORE")

        st.dataframe(
            risk_df,
            use_container_width=True,
            
        )
    else:
        st.info("No accounts matching the selected filters.")

# ==================== TAB: INVESTIGATION PIPELINE ====================
with tab_actions:
    st.subheader("Investigation Pipeline")

    pipeline_tab1, pipeline_tab2, pipeline_tab3, pipeline_tab4 = st.tabs([
        "Case Tracker", "Create Case", "SAR Pipeline", "Export Report"
    ])

    # --- Case Tracker ---
    with pipeline_tab1:
        case_df = session.sql("""
            SELECT case_id, account_id, case_type, status, priority,
                   created_at, assigned_to, linked_sar_id
            FROM RISK_FRAUD_COPILOT.PROCESSED.CASE_MANAGEMENT
            ORDER BY created_at DESC
            LIMIT 100
        """).to_pandas()

        if not case_df.empty:
            status_counts = case_df["STATUS"].value_counts()
            status_cols = st.columns(4)
            for i, status in enumerate(["OPEN", "INVESTIGATING", "PENDING_REVIEW", "CLOSED"]):
                count = status_counts.get(status, 0)
                status_cols[i].metric(status, count)

            st.dataframe(case_df, use_container_width=True)

            st.divider()
            st.markdown("**Update Case Status**")
            upd_col1, upd_col2, upd_col3 = st.columns(3)
            with upd_col1:
                upd_case_id = st.text_input("Case ID", placeholder="e.g., CASE123456", key="upd_case")
            with upd_col2:
                upd_status = st.selectbox("New Status", ["INVESTIGATING", "PENDING_REVIEW", "CLOSED"], key="upd_status")
            with upd_col3:
                upd_notes = st.text_input("Notes", key="upd_notes")
            if st.button("Update Status", type="primary", key="btn_upd_case"):
                if upd_case_id and upd_notes:
                    try:
                        safe_notes = upd_notes.replace("'", "''")
                        result = session.sql(f"CALL RISK_FRAUD_COPILOT.APP.UPDATE_CASE_STATUS('{upd_case_id}', '{upd_status}', '{safe_notes}')").collect()
                        st.success(result[0][0])
                    except Exception as e:
                        st.error(f"Failed: {e}")
                else:
                    st.warning("Enter Case ID and Notes.")
        else:
            st.info("No investigation cases yet. Create one from the 'Create Case' tab.")

    # --- Create Case ---
    with pipeline_tab2:
        st.markdown("Open a new investigation case for an account.")
        case_col1, case_col2 = st.columns(2)
        with case_col1:
            case_account = st.text_input("Account ID", placeholder="e.g., ACC0000018", key="case_acc")
            case_type = st.selectbox("Case Type", ["AML_STRUCTURING", "FRAUD_VELOCITY", "PEP_REVIEW", "SANCTIONS_HIT", "KYC_EXPIRED"])
        with case_col2:
            case_priority = st.selectbox("Priority", ["HIGH", "MEDIUM", "LOW"])
            case_findings = st.text_area("Initial Findings", height=100, key="case_findings")

        col_create, col_validate = st.columns(2)
        with col_create:
            if st.button("Create Case", type="primary", key="btn_case"):
                if case_account and case_findings:
                    with st.spinner("Creating case..."):
                        try:
                            safe_findings = case_findings.replace("'", "''")
                            result = session.sql(f"""
                                CALL RISK_FRAUD_COPILOT.APP.CREATE_INVESTIGATION_CASE(
                                    '{case_account}', '{case_type}', '{case_priority}', '{safe_findings}'
                                )
                            """).collect()
                            st.success(result[0][0])
                        except Exception as e:
                            st.error(f"Failed to create case: {e}")
                else:
                    st.warning("Please fill in Account ID and Findings.")
        with col_validate:
            if st.button("Validate Evidence", key="btn_validate"):
                if case_account:
                    with st.spinner("Validating..."):
                        try:
                            result = session.sql(f"""
                                CALL RISK_FRAUD_COPILOT.APP.VALIDATE_FINDING('{case_account}', '{case_type}')
                            """).collect()
                            import json as _json
                            evidence = _json.loads(result[0][0])
                            conf = evidence.get("overall_confidence", "UNKNOWN")
                            if conf == "HIGH":
                                st.success(f"Confidence: {conf} | {evidence.get('recommendation', '')}")
                            elif conf == "MEDIUM":
                                st.warning(f"Confidence: {conf} | {evidence.get('recommendation', '')}")
                            else:
                                st.error(f"Confidence: {conf} | {evidence.get('recommendation', '')}")
                            st.json(evidence)
                        except Exception as e:
                            st.error(f"Validation failed: {e}")
                else:
                    st.warning("Enter Account ID first.")

    # --- SAR Pipeline ---
    with pipeline_tab3:
        st.markdown("**SAR/STR Filing Pipeline**: DRAFT -> REVIEW -> SUBMITTED")

        sar_df = session.sql("""
            SELECT sar_id, account_id, report_type, status, filing_date,
                   regulatory_body, generated_by, reviewed_by, submitted_at
            FROM RISK_FRAUD_COPILOT.PROCESSED.SAR_FILINGS
            ORDER BY filing_date DESC
            LIMIT 100
        """).to_pandas()

        if not sar_df.empty:
            sar_status_counts = sar_df["STATUS"].value_counts()
            sar_cols = st.columns(3)
            sar_cols[0].metric("DRAFT", sar_status_counts.get("DRAFT", 0))
            sar_cols[1].metric("REVIEW", sar_status_counts.get("REVIEW", 0))
            sar_cols[2].metric("SUBMITTED", sar_status_counts.get("SUBMITTED", 0))
            st.dataframe(sar_df, use_container_width=True)
        else:
            st.info("No SAR filings yet.")

        st.divider()
        st.markdown("**Generate New SAR Draft**")
        sar_col1, sar_col2 = st.columns(2)
        with sar_col1:
            sar_account = st.text_input("Account ID", placeholder="e.g., ACC0000018", key="sar_acc")
            sar_flag_type = st.selectbox("Flag Type", ["STRUCTURING", "HIGH_VALUE_INTERNATIONAL", "PEP_ACTIVITY"])
        with sar_col2:
            sar_evidence = st.text_area("Evidence Summary", height=100, key="sar_evidence")

        if st.button("Generate SAR Draft", type="primary", key="btn_sar"):
            if sar_account and sar_evidence:
                with st.spinner("Generating SAR report..."):
                    try:
                        safe_evidence = sar_evidence.replace("'", "''")
                        result = session.sql(f"""
                            CALL RISK_FRAUD_COPILOT.APP.GENERATE_SAR_REPORT(
                                '{sar_account}', '{sar_flag_type}', '{safe_evidence}'
                            )
                        """).collect()
                        st.success(result[0][0])
                    except Exception as e:
                        st.error(f"Failed to generate SAR: {e}")
            else:
                st.warning("Please fill in Account ID and Evidence Summary.")

    # --- Export Report ---
    with pipeline_tab4:
        st.markdown("Export accounts requiring STR filing as a downloadable audit report.")
        if st.button("Generate Audit Export", type="primary", key="btn_export"):
            with st.spinner("Generating report..."):
                report_data = session.sql("""
                    SELECT 
                        a.account_id, r.customer_name, a.flag_type, a.description,
                        a.required_action, a.confidence_score, a.flag_date,
                        r.composite_risk_score, r.fraud_risk_level, r.compliance_risk_level
                    FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS a
                    JOIN RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES r ON a.account_id = r.account_id
                    WHERE a.required_action = 'FILE_STR'
                    ORDER BY a.flag_date DESC
                """).to_pandas()

                if not report_data.empty:
                    st.markdown(f"**Total findings:** {len(report_data)} accounts requiring STR filing")
                    st.dataframe(report_data, use_container_width=True)
                    st.download_button(
                        "Download CSV",
                        report_data.to_csv(index=False),
                        "str_audit_report.csv",
                        "text/csv",
                        use_container_width=True,
                    )
                else:
                    st.info("No accounts currently require STR filing.")

# ==================== TAB: AUDIT TRAIL ====================
with tab_audit:
    st.subheader("Audit Trail")

    audit_col1, audit_col2, audit_col3 = st.columns(3)
    with audit_col1:
        audit_action = st.multiselect(
            "Action Type",
            ["CASE_CREATED", "CASE_STATUS_UPDATE", "SAR_GENERATED", "SAR_LINKED",
             "FINDING_VALIDATED", "HIGH_RISK_ALERT", "WEEKLY_AML_SUMMARY"],
            key="audit_action",
        )
    with audit_col2:
        audit_entity = st.multiselect(
            "Entity Type", ["CASE", "SAR", "ACCOUNT", "REPORT"],
            key="audit_entity",
        )
    with audit_col3:
        audit_days = st.slider("Lookback (days)", 1, 90, 30, key="audit_days")

    audit_query = f"""
        SELECT log_id, action_timestamp, action_type, entity_type, entity_id,
               response_summary, confidence_score
        FROM RISK_FRAUD_COPILOT.PROCESSED.AUDIT_LOG
        WHERE action_timestamp >= DATEADD(day, -{audit_days}, CURRENT_TIMESTAMP())
    """
    if audit_action:
        action_clause = ",".join(f"'{a}'" for a in audit_action)
        audit_query += f" AND action_type IN ({action_clause})"
    if audit_entity:
        entity_clause = ",".join(f"'{e}'" for e in audit_entity)
        audit_query += f" AND entity_type IN ({entity_clause})"
    audit_query += " ORDER BY action_timestamp DESC LIMIT 200"

    audit_df = session.sql(audit_query).to_pandas()

    if not audit_df.empty:
        st.metric("Audit Events", len(audit_df))
        st.dataframe(
            audit_df,
            use_container_width=True,
            
        )
    else:
        st.info("No audit events matching the selected filters.")

# --- Sidebar ---
with st.sidebar:
    st.divider()
    st.caption("Risk, Fraud & Regulatory Intelligence Copilot")
    st.caption("Snowflake Cortex AI | Real-time Monitoring")
    if st.button("Refresh Data", use_container_width=True):
        st.cache_data.clear()
        st.experimental_rerun()
