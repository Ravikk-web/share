"""
Sections Part 3: Sections 19 through 25
Complete Module Wirings & Architectural Interconnections (Core Focus),
Variables & Configuration Reference, Security Architecture,
Deployment & Jump Host Setup, Operational Runbook,
Reporting & Notifications, Logging, Audit & Evidence.
"""

import os
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT

from scratch.build_complete_word_doc import (
    add_h, add_p, add_b, add_alert, add_fig, add_tbl,
    C_NAVY, C_BLUE, C_GREEN, C_AMBER, C_RED, C_SLATE, C_BODY, C_MUTED
)

def build_part3(doc):
    # =========================================================================
    # 19. COMPLETE MODULE WIRINGS & ARCHITECTURAL INTERCONNECTIONS
    # =========================================================================
    add_h(doc, "19. Complete Module Wirings & Architectural Interconnections", level=1)
    add_p(doc, "This section documents the comprehensive end-to-end architectural wiring of the ARO Cluster Upgrade Automation suite. It defines the exact caller-callee hierarchies, playbook-to-role delegations, task inclusions, registered fact flows, inter-phase data contracts, settle-gate decision logic, and error escalation paths across all 7 process files, 24 modular roles, 6 configuration files, and 3 presentation templates.")

    add_fig(doc, "fig18_module_wiring_fact_flow.png", 18, "Complete Module Wirings, Caller-Callee Bindings & Fact Flow",
            "Exhaustive component wiring diagram illustrating exact caller-callee bindings, registered fact handoffs, task inclusions, and presentation consumers.")

    add_h(doc, "19.1 Master Orchestrator Wiring (main.yml)", level=2)
    add_p(doc, "The master orchestrator main.yml is the central spine of the automation. It is structured into 3 distinct operational phases: initialization, phase chaining, and lifecycle boundary intercepts:")
    add_b(doc, "Loads all 6 configuration files (vars/upgrade.yml, secrets.yml, paths.yml, smtp.yml, report_vars.yml, api_regex.yml) into localhost host facts. Asserts that cluster_name and upgrade_path are defined and non-empty; renders dispatch debug banner.", bold_prefix="1. Initialization Play: ")
    add_b(doc, "Chains phase playbooks sequentially via import_playbook with strict conditional evaluation:", bold_prefix="2. Phase Import Chain: ")
    add_b(doc, "import_playbook: 01_Policy_Check.yaml when: (skip_to_phase <= 1) and (stop_after_phase >= 1)")
    add_b(doc, "import_playbook: 02_Pre_upgrade_check.yaml when: (skip_to_phase <= 2) and (stop_after_phase >= 2)")
    add_b(doc, "Prevalidation / Dry-Run Intercept Play: Evaluates when: dry_run or (stop_after_phase <= 2). Invokes roles/logout and terminates execution cleanly via meta: end_play.", bold_prefix="3. Dry-Run Intercept Play: ")
    add_b(doc, "import_playbook: 03_Initiate_upgrade.yaml when: not dry_run and (skip_to_phase <= 3) and (stop_after_phase >= 3)")
    add_b(doc, "import_playbook: 05_post_Upgrade_Checks.yaml when: not dry_run and (skip_to_phase <= 5) and (stop_after_phase >= 5)")
    add_b(doc, "Post-Check Intercept Play: Evaluates when: stop_after_phase <= 5. Invokes roles/logout and terminates execution via meta: end_play.", bold_prefix="4. Post-Check Intercept Play: ")
    add_b(doc, "import_playbook: 06_Operator_Upgrade.yaml when: not dry_run and (skip_to_phase <= 6) and (stop_after_phase >= 6)")

    add_h(doc, "19.2 Comprehensive Caller-Callee Binding Hierarchy", level=2)
    add_p(doc, "The following matrix details every component invocation, showing which playbook or task calls which downstream role or task file, the invocation mechanism used, and the operational condition governing execution:")
    
    wire_headers = ["Calling Component", "Target Component Called", "Mechanism", "Execution Condition / Trigger", "Purpose"]
    wire_data = [
        ["00_Run.sh", "main.yml", "ansible-playbook", "CLI launch", "Master orchestration dispatch with extra-vars JSON"],
        ["main.yml", "01_Policy_Check.yaml", "import_playbook", "skip_to_phase <= 1", "Phase 01: Auth, snapshot, edge check"],
        ["main.yml", "02_Pre_upgrade_check.yaml", "import_playbook", "skip_to_phase <= 2", "Phase 02: 14 health checks & auto-remediation"],
        ["main.yml", "roles/logout", "include_role", "dry_run or stop_after_phase <= 2", "Early session teardown for dry-run/pre-check"],
        ["main.yml", "03_Initiate_upgrade.yaml", "import_playbook", "not dry_run and skip_to_phase <= 3", "Phase 03: Sequential upgrade hop driver"],
        ["main.yml", "05_post_Upgrade_Checks.yaml", "import_playbook", "not dry_run and skip_to_phase <= 5", "Phase 05: 10 postval checks & baseline diff"],
        ["main.yml", "roles/logout", "include_role", "stop_after_phase <= 5", "Early session teardown for post-check only"],
        ["main.yml", "06_Operator_Upgrade.yaml", "import_playbook", "not dry_run and skip_to_phase <= 6", "Phase 06: Operator upgrades & terminal logout"],
        ["01_Policy_Check", "roles/login", "include_role", "Always in pre_tasks", "Single authentication establishing kubeconfig"],
        ["01_Policy_Check", "roles/snapshot", "include_role", "Following login", "Captures baseline JSON snapshot"],
        ["01_Policy_Check", "roles/error_handle", "include_role", "rescue: block on failure", "Hierarchical error extraction & alert mail"],
        ["01_Policy_Check", "roles/logout", "include_role", "rescue: and always: blocks", "Guaranteed session token revocation"],
        ["02_Pre_upgrade", "roles/prevalidation", "include_role", "Initial scan", "Executes 14 health checks; gathers health_summary"],
        ["02_Pre_upgrade", "roles/remediate", "include_role", "Blockers & auto_remediation_enabled", "Executes Tier 1/2 auto-remediation passes"],
        ["02_Pre_upgrade", "roles/report", "include_role", "Post-scan & post-fix", "Renders prevalidation HTML report in output/"],
        ["02_Pre_upgrade", "roles/error_handle", "include_role", "rescue: block on failure", "Hierarchical error extraction & alert mail"],
        ["02_Pre_upgrade", "roles/logout", "include_role", "rescue: and always: blocks", "Guaranteed session token revocation"],
        ["03_Initiate_upgrade", "tasks/hop.yml", "include_tasks (loop)", "loop: upgrade_path", "Drives single minor release upgrade hop"],
        ["tasks/hop.yml", "roles/upgrade", "include_role", "Pre-hop settled", "Sets channel, edge check, triggers oc adm upgrade"],
        ["tasks/hop.yml", "04_Live_monitoring", "include_tasks", "Post-upgrade trigger", "Handoff to live monitoring polling loop"],
        ["04_Live_monitoring", "roles/monitor", "include_role", "Always in Phase 04", "Drives 2m poll loop, heartbeats, settle-gate"],
        ["roles/monitor", "tasks/poll_iteration.yml", "include_tasks (loop)", "range(1, max_iterations)", "Single 2-min polling evaluation iteration"],
        ["poll_iteration.yml", "roles/sendmail", "include_role", "State change or 20m elapsed", "Dispatches HTML progress heartbeat email"],
        ["tasks/hop.yml", "roles/sendmail", "include_role", "Settle-gate passed", "Dispatches hop-complete email with preval report"],
        ["tasks/hop.yml", "roles/error_handle", "include_role", "rescue: block on failure", "Hierarchical error extraction & alert mail"],
        ["tasks/hop.yml", "roles/logout", "include_role", "rescue: block on failure", "Guaranteed session token revocation"],
        ["05_post_Upgrade", "roles/postvalidation", "include_role", "Always in Phase 05", "Executes 10 checks & baseline structural diff"],
        ["05_post_Upgrade", "roles/report", "include_role", "Postval complete", "Renders postvalidation HTML report in output/"],
        ["05_post_Upgrade", "roles/sendmail", "include_role", "send_postvalidation_email: true", "Dispatches postvalidation email with report"],
        ["05_post_Upgrade", "roles/error_handle", "include_role", "rescue: block on failure", "Hierarchical error extraction & alert mail"],
        ["05_post_Upgrade", "roles/logout", "include_role", "rescue: block on failure", "Guaranteed session token revocation"],
        ["06_Operator_Upgrade", "roles/operator_compat", "include_role", "Always in Phase 06", "Scans OLM subscriptions for channel compatibility"],
        ["06_Operator_Upgrade", "roles/operator_upgrade", "include_role", "not skip_operator_upgrade", "Approves InstallPlans, monitors CSVs, Tier 2 retry"],
        ["06_Operator_Upgrade", "roles/operator_validate", "include_role", "Always in Phase 06", "Validates Succeeded CSVs & renders report"],
        ["06_Operator_Upgrade", "roles/sendmail", "include_role", "All phases complete", "Dispatches final digest with 4 audit attachments"],
        ["06_Operator_Upgrade", "roles/logout", "include_role", "Final success & always: block", "Definitive terminal logout & kubeconfig removal"]
    ]
    add_tbl(doc, wire_headers, wire_data, col_widths=[1.3, 1.4, 1.2, 1.3, 1.8])

    add_h(doc, "19.3 Inbound & Outbound Data Fact Registry", level=2)
    add_p(doc, "The automation suite strictly coordinates state using registered Ansible host facts on localhost. The following registry documents all 30+ core operational facts, their exporting source, consuming components, data structures, and persistence lifecycle:")
    
    fact_headers = ["Fact Variable Name", "Exporting Source", "Consuming Components", "Data Type", "Lifecycle Scope"]
    fact_data = [
        ["cluster_name", "00_Run.sh / vars", "All playbooks & roles", "String", "Run Duration"],
        ["upgrade_path", "00_Run.sh / vars", "01, 02, 03, tasks/hop.yml", "List of Strings", "Run Duration"],
        ["run_timestamp", "00_Run.sh", "All playbooks, report, logs", "String (YYYYMMDD_HHMMSS)", "Run Duration"],
        ["dry_run", "00_Run.sh", "main.yml, hop.yml, monitor", "Boolean", "Run Duration"],
        ["auto_remediation_enabled", "vars/upgrade.yml", "02_Pre_upgrade, remediate", "Boolean", "Run Duration"],
        ["skip_to_phase", "00_Run.sh / CLI", "main.yml (import guards)", "Integer / String", "Run Duration"],
        ["stop_after_phase", "00_Run.sh / CLI", "main.yml (intercept plays)", "Integer / String", "Run Duration"],
        ["cluster_kubeconfig", "roles/login", "All oc CLI commands & roles", "String (File Path)", "Run Duration (Cleaned at logout)"],
        ["kubeconfig_path", "roles/login", "roles/logout, main.yml", "String (File Path)", "Run Duration (Cleaned at logout)"],
        ["active_cluster_server", "roles/login", "roles/api_check", "String (URL)", "Phase 01"],
        ["baseline_dict", "roles/snapshot", "roles/snapshot (to_nice_json)", "Dictionary", "Phase 01"],
        ["baseline_snapshot_file_path", "roles/snapshot", "05_post_Upgrade, postvalidation", "String (File Path)", "Cross-Phase Persistence"],
        ["health_summary", "roles/prevalidation", "roles/remediate, report, preval", "List of Dicts {num, name, status...}", "Phase 02"],
        ["autofix_items", "roles/remediate", "roles/report, health-overview.j2", "List of Dicts {action, target...}", "Phase 02"],
        ["report_file_path", "roles/report", "02, 05, 06, sendmail", "String (File Path)", "Per-Report Generation"],
        ["hop_number", "tasks/hop.yml", "roles/upgrade, monitor, sendmail", "Integer", "Per-Hop Loop"],
        ["hop_total", "tasks/hop.yml", "roles/upgrade, monitor, sendmail", "Integer", "Per-Hop Loop"],
        ["hop_label", "tasks/hop.yml", "roles/upgrade, monitor, sendmail", "String", "Per-Hop Loop"],
        ["hop_target_version", "tasks/hop.yml", "roles/upgrade, monitor, sendmail", "String (Semantic Version)", "Per-Hop Loop"],
        ["resolved_target_channel", "roles/upgrade", "tasks/hop.yml, monitor", "String (e.g. stable-4.19)", "Per-Hop Loop"],
        ["mcp_summary_table", "roles/monitor", "roles/sendmail, progress-mail.j2", "List of Dicts (pool counts)", "Monitoring Polling"],
        ["settle_gate_passed", "roles/monitor", "tasks/hop.yml", "Boolean", "Monitoring Settle Gate"],
        ["hop_elapsed_duration", "roles/monitor", "tasks/hop.yml, sendmail", "String", "Per-Hop Loop"],
        ["postval_health_summary", "roles/postvalidation", "roles/report, postval", "List of Dicts (10 checks)", "Phase 05"],
        ["postval_baseline_diff", "roles/postvalidation", "roles/report, health-overview.j2", "Dictionary (diff findings)", "Phase 05"],
        ["operator_compat_plan", "roles/operator_compat", "roles/operator_upgrade, validate", "List of Dicts (operator plans)", "Phase 06"],
        ["unapproved_plans", "roles/operator_upgrade", "roles/operator_upgrade (patch)", "List of Strings", "Phase 06"],
        ["operator_results", "roles/operator_validate", "roles/report, health-overview.j2", "List of Dicts", "Phase 06"],
        ["attached_reports", "06_Operator_Upgrade", "roles/sendmail, progress-mail.j2", "List of File Paths (4 files)", "Phase 06 Closeout"],
        ["resolved_error", "roles/error_handle", "roles/sendmail, error-report.j2", "String", "Rescue Blocks"],
        ["is_rbac_error", "roles/error_handle", "roles/sendmail, error-report.j2", "Boolean", "Rescue Blocks"]
    ]
    add_tbl(doc, fact_headers, fact_data, col_widths=[1.5, 1.2, 1.5, 1.1, 1.2])

    add_h(doc, "19.4 Inter-Role Fact Dependencies & Data Handoffs", level=2)
    add_p(doc, "Data contracts between roles are strictly coordinated through explicit fact handoffs:")
    add_b(doc, "roles/snapshot captures baseline JSON into snapshots/<cluster>_<ts>_baseline.json and registers baseline_snapshot_file_path. In Phase 05, roles/postvalidation slurps this exact file path, parses JSON via from_json, queries live cluster state, and computes the structural diff.", bold_prefix="1. Snapshot -> Postvalidation Diff Handoff: ")
    add_b(doc, "roles/prevalidation executes 14 checks and builds health_summary. If HARD blockers exist, roles/remediate consumes health_summary, executes targeted fixes, updates status to AUTO-FIXED (or FIX-FAILED), and appends audit logs to autofix_items. roles/report consumes both facts to render output/<cluster>_prevalidation_<ts>.html.", bold_prefix="2. Prevalidation -> Remediate -> Report Handoff: ")
    add_b(doc, "tasks/hop.yml sets hop_target_version; roles/upgrade triggers mutation; roles/monitor evaluates settle gate; on pass, roles/sendmail attaches the prevalidation HTML report and dispatches hop-complete notifications.", bold_prefix="3. Hop Driver -> Upgrade -> Monitor -> Sendmail Handoff: ")
    add_b(doc, "roles/operator_compat scans installed subscriptions and outputs operator_compat_plan. roles/operator_upgrade approves unapproved manual InstallPlans. roles/operator_validate confirms all CSVs Succeeded and delegates to roles/report to write output/<cluster>_operators_<ts>.html.", bold_prefix="4. Operator Compat -> Upgrade -> Validate -> Report Handoff: ")

    add_h(doc, "19.5 Settle-Gate & Decision Logic Wiring", level=2)
    add_p(doc, "The settle gate in roles/monitor/tasks/poll_iteration.yml is wired to evaluate strict boolean assertions before allowing tasks/hop.yml to advance:")
    add_p(doc, "cv_settled = (cv_version == target_version) and (cv_available == true) and (cv_progressing == false) and (cv_history_state == 'Completed')", bold_prefix="ClusterVersion Settle: ")
    add_p(doc, "co_settled = (co_degraded_count == 0) and (co_unavailable_count == 0) and (co_progressing_count == 0) [excluding co_allow_list]", bold_prefix="ClusterOperators Settle: ")
    add_p(doc, "mcp_settled = (mcp_updating_count == 0) and (mcp_degraded_count == 0) and (all mcp.readyMachineCount == mcp.machineCount)", bold_prefix="MachineConfigPool Settle: ")
    add_p(doc, "settle_gate_passed = cv_settled and co_settled and mcp_settled. When true, the polling loop breaks immediately, sets settle_gate_passed: true, records duration, and triggers hop completion.", bold_prefix="Master Settle Equation: ")

    add_h(doc, "19.6 Error Escalation & Fail-Safe Teardown Wiring", level=2)
    add_p(doc, "Failures occurring in any role bubble up deterministically through the calling playbook's rescue: block:")
    add_b(doc, "1. The task failure halts the block: immediately, transferring control to rescue:.")
    add_b(doc, "2. rescue: executes the hierarchical error extraction cascade: sets resolved_error from ansible_failed_result.stderr (fallback to stderr_lines, msg, or generic text).")
    add_b(doc, "3. Detects RBAC permission errors: searches resolved_error for 'forbidden', 'cannot patch', 'unauthorized', setting is_rbac_error: true.")
    add_b(doc, "4. Invokes roles/error_handle: records failure to failed_checks, writes dual run logs (.txt, .csv), and dispatches error-report.j2 via roles/sendmail with actionable RBAC remediation guidance.")
    add_b(doc, "5. The playbook's always: block unconditionally executes include_role: name: logout, guaranteeing that oc logout revokes the active token and deletes .kubeconfig-<cluster> under all conditions.")

    # =========================================================================
    # 20. VARIABLES & CONFIGURATION REFERENCE
    # =========================================================================
    add_h(doc, "20. Variables & Configuration Reference (All 6 Files)", level=1)
    add_p(doc, "All input variables are strictly externalized in playbooks/vars/. No logic resides in variable files, and all optional parameters carry defensive typed defaults.")

    add_h(doc, "20.1 Global Upgrade Variables (vars/upgrade.yml)", level=2)
    upg_vars_headers = ["Variable Name", "Type", "Default Value", "Purpose & Override Precedence"]
    upg_vars_data = [
        ["cluster_name", "String", "'' (Mandatory)", "Target cluster identifier matching vars/secrets.yml."],
        ["upgrade_path", "List", "[] (Mandatory)", "Ordered sequence of target minor versions (e.g. ['4.19.15', '4.20.08'])."],
        ["dry_run", "Boolean", "false", "When true, runs Phases 01-02 without cluster mutations; stops cleanly."],
        ["auto_remediation_enabled", "Boolean", "true", "Master switch enabling the three-tier auto-remediation engine."],
        ["auto_fix_cgroup_v2", "Boolean", "true", "Tier 1: Automatically patches nodes.config/cluster to cgroupMode: v2."],
        ["auto_apply_admin_acks", "Boolean", "true", "Tier 1: Dynamically patches openshift-config/admin-acks ConfigMap."],
        ["auto_unpause_mcp", "Boolean", "true", "Tier 1: Automatically unpauses permitted MachineConfigPools."],
        ["mcp_auto_unpause_list", "List", "['worker', 'master']", "Allow-list of pool names permitted for automated unpausing."],
        ["auto_restart_degraded_operators", "Boolean", "false", "Tier 2: Guided recovery restarting degraded operator pods (grace: 180s)."],
        ["auto_force_stalled_node", "Boolean", "false", "Tier 2: Triggers MCD force re-apply for nodes stalled > 30 mins."],
        ["poll_interval_minutes", "Integer", "2", "Polling interval for live monitoring loop in Phase 04."],
        ["hop_timeout_minutes", "Integer", "90", "Maximum elapsed time permitted for an individual upgrade hop."],
        ["heartbeat_minutes", "Integer", "20", "Cadence for dispatching HTML progress heartbeat emails."],
        ["oc_command_retries", "Integer", "3", "Bounded retry count for all cluster oc CLI queries and mutations."],
        ["oc_command_retry_delay", "Integer", "10", "Delay in seconds between transient oc CLI retry attempts."],
        ["co_allow_list", "List", "[]", "Exclusion list of ClusterOperators ignored during settle-gate checks."],
        ["skip_operator_upgrade", "Boolean", "false", "Bypasses Phase 06 manual InstallPlan approvals; runs validation only."]
    ]
    add_tbl(doc, upg_vars_headers, upg_vars_data, col_widths=[1.8, 0.7, 1.3, 2.7])

    add_h(doc, "20.2 Secrets Configuration (vars/secrets.yml)", level=2)
    add_p(doc, "Contains zero plaintext credentials. All sensitive fields are variable references: cluster_d01_password: '{{ vault_cluster_d01_password | default('') }}'. Defines the structured clusters map containing cluster_id, display_name, api_url, username, and tier (DEV, STAGE, PROD).")

    add_h(doc, "20.3 SMTP Notification Configuration (vars/smtp.yml)", level=2)
    add_p(doc, "Configures native direct SMTP delivery: smtp_server (localhost / corporate relay), smtp_port (25), smtp_sender, mail_to (primary operators), alert_mail_to (SRE on-call distribution list), postval_mail_to, and subject prefixes ([ARO Upgrade], [ARO Upgrade ALERT], [ARO Upgrade COMPLETE]).")

    add_h(doc, "20.4 Dynamic Directory Paths (vars/paths.yml)", level=2)
    add_p(doc, "Derives all filesystem locations dynamically from playbook_dir: log_dir: '{{ playbook_dir }}/logs', output_dir: '{{ playbook_dir }}/output', snapshot_dir: '{{ playbook_dir }}/snapshots', kubeconfig_path: '{{ playbook_dir }}/.kubeconfig-{{ cluster_name }}', oc_binary: 'oc'. Guarantees 100% portability without machine-specific hardcoded paths.")

    add_h(doc, "20.5 UI Design Tokens (vars/report_vars.yml)", level=2)
    add_p(doc, "Defines WCAG AA-compliant hex color codes, background tints, and status badge constants matching context/ui-context.md: status_pass (#1a7f37 / #e6f4ea / ✔), status_warn (#9a6700 / #fff8e1 / !), status_fail (#b42318 / #fdecea / ✖), status_autofix (#1d4ed8 / #eff6ff / ⚙), status_fixfailed (#c2410c / #ffedd5 / ⚠).")

    add_h(doc, "20.6 Input Validation Patterns (vars/api_regex.yml)", level=2)
    add_p(doc, "Enforces strict input validation regexes: desired_cluster_api_regex: '^https://api\\.[a-zA-Z0-9.-]+:6443/?$', ocp_version_regex: '^[0-9]+\\.[0-9]+\\.[0-9]+$', and cluster_name_regex: '^[a-zA-Z0-9_-]+$'.")

    # =========================================================================
    # 21. SECURITY ARCHITECTURE
    # =========================================================================
    add_h(doc, "21. Security Architecture & Trust Boundaries", level=1)
    add_p(doc, "Security is engineered into every layer of the automation suite, enforcing least privilege, zero credential leakage, session isolation, and auditability.")

    add_fig(doc, "fig07_auth_session_sequence.png", 7, "Authentication & Session Lifecycle Sequence",
            "Sequence diagram showing single oc login, dedicated kubeconfig isolation, cross-phase reuse, and guaranteed fail-safe teardown.")

    add_fig(doc, "fig12_security_trust_boundaries.png", 12, "Security Trust Boundaries & Data Protection",
            "The 4 security trust boundaries: Secrets repository, Runtime execution, Cluster session, and Output audit sanitization.")

    add_h(doc, "21.1 Dedicated Session Kubeconfig Isolation", level=2)
    add_p(doc, "The automation strictly avoids writing to or relying on the human engineer's default ~/.kube/config. Authentication writes exclusively to a cluster-scoped configuration file: {{ playbook_dir }}/.kubeconfig-{{ cluster_name }}. All oc CLI commands explicitly inject environment: KUBECONFIG: '{{ cluster_kubeconfig }}'. On logout, the file is deleted via file: state=absent.")

    add_h(doc, "21.2 Zero Credential Leaks (no_log & Argv Execution)", level=2)
    add_b(doc, "All authentication tasks and credential assertions declare no_log: true, preventing service account passwords or tokens from appearing in console stdout, Ansible job logs, or CI/CD pipelines.", bold_prefix="no_log Enforcement: ")
    add_b(doc, "roles/login executes oc login via Ansible's native command: module utilizing argv: list syntax. This passes arguments directly via execve() to the operating system, completely bypassing shell expansion and preventing password corruption on special characters ($) or whitespace.", bold_prefix="Argv Execution: ")
    add_b(doc, "Diagnostic failure messages in roles/login dynamically mask passwords using | replace(cluster_password, '******'), ensuring full error surfacing without credential compromise.", bold_prefix="Password Masking: ")

    add_h(doc, "21.3 CyberArk Conjur Vault Migration Readiness", level=2)
    add_p(doc, "Because all credentials in vars/secrets.yml are declared as variable references (e.g. cluster_d01_password: '{{ vault_cluster_d01_password }}'), migrating to CyberArk Conjur Vault in production requires zero task or role refactoring. Only the external secret lookup source is modified.")

    # =========================================================================
    # 22. DEPLOYMENT & JUMP HOST SETUP
    # =========================================================================
    add_h(doc, "22. Deployment & Jump Host Setup", level=1)
    add_p(doc, "The automation suite is deployed directly on an enterprise RHEL 8 jump server with network access to target ARO clusters.")

    add_fig(doc, "fig11_deployment_diagram.png", 11, "RHEL 8 Jump Server Deployment & Network Architecture",
            "Hardware, operating system, runtime dependencies, directory structures, and egress network flows (HTTPS 6443, SMTP 25).")

    add_h(doc, "22.1 Prerequisites & System Requirements", level=2)
    add_b(doc, "Red Hat Enterprise Linux 8.x (64-bit).", bold_prefix="Operating System: ")
    add_b(doc, "Ansible 2.7.17 (test jump hosts) or Ansible 2.14.18 (production environments); single codebase.", bold_prefix="Ansible: ")
    add_b(doc, "OpenShift CLI (oc) version >= 4.14 installed in /usr/local/bin/oc or system PATH.", bold_prefix="OpenShift Client: ")
    add_b(doc, "jq JSON processor version 1.5 (standard RHEL 8 repository package).", bold_prefix="jq Parser: ")
    add_b(doc, "Python 3.6+ with PyYAML, Jinja2, and standard smtplib library.", bold_prefix="Python Runtime: ")
    add_b(doc, "Network route to ARO API (port 6443) and corporate SMTP gateway (port 25).", bold_prefix="Network Access: ")

    add_h(doc, "22.2 Jump Host Installation Verification", level=2)
    add_p(doc, "Execute the following command to verify jump host prerequisites prior to launching the automation suite:")
    add_p(doc, "ansible --version && oc version --client && jq --version && python3 -c 'import yaml, smtplib; print(\"Environment OK\")'", italic=True)

    # =========================================================================
    # 23. OPERATIONAL RUNBOOK
    # =========================================================================
    add_h(doc, "23. Operational Runbook & Execution Guide", level=1)
    add_p(doc, "The operational runbook provides step-by-step guidance for platform operators executing cluster upgrades using the one-touch CLI entrypoint.")

    add_h(doc, "23.1 CLI Command Line Reference", level=2)
    add_p(doc, "Launch the automation suite from the playbooks/ directory using ./00_Run.sh:")
    add_p(doc, "./00_Run.sh [OPTIONS]", bold_prefix="Syntax: ")

    cli_headers = ["Flag / Option", "Argument", "Description & Operational Usage"]
    cli_data = [
        ["-c, --cluster", "<name>", "Specify target cluster name directly, bypassing cluster menu."],
        ["-p, --path", "<v1,v2...>", "Specify comma-separated upgrade path, bypassing path menu."],
        ["-d, --dry-run", "None", "Execute non-mutating pre-checks (Phases 01-02); halts before Phase 03."],
        ["--pre-check", "None", "Execute prevalidation with auto-remediation (Phases 01-02); stops before 03."],
        ["--post-check", "None", "Execute standalone postvalidation diffing (Phase 05); stops before 06."],
        ["-s, --skip-to-phase", "<NN>", "Skip to phase NN (02, 03, 05, or 06) for recovery or targeted runs."],
        ["--stop-after-phase", "<NN>", "Halt workflow cleanly immediately after phase NN."],
        ["--skip-cgroup", "None", "Bypass Check 14 cgroupMode validation and remediation."],
        ["--skip-operator-upgrade", "None", "Bypass Phase 06 manual InstallPlan approvals; validate only."],
        ["-y, --yes", "None", "Bypass interactive confirmation prompt (PROD still requires typing UPGRADE)."],
        ["--no-menu", "None", "Bypass all interactive menus; use configured defaults."],
        ["-v, --verbose", "None", "Enable verbose Ansible execution (-v)."],
        ["-q, --quiet", "None", "Suppress banner display and informational chatter."],
        ["-h, --help", "None", "Display formatted CLI help and argument reference."]
    ]
    add_tbl(doc, cli_headers, cli_data, col_widths=[1.7, 1.2, 3.6])

    add_h(doc, "23.2 CLI Exit Code Matrix", level=2)
    add_p(doc, "The CLI returns deterministic exit codes to integration pipelines and shell scripts:")
    
    code_headers = ["Exit Code", "Classification", "Operational Cause & Recommended Remediation"]
    code_data = [
        ["0", "Success", "Upgrade lifecycle or requested validation phase completed cleanly."],
        ["1", "Pre-flight Error", "Missing dependency (ansible, oc, jq, python) or invalid CLI flag."],
        ["2", "Operator Cancelled", "Operator aborted at confirmation prompt or failed PROD UPGRADE confirmation."],
        ["3", "Config Error", "vars/*.yml missing, YAML unparseable, or target cluster not configured."],
        ["10", "Preval Failed", "Phase 02 prevalidation failed with residual HARD blockers; review report."],
        ["20", "Upgrade Failed", "Phase 03 upgrade trigger or hop initiation failed; inspect clusterversion."],
        ["25", "Postval Failed", "Phase 05 postvalidation failed or baseline diff detected missing components."],
        ["30", "Monitoring Timeout", "Phase 04 settle-gate exceeded 90-minute timeout guard; check stalled nodes."],
        ["35", "Operator Failed", "Phase 06 operator compat, InstallPlan approval, or CSV settle failed."],
        ["99", "Playbook Crash", "Unexpected Ansible runtime error; inspect logs/<cluster>_<ts>.txt."]
    ]
    add_tbl(doc, code_headers, code_data, col_widths=[1.0, 1.5, 4.0])

    # =========================================================================
    # 24. REPORTING & NOTIFICATIONS
    # =========================================================================
    add_h(doc, "24. Reporting Architecture & Notification Engine", level=1)
    add_p(doc, "The automation suite generates client-facing, print-friendly standalone HTML audit reports and dispatches responsive HTML emails using direct SMTP.")

    add_fig(doc, "fig14_reporting_notification_flow.png", 14, "Reporting Architecture & Notification Engine",
            "Flow from in-memory health facts through roles/report and roles/sendmail to standalone HTML reports, progress emails, and completion digests.")

    add_h(doc, "24.1 Client-Facing Standalone HTML Reports (output/)", level=2)
    add_p(doc, "All reports are written to playbooks/output/ and styled via health-overview.j2 with modern CSS tokens, responsive layouts, and print styles:")
    add_b(doc, "output/<cluster>_prevalidation_<ts>.html: Renders header verdict badge, 5-tile summary metrics (total, passed, warnings, auto-fixed, failed), 14-check structured table, auto-remediation callout card, and collapsible diagnostic outputs.", bold_prefix="1. Prevalidation Report: ")
    add_b(doc, "output/<cluster>_postvalidation_<ts>.html: Renders 10 post-upgrade health checks, baseline structural diff audit table (node counts, operators, routes), and final cluster health verdict.", bold_prefix="2. Postvalidation Report: ")
    add_b(doc, "output/<cluster>_operators_<ts>.html: Renders installed OLM subscriptions, target channel recommendations, approval modes, CSV rollout phases, and compatibility status.", bold_prefix="3. Operator Report: ")

    add_h(doc, "24.2 Direct SMTP Notification Specifications", level=2)
    add_p(doc, "Emails are delivered via Ansible's native mail module directly to corporate relays on port 25 without local sendmail dependencies:")
    add_b(doc, "Max-width 580px card layout; header badge (Hop X of Y, target version, % complete, duration); MCP table (ready/total, updating, degraded); updating node tracker.", bold_prefix="Progress & Heartbeat Email (progress-mail.j2): ")
    add_b(doc, "High-visibility red accent border; UPGRADE HALTED banner; diagnostic failure matrix; conditional RBAC callout with copy-paste remediation commands.", bold_prefix="Failure Alert Email (error-report.j2): ")
    add_b(doc, "Dispatched upon full Phase 06 completion; summarizes total duration and hops; delivers ALL 4 core audit attachments (Preval HTML, Postval HTML, Operator HTML, and run log).", bold_prefix="Final Upgrade-Complete Digest: ")

    # =========================================================================
    # 25. LOGGING, AUDIT & EVIDENCE
    # =========================================================================
    add_h(doc, "25. Logging, Audit & Evidence Retention", level=1)
    add_p(doc, "The automation suite enforces strict auditability through dual-format logging and write-only persistence boundaries.")

    add_fig(doc, "fig15_storage_concurrency.png", 15, "Storage Architecture, Persistence & Concurrency Model",
            "Storage boundaries: PID lock file, ephemeral in-memory facts, baseline JSON snapshot, and write-only audit outputs.")

    add_h(doc, "25.1 Dual-Format Execution Logging (logs/)", level=2)
    add_p(doc, "Every run simultaneously generates two execution logs in playbooks/logs/:")
    add_b(doc, "logs/<cluster>_<ts>.txt: Real-time console output tee'd via 00_Run.sh, capturing every Ansible task, debug message, and CLI interaction.", bold_prefix="1. Text Console Log: ")
    add_b(doc, "logs/<cluster>_<ts>.csv: Machine-parseable audit record with standardized headers (timestamp, cluster, phase, step, task_name, gate_type, status, observed). Written continuously by roles/error_handle and phase playbooks.", bold_prefix="2. Structured CSV Log: ")

    add_h(doc, "25.2 Write-Only Boundary Principle", level=2)
    add_alert(doc, "WRITE-ONLY BOUNDARY PRINCIPLE: Files written to logs/, output/, and snapshots/ (with the sole exception of the Phase 01 baseline snapshot consumed by Phase 05) are write-only audit artifacts. They are NEVER ingested back into Ansible logic or orchestration decisions, eliminating circular dependencies.", "AUDIT ARCHITECTURE INVARIANT", "note")

    return doc

print("sections_part3 module loaded successfully.")
