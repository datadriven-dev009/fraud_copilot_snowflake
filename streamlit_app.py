import streamlit as st
import json
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Risk & Fraud Intelligence Copilot", layout="wide")

session = get_active_session()

# --- Header ---
st.title("Risk, Fraud & Regulatory Intelligence Copilot")
st.caption("AI-powered compliance assistant for banking teams")

# --- Sidebar: Summary Metrics ---
with st.sidebar:
    st.header("Risk Dashboard")
    
    metrics = session.sql("""
        SELECT 
            COUNT(*) as total_accounts,
            COUNT(CASE WHEN composite_risk_score > 50 THEN 1 END) as high_risk,
            AVG(composite_risk_score) as avg_score
        FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES
    """).collect()
    
    fraud_count = session.sql("""
        SELECT COUNT(*) as cnt 
        FROM RISK_FRAUD_COPILOT.PROCESSED.FRAUD_SIGNALS 
        WHERE signal_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP())
    """).collect()
    
    aml_count = session.sql("""
        SELECT COUNT(*) as cnt 
        FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS 
        WHERE flag_date >= DATEADD(day, -7, CURRENT_DATE())
    """).collect()
    
    st.metric("Total Accounts Monitored", f"{metrics[0]['TOTAL_ACCOUNTS']:,}")
    st.metric("High Risk Accounts (>50)", metrics[0]['HIGH_RISK'])
    st.metric("Avg Risk Score", f"{metrics[0]['AVG_SCORE']:.1f}")
    st.metric("Fraud Signals (7d)", fraud_count[0]['CNT'])
    st.metric("AML Flags (7d)", aml_count[0]['CNT'])
    
    st.divider()
    st.subheader("Quick Actions")
    if st.button("Export Audit Report"):
        st.session_state['export_report'] = True

# --- Main Content: Tabs ---
tab1, tab2, tab3, tab4 = st.tabs(["Copilot Chat", "Fraud Signals", "AML Alerts", "Risk Scores"])

# --- Tab 1: Copilot Chat ---
with tab1:
    st.subheader("Ask the Compliance Copilot")
    
    # Sample questions
    col1, col2 = st.columns(2)
    with col1:
        st.markdown("**Sample Questions:**")
        sample_qs = [
            "Which accounts triggered AML alerts this week?",
            "What is the SAR filing threshold under RBI guidelines?",
            "Show me top 10 highest risk accounts",
            "What are the structuring detection patterns?",
            "Portfolio risk exposure by tier?"
        ]
        for q in sample_qs:
            if st.button(q, key=f"sq_{q[:20]}"):
                st.session_state['user_query'] = q
    
    with col2:
        user_input = st.text_area(
            "Enter your question:",
            value=st.session_state.get('user_query', ''),
            height=100,
            placeholder="e.g., Which accounts have unusual transaction patterns?"
        )
        
        if st.button("Ask Copilot", type="primary"):
            if user_input:
                with st.spinner("Analyzing..."):
                    try:
                        result = session.sql(f"""
                            SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
                                'RISK_FRAUD_COPILOT.APP.RISK_FRAUD_AGENT',
                                '{{"messages": [{{"role": "user", "content": [{{"type": "text", "text": "{user_input.replace(chr(39), chr(39)+chr(39)).replace(chr(34), chr(92)+chr(34))}"}}]}}]}}'
                            ) AS response
                        """).collect()
                        
                        response = json.loads(result[0]['RESPONSE'])
                        if 'message' in response and response.get('code'):
                            st.warning("Agent encountered an issue. Falling back to direct query...")
                            # Fallback: use Cortex Complete
                            fallback = session.sql(f"""
                                SELECT SNOWFLAKE.CORTEX.COMPLETE(
                                    'llama3.1-70b',
                                    'You are a risk and compliance analyst. Based on the data context, answer: {user_input.replace(chr(39), chr(39)+chr(39))}'
                                ) AS answer
                            """).collect()
                            st.markdown(fallback[0]['ANSWER'])
                        else:
                            st.markdown(response.get('content', str(response)))
                    except Exception as e:
                        st.error(f"Error: {str(e)}")
            else:
                st.warning("Please enter a question.")

# --- Tab 2: Fraud Signals ---
with tab2:
    st.subheader("Fraud Signal Monitor")
    
    col1, col2, col3 = st.columns(3)
    with col1:
        severity_filter = st.multiselect("Severity", ["CRITICAL", "HIGH", "MEDIUM", "LOW"], default=["CRITICAL", "HIGH"])
    with col2:
        signal_filter = st.multiselect("Signal Type", ["VELOCITY_1MIN", "VELOCITY_1HR", "AMOUNT_ANOMALY", "HIGH_RISK_COUNTRY", "HIGH_RISK_CATEGORY"])
    with col3:
        days_back = st.slider("Days Back", 1, 30, 7)
    
    severity_clause = "'" + "','".join(severity_filter) + "'" if severity_filter else "'CRITICAL','HIGH'"
    
    query = f"""
        SELECT account_id, signal_type, severity, amount, merchant_country, 
               merchant_category, confidence_score, signal_timestamp
        FROM RISK_FRAUD_COPILOT.PROCESSED.FRAUD_SIGNALS
        WHERE severity IN ({severity_clause})
          AND signal_timestamp >= DATEADD(day, -{days_back}, CURRENT_TIMESTAMP())
    """
    if signal_filter:
        signal_clause = "'" + "','".join(signal_filter) + "'"
        query += f" AND signal_type IN ({signal_clause})"
    query += " ORDER BY signal_timestamp DESC LIMIT 100"
    
    fraud_df = session.sql(query).to_pandas()
    
    if not fraud_df.empty:
        # Summary chart
        signal_summary = fraud_df.groupby(['SIGNAL_TYPE', 'SEVERITY']).size().reset_index(name='COUNT')
        st.bar_chart(signal_summary.pivot(index='SIGNAL_TYPE', columns='SEVERITY', values='COUNT').fillna(0))
        
        st.dataframe(fraud_df, use_container_width=True)
    else:
        st.info("No fraud signals matching filters.")

# --- Tab 3: AML Alerts ---
with tab3:
    st.subheader("AML Alert Dashboard")
    
    col1, col2 = st.columns(2)
    with col1:
        aml_type = st.multiselect("Flag Type", ["STRUCTURING", "HIGH_VALUE_INTERNATIONAL", "PEP_ACTIVITY"], 
                                   default=["STRUCTURING", "HIGH_VALUE_INTERNATIONAL", "PEP_ACTIVITY"])
    with col2:
        action_filter = st.multiselect("Required Action", ["FILE_STR", "ENHANCED_DUE_DILIGENCE", "SENIOR_REVIEW"])
    
    aml_type_clause = "'" + "','".join(aml_type) + "'"
    aml_query = f"""
        SELECT a.account_id, a.flag_type, a.severity, a.required_action, 
               a.description, a.confidence_score, a.flag_date,
               r.customer_name, r.composite_risk_score
        FROM RISK_FRAUD_COPILOT.PROCESSED.AML_FLAGS a
        JOIN RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES r ON a.account_id = r.account_id
        WHERE a.flag_type IN ({aml_type_clause})
    """
    if action_filter:
        action_clause = "'" + "','".join(action_filter) + "'"
        aml_query += f" AND a.required_action IN ({action_clause})"
    aml_query += " ORDER BY a.flag_date DESC, a.confidence_score DESC LIMIT 100"
    
    aml_df = session.sql(aml_query).to_pandas()
    
    if not aml_df.empty:
        # Action required summary
        action_summary = aml_df['REQUIRED_ACTION'].value_counts()
        st.bar_chart(action_summary)
        
        # Highlight accounts needing SAR filing
        sar_accounts = aml_df[aml_df['REQUIRED_ACTION'] == 'FILE_STR']
        if not sar_accounts.empty:
            st.error(f"⚠ {len(sar_accounts)} accounts require STR/SAR filing")
            st.dataframe(sar_accounts[['ACCOUNT_ID', 'CUSTOMER_NAME', 'FLAG_TYPE', 'DESCRIPTION', 'COMPOSITE_RISK_SCORE', 'FLAG_DATE']], 
                        use_container_width=True)
        
        st.divider()
        st.dataframe(aml_df, use_container_width=True)
    else:
        st.info("No AML flags matching filters.")

# --- Tab 4: Risk Scores ---
with tab4:
    st.subheader("Account Risk Scores")
    
    col1, col2 = st.columns(2)
    with col1:
        min_score = st.slider("Minimum Risk Score", 0, 100, 30)
    with col2:
        risk_level = st.multiselect("Fraud Risk Level", ["HIGH", "MEDIUM", "LOW"], default=["HIGH", "MEDIUM"])
    
    risk_level_clause = "'" + "','".join(risk_level) + "'"
    risk_query = f"""
        SELECT account_id, customer_name, account_type, assigned_tier,
               composite_risk_score, fraud_risk_level, compliance_risk_level,
               total_transaction_volume, flagged_transaction_count,
               pep_flag, sanctions_flag, kyc_status
        FROM RISK_FRAUD_COPILOT.PROCESSED.RISK_SCORES
        WHERE composite_risk_score >= {min_score}
          AND fraud_risk_level IN ({risk_level_clause})
        ORDER BY composite_risk_score DESC
        LIMIT 50
    """
    
    risk_df = session.sql(risk_query).to_pandas()
    
    if not risk_df.empty:
        # Distribution chart
        st.bar_chart(risk_df.set_index('ACCOUNT_ID')['COMPOSITE_RISK_SCORE'].head(20))
        
        # Summary stats
        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric("Accounts Shown", len(risk_df))
        with col2:
            st.metric("Avg Score", f"{risk_df['COMPOSITE_RISK_SCORE'].mean():.1f}")
        with col3:
            st.metric("PEP Accounts", risk_df['PEP_FLAG'].sum())
        with col4:
            st.metric("Sanctioned", risk_df['SANCTIONS_FLAG'].sum())
        
        st.dataframe(risk_df, use_container_width=True)
    else:
        st.info("No accounts matching filters.")

# --- Export Report ---
if st.session_state.get('export_report'):
    st.divider()
    st.subheader("Audit Report Export")
    
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
    
    st.markdown(f"""
    ### Audit Report: Accounts Requiring STR Filing
    **Generated**: {st.session_state.get('report_date', 'Today')}  
    **Total Findings**: {len(report_data)}  
    **Report Type**: Suspicious Transaction Report (STR) Candidates
    """)
    
    st.dataframe(report_data, use_container_width=True)
    st.download_button(
        "Download CSV",
        report_data.to_csv(index=False),
        "audit_report_str_candidates.csv",
        "text/csv"
    )
    st.session_state['export_report'] = False
