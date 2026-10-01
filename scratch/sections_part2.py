"""
Sections Part 2: Sections 11 through 18
24-Role Catalog, End-to-End Upgrade Workflow, Multi-Hop Upgrade Model,
Prevalidation Framework, Auto-Remediation Engine, Live Monitoring,
Postvalidation & Baseline Diff, Operator Upgrade Workflow.
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

def build_part2(doc):
    # =========================================================================
    # 11. 24-ROLE CATALOG & ARCHITECTURAL TAXONOMY
    # =========================================================================
    add_h(doc, "11. 24-Role Catalog & Architectural Taxonomy", level=1)
    add_p(doc, "The automation suite is modularized into exactly 24 single-purpose roles under playbooks/roles/. Each role strictly owns one functional concern, adheres to standardized dual-version header schemas, and defines typed variable defaults in defaults/main.yml.")

    add_fig(doc, "fig10_role_interaction.png", 10, "Role Interaction & Architectural Categorization",
            "Taxonomy mapping all 24 modular roles across 8 architectural functional groups and illustrating phase delegation contracts.")

    add_h(doc, "11.1 Comprehensive 24-Role Technical Inventory", level=2)
    
    role_headers = ["Role Name", "Domain Group", "Purpose & Target Operation", "Inputs & Registered Facts", "Gate"]
    role_data = [
        ["login", "Session & Infra", "OpenShift CLI login via execve argv; validates API URL regex", "cluster_username, cluster_password -> cluster_kubeconfig", "HARD"],
        ["logout", "Session & Infra", "Token revocation & idempotent deletion of scoped kubeconfig", "kubeconfig_path -> unsets session facts", "N/A"],
        ["snapshot", "Session & Infra", "Captures Phase 01 cluster state JSON baseline (nodes, CO, routes)", "cluster_name -> baseline_snapshot_file_path", "HARD"],
        ["api_check", "Health Checks", "Validates active server URL against desired regex pattern", "desired_cluster_api_regex -> health_summary", "HARD"],
        ["api_readiness", "Health Checks", "Queries raw /readyz endpoint for 'ok' response", "oc_command_retries -> health_summary", "HARD"],
        ["co", "Health Checks", "Evaluates all ClusterOperators for Available=True & Degraded=False", "co_allow_list -> co_degraded, co_unavailable", "HARD"],
        ["mcp", "Health Checks", "Verifies MachineConfigPools are Updated=True & Degraded=False", "mcp_all_pools -> mcp_parsed_data", "HARD"],
        ["node", "Health Checks", "Evaluates Node Readiness (100% Ready) & Pressure conditions", "allowed_unschedulable_nodes -> node_not_ready_list", "HARD"],
        ["etcd", "Health Checks", "Control-plane etcd database health & pod quorum (>= 3 pods)", "etcd_expected_pods -> etcd_co_available", "HARD"],
        ["utilization", "Capacity", "Cluster CPU & Memory allocatable vs requested resource audit", "max_cpu_percent, max_memory_percent -> health_summary", "HARD"],
        ["pv", "Storage", "Verifies PersistentVolumes are in Bound or Available phase", "pv_enforce_gate (default false) -> pv_failed_list", "WARN"],
        ["pvc", "Storage", "Verifies PersistentVolumeClaims across all namespaces are Bound", "pvc_enforce_gate (default false) -> pvc_pending_list", "WARN"],
        ["pdb", "Disruption", "Audits PodDisruptionBudgets for zero-disruption deadlocks", "fail_on_zero_disruption_pdb -> pdb_violating_list", "WARN"],
        ["prevalidation", "Aggregators", "Consolidates 14 pre-upgrade health checks; suppresses role gates", "upgrade_path -> health_summary (14 items)", "HARD"],
        ["postvalidation", "Aggregators", "Executes 10 post-upgrade checks & computes baseline diff", "baseline_snapshot_file -> postval_health_summary", "HARD"],
        ["upgrade", "Engine", "Updates channel, confirms live edge, triggers oc adm upgrade", "target_version, target_channel -> hop_version", "HARD"],
        ["monitor", "Engine", "2m polling loop, settle-gate evaluation, 20m heartbeat emails", "poll_interval, hop_timeout -> settle_gate_passed", "HARD"],
        ["remediate", "Auto-Fix", "Three-tier auto-remediation engine for known blockers", "auto_remediation_enabled -> autofix_items", "AUTO"],
        ["operator_compat", "Operators", "Scans installed OLM subscriptions for target channel compatibility", "target_minor_version -> operator_compat_plan", "HARD"],
        ["operator_upgrade", "Operators", "Approves manual InstallPlans & tracks CSV rollout (Tier 2 retry)", "operator_upgrade_timeout -> unapproved_plans", "HARD"],
        ["operator_validate", "Operators", "Validates active CSVs report Succeeded; triggers HTML report", "operator_validate_enforce_gate -> operator_results", "HARD"],
        ["sendmail", "Reporting", "Direct SMTP delivery via native mail module; clears facts post-dispatch", "mail_template, mail_to -> clears mail_html_body", "N/A"],
        ["report", "Reporting", "Generates client-facing HTML reports via health-overview.j2", "health_summary -> output/<cluster>_*.html", "N/A"],
        ["error_handle", "Reporting", "Hierarchical error extraction, RBAC detection, alert email dispatch", "ansible_failed_result -> is_rbac_error", "N/A"]
    ]
    add_tbl(doc, role_headers, role_data, col_widths=[1.1, 1.1, 2.3, 1.5, 0.5])

    # =========================================================================
    # 12. END-TO-END UPGRADE WORKFLOW
    # =========================================================================
    add_h(doc, "12. End-to-End Upgrade Workflow", level=1)
    add_p(doc, "The end-to-end upgrade workflow follows a strictly deterministic 19-step sequence from operational invocation to audit completion:")

    add_fig(doc, "fig04_end_to_end_workflow.png", 4, "End-to-End Upgrade Execution Flow",
            "Chronological 19-step workflow diagram illustrating pre-flight checks, session login, baseline capture, preval, multi-hop upgrades, settle gates, postval, and digest closeout.")

    add_h(doc, "12.1 Chronological Execution Stages", level=2)
    steps = [
        ("Step 1: Pre-flight Validation", "00_Run.sh validates local bash, oc client, jq 1.5, and python dependencies before launching Ansible."),
        ("Step 2: Configuration & Schema Check", "Python yaml.safe_load validates all 6 vars/*.yml files, ensuring no syntax errors or missing required keys."),
        ("Step 3: Interactive Selection Menus", "The operator selects the target cluster, upgrade path, and execution mode via 72-column box menus."),
        ("Step 4: Tier-Aware Risk Gate", "Risk is evaluated; if target cluster is PROD, the operator must type 'UPGRADE' to proceed."),
        ("Step 5: Concurrency Lock Acquisition", "00_Run.sh verifies /tmp/aro-upgrade-<cluster>.lock; kills stale locks or halts if a live run is in progress."),
        ("Step 6: Session Authentication (Phase 01)", "roles/login authenticates via oc login with argv: bypass, writing to .kubeconfig-<cluster>."),
        ("Step 7: Baseline Snapshot Capture", "roles/snapshot queries cluster version, nodes, operators, and routes, writing JSON to snapshots/."),
        ("Step 8: Update Edge Validation", "01_Policy_Check.yaml verifies that upgrade_path[0] is an available or conditional update edge."),
        ("Step 9: 14-Check Prevalidation Scan", "02_Pre_upgrade_check.yaml runs 14 comprehensive health checks (suppressing individual gates)."),
        ("Step 10: Auto-Remediation Execution", "If blockers exist and auto_remediation_enabled is true, roles/remediate resolves cgroup, admin-acks, or MCPs."),
        ("Step 11: Re-verification & Preval Report", "Failed checks are re-evaluated; status marked AUTO-FIXED or FIX-FAILED; HTML report generated."),
        ("Step 12: Dry-Run Intercept (Optional)", "If dry_run=true or stop_after_phase<=2, the workflow logs completion, executes logout, and exits cleanly."),
        ("Step 13: Per-Hop Upgrade Initiation", "03_Initiate_upgrade.yaml loops tasks/hop.yml: sets channel, re-verifies edge, triggers oc adm upgrade."),
        ("Step 14: Live Monitoring & Telemetry", "roles/monitor polls every 2 mins; sends 20-min heartbeats and immediate state alerts via sendmail."),
        ("Step 15: Settle-Gate Verification", "Asserts CV at target version, Progressing=False, all COs healthy, all MCPs updated; dispatches hop email."),
        ("Step 16: Postvalidation & Baseline Diff", "05_post_Upgrade_Checks.yaml runs 10 checks and structural diff against Phase 01 snapshot; generates report."),
        ("Step 17: Operator Upgrade & Validation", "06_Operator_Upgrade.yaml scans OLM compatibility, approves InstallPlans, settles CSVs, renders operator report."),
        ("Step 18: 4-Attachment Completion Digest", "Dispatches final email with 4 attached reports (Preval, Postval, Operator HTML + run log)."),
        ("Step 19: Terminal Teardown & Summary", "roles/logout revokes token and removes kubeconfig; 00_Run.sh removes PID lock and prints execution summary.")
    ]
    for s_title, s_desc in steps:
        add_b(doc, s_desc, bold_prefix=f"{s_title}: ")

    # =========================================================================
    # 13. MULTI-HOP UPGRADE MODEL
    # =========================================================================
    add_h(doc, "13. Multi-Hop Upgrade Model & Settle Gates", level=1)
    add_p(doc, "OpenShift upgrades across minor versions (Y-stream) require strict sequential adherence. OpenShift does not support jumping across minor releases (e.g. 4.18 directly to 4.20). The automation enforces this multi-hop discipline through deterministic iteration:")

    add_fig(doc, "fig05_multihop_upgrade_flow.png", 5, "Multi-Hop Upgrade Model & Sequential Settle Gates",
            "Illustrating sequential Y-stream progression (4.18.09 -> 4.19.15 -> 4.20.08), live channel edge verification, and mandatory per-hop settle gates.")

    add_h(doc, "13.1 Per-Hop Lifecycle Execution (tasks/hop.yml)", level=2)
    add_p(doc, "For every version item in upgrade_path, the automation executes tasks/hop.yml through a standardized 7-step lifecycle:")
    add_b(doc, "Computes hop_number, hop_total, and hop_label (e.g. 'Hop 1 of 2: -> 4.19.15').", bold_prefix="1. Metadata Resolution: ")
    add_b(doc, "Verifies cluster is stable, unblocked, not actively updating, and has 0 degraded pools.", bold_prefix="2. Pre-Hop Settle Assertion: ")
    add_b(doc, "Updates channel via oc adm upgrade channel and confirms target version is a verified live edge.", bold_prefix="3. Channel & Edge Confirmation: ")
    add_b(doc, "Ensures required dynamic administrator acknowledgements are applied prior to triggering mutation.", bold_prefix="4. Admin-Ack Pre-Patch: ")
    add_b(doc, "Executes oc adm upgrade --to=<version>; records initiation timestamp in run logs.", bold_prefix="5. Upgrade Trigger: ")
    add_b(doc, "Hands off control to 04_Live_monitoring_upgrade.yaml; polls every 2 minutes with 90-minute timeout.", bold_prefix="6. Live Monitoring Hand-off: ")
    add_b(doc, "Asserts CV at target, Available=True, Progressing=False, all COs healthy, all MCPs updated; dispatches hop-complete notification.", bold_prefix="7. Settle-Gate Passage: ")

    # =========================================================================
    # 14. PREVALIDATION FRAMEWORK
    # =========================================================================
    add_h(doc, "14. Prevalidation Framework (14-Check Contract)", level=1)
    add_p(doc, "Phase 02 executes an exhaustive 14-check prevalidation scan. To ensure complete cluster visibility, individual role gates are suppressed during the initial sweep, allowing all 14 checks to execute and populate health_summary before evaluating gates.")

    add_fig(doc, "fig16_venn_diagram.png", 16, "Three-Way Health, Remediation & Postval Overlap",
            "Venn diagram illustrating overlapping health verification pillars: Prevalidation checks, Auto-Remediation capabilities, and Postvalidation audit controls.")

    add_h(doc, "14.1 Exhaustive 14-Check Technical Contract", level=2)
    
    preval_headers = ["#", "Check Name", "Role / Target", "PASS Condition", "FAIL Condition", "Remediation", "Gate"]
    preval_data = [
        ["01", "ClusterOperators", "roles/co", "All COs Available=True & Degraded=False", "Any CO degraded or unavailable", "Tier 2: Pod Restart", "HARD"],
        ["02", "Node Readiness", "roles/node", "100% of nodes Ready=True; Pressures=0", "Any node NotReady or pressure true", "None (Manual SRE)", "HARD"],
        ["03", "MachineConfigPools", "roles/mcp", "All MCPs Updated=True & Degraded=False", "Any MCP updating or degraded", "Tier 1: Auto-Unpause", "HARD"],
        ["04", "API Context", "roles/api_check", "Active server URL matches desired regex", "Mismatched or untrusted endpoint", "None (Session Halt)", "HARD"],
        ["05", "API Readiness", "roles/api_readiness", "Raw /readyz endpoint returns 'ok'", "/readyz returns non-200 or failure", "None (Session Halt)", "HARD"],
        ["06", "etcd Health", "roles/etcd", ">=3 pods Running/Ready; co/etcd healthy", "Pod count < 3 or co/etcd degraded", "None (Quorum Halt)", "HARD"],
        ["07", "Admin-Acks", "inline preval", "No Upgradeable=False AdminAckRequired", "Pending administrator ack required", "Tier 1: Dynamic Ack", "HARD"],
        ["08", "Node Utilization", "roles/utilization", "CPU & Memory allocatable requests < 90%", "CPU or Memory requests >= 90%", "None (Eviction Guard)", "HARD"],
        ["09", "Pending CSRs", "inline preval", "Zero pending node/client CSRs", "Pending certificate requests found", "None (Advisory)", "WARN"],
        ["10", "PersistentVolumes", "roles/pv", "All PVs in Bound or Available phase", "PVs in Failed or Released phase", "None (Advisory)", "WARN"],
        ["11", "VolumeClaims", "roles/pvc", "All PVCs in Bound phase across all namespaces", "PVCs in Pending or Lost phase", "None (Advisory)", "WARN"],
        ["12", "PodDisruptionBudgets", "roles/pdb", "No zero-disruption budgets on active pods", "disruptionsAllowed=0 & expectedPods>0", "None (Advisory)", "WARN"],
        ["13", "Critical Pods", "inline preval", "openshift-* pods free of CrashLoopBackOff", "System platform pods crashing", "None (Advisory)", "WARN"],
        ["14", "CGroup Mode", "inline preval", "cgroupMode=v2 if target >= 4.19", "cgroupMode=v1 on >= 4.19 target", "Tier 1: cgroup v2 patch", "WARN"]
    ]
    add_tbl(doc, preval_headers, preval_data, col_widths=[0.4, 1.4, 1.1, 1.7, 1.4, 1.1, 0.6])

    # =========================================================================
    # 15. AUTO-REMEDIATION ENGINE
    # =========================================================================
    add_h(doc, "15. Three-Tier Auto-Remediation Engine", level=1)
    add_p(doc, "The automation suite incorporates a deterministic, three-tiered auto-remediation engine (roles/remediate) engineered to automatically resolve well-understood upgrade blockers without manual human intervention while strictly safeguarding cluster integrity.")

    add_fig(doc, "fig06_auto_remediation_flow.png", 6, "Three-Tier Auto-Remediation Decision Logic",
            "Deterministic auto-remediation decision flow: blocker detection, feature toggle gating, Tier 1/2/3 execution, state re-verification, and status classification.")

    add_h(doc, "15.1 Architectural Tier Definitions", level=2)
    add_b(doc, "Safe, zero-data-loss, official Red Hat remediation procedures. Enabled by default (auto_remediation_enabled: true). Includes CGroup v2 migration, dynamic admin-acks, MachineConfigPool unpausing, and transient CLI command retries.", bold_prefix="Tier 1 (Auto-Fix, Default ON): ")
    add_b(doc, "Targeted recovery procedures for transient or non-fatal component degradation. Disabled by default; requires explicit opt-in. Includes Degraded ClusterOperator pod restarts (3-minute grace period), stalled node MCD force re-applies, and operator CSV rollout retries.", bold_prefix="Tier 2 (Guided Recovery, Default OFF): ")
    add_b(doc, "Complex architectural conflicts where automated heuristics would risk cluster instability (e.g. Gateway API CRD ownership conflicts). Execution halts immediately with actionable diagnostic guidance.", bold_prefix="Tier 3 (Hard-Stop, Zero Guesswork): ")

    add_h(doc, "15.2 Blocker Resolution Details", level=2)
    add_p(doc, "1. CGroup Mode Migration (Blocker 1): Clusters running cgroup v1 block upgrades to OpenShift 4.19+. When upgrading to >= 4.19, roles/remediate applies a JSON merge patch to nodes.config/cluster setting spec.cgroupMode: 'v2', re-verifies via jsonpath, and records status as AUTO-FIXED.")
    add_p(doc, "2. Dynamic Admin Acknowledgements (Blocker 2): OpenShift minor upgrades often require acknowledging deprecated APIs. The role parses Upgradeable=False conditions from ClusterVersion, extracts acknowledgement keys matching ack-*.api-removals-in-*, patches openshift-config/admin-acks ConfigMap, and records AUTO-FIXED.")
    add_p(doc, "3. MachineConfigPool Auto-Unpause (Blocker 3): Paused worker or master pools prevent MachineConfig rollouts. The role checks mcp_auto_unpause_list, applies spec.paused: false via JSON patch, confirms pool unpaused, and records AUTO-FIXED.")

    # =========================================================================
    # 16. LIVE MONITORING & SETTLE GATES
    # =========================================================================
    add_h(doc, "16. Live Monitoring Loop & Telemetry Engine", level=1)
    add_p(doc, "Phase 04 drives continuous cluster telemetry during version rollouts through roles/monitor. It executes a bounded polling loop executing poll_iteration.yml every 2 minutes until settle-gate criteria are satisfied or the 90-minute timeout guard expires.")

    add_fig(doc, "fig09_monitoring_loop.png", 9, "Live Monitoring Loop & Telemetry Engine",
            "Bounded 2-minute polling loop with real-time state change detection, 20-minute HTML progress heartbeats, 90-minute timeout guard, and settle-gate evaluation.")

    add_h(doc, "16.1 Telemetry Metrics & Alerting Cadence", level=2)
    add_b(doc, "ClusterVersion, MachineConfigPools (updated, updating, degraded machine counts), ClusterOperators, and Node Ready/Pressure states are queried live via oc get -o json and parsed via jq 1.5.", bold_prefix="2-Minute Polling Cycle: ")
    add_b(doc, "Every 20 minutes elapsed, roles/sendmail dispatches progress-mail.j2 featuring cluster name, hop counter, target version, rollout progress bar, and MCP machine tables.", bold_prefix="20-Minute Progress Heartbeat: ")
    add_b(doc, "If a node transitions to NotReady, or an MCP enters Degraded state, an immediate alert email is dispatched highlighting the degraded resource and diagnostic logs.", bold_prefix="Immediate State-Change Alerts: ")
    add_b(doc, "If an upgrade hop exceeds 90 minutes without settling, execution terminates with Exit Code 30, logs the failure, sends an alert email, and logs out cleanly.", bold_prefix="90-Minute Timeout Guard: ")

    add_h(doc, "16.2 Settle-Gate Contract", level=2)
    add_p(doc, "The settle-gate is the mandatory stability assertion executed between hops. A hop is declared settled only when ALL four criteria are simultaneously satisfied:")
    add_b(doc, "ClusterVersion reports desired.version equals target_version, Available=True, and Progressing=False.")
    add_b(doc, "ClusterVersion status.history[0] reports state: Completed.")
    add_b(doc, "All ClusterOperators report Available=True, Degraded=False, and Progressing=False (excluding co_allow_list).")
    add_b(doc, "All MachineConfigPools report Updated=True, Updating=False, Degraded=False, and readyMachineCount equals machineCount.")

    # =========================================================================
    # 17. POSTVALIDATION & BASELINE COMPARISON
    # =========================================================================
    add_h(doc, "17. Postvalidation Framework & Baseline Diff Analysis", level=1)
    add_p(doc, "Phase 05 executes following completion of all cluster hops. It runs a 10-check post-upgrade health validation contract and performs a structural diff against the Phase 01 baseline snapshot to identify missing or degraded cluster components.")

    add_fig(doc, "fig08_baseline_snapshot_dataflow.png", 8, "Baseline Snapshot Data Flow & Postval Diff",
            "Single cross-phase persistence data flow: Phase 01 baseline capture to Phase 05 structural diff auditing nodes, operators, and routes.")

    add_h(doc, "17.1 10-Check Postvalidation Contract", level=2)
    
    postval_headers = ["#", "Postval Check Name", "Target Resource", "Evaluation Criteria", "Gate"]
    postval_data = [
        ["01", "Final ClusterVersion", "clusterversion/version", "Matches final_target_version; Available=True; Progressing=False", "HARD"],
        ["02", "ClusterOperators Health", "clusteroperators", "All operators Available=True; Degraded=False; Progressing=False", "HARD"],
        ["03", "MachineConfigPool Status", "mcp (all pools)", "All pools Updated=True; Updating=False; Degraded=False", "HARD"],
        ["04", "Node Readiness & Kubelet", "nodes", "100% Ready=True; kubelet versions match target minor 1.(Y+13)", "HARD"],
        ["05", "Node Pressure Conditions", "nodes", "Zero DiskPressure, MemoryPressure, or PIDPressure across all nodes", "HARD"],
        ["06", "etcd Database Health", "openshift-etcd", ">= 3 control-plane pods Running/Ready; co/etcd Available & Not Degraded", "HARD"],
        ["07", "PersistentVolume Status", "pv", "All storage volumes in Bound or Available phase (0 Failed/Released)", "WARN"],
        ["08", "Core Namespace Pods", "openshift-*", "Platform pods free of CrashLoopBackOff or continuous restarts", "WARN"],
        ["09", "Firing Critical Alerts", "Prometheus Alertmanager", "Zero firing critical platform alerts queried via Prometheus API", "WARN"],
        ["10", "Baseline Snapshot Diff", "snapshots/ JSON vs live", "Structural parity on node count, operator list, and exposed routes", "WARN"]
    ]
    add_tbl(doc, postval_headers, postval_data, col_widths=[0.4, 1.8, 1.4, 2.7, 0.6])

    add_h(doc, "17.2 Baseline Structural Diff Audit Details", level=2)
    add_p(doc, "Check 10 slurps snapshots/<cluster>_<ts>_baseline.json and compares it with live cluster queries:")
    add_b(doc, "Compares total node count and individual node names; surfaces any node that failed to rejoin the cluster following reboot.", bold_prefix="Node Inventory Diff: ")
    add_b(doc, "Compares all active ClusterOperators; asserts that no previously available operators have degraded or disappeared.", bold_prefix="Operator State Diff: ")
    add_b(doc, "Compares exposed OpenShift route hostnames across all namespaces; surfaces any missing ingress routes.", bold_prefix="Route Availability Diff: ")

    # =========================================================================
    # 18. OPERATOR UPGRADE WORKFLOW
    # =========================================================================
    add_h(doc, "18. Phase 06: Operator Upgrade & CSV Settle Workflow", level=1)
    add_p(doc, "Phase 06 executes after the underlying OpenShift cluster upgrade is settled and verified. It is driven by 06_Operator_Upgrade.yaml and orchestrates the lifecycle of installed Operator Lifecycle Manager (OLM) subscriptions.")

    add_h(doc, "18.1 Non-Interfering Failure Domain Invariant", level=2)
    add_alert(doc, "NON-INTERFERING FAILURE DOMAIN: An operator upgrade failure during Phase 06 NEVER rolls back or invalidates completed cluster upgrade hops. The cluster upgrade is finalized. Phase 06 alerts and reports its findings independently without mutating cluster version states.", "CORE RESILIENCE INVARIANT", "important")

    add_h(doc, "18.2 Operator Lifecycle Execution Sequence", level=2)
    add_b(doc, "roles/operator_compat resiliently queries all installed subscriptions (oc get subscriptions.operators.coreos.com -A -o json), inspects PackageManifests, and builds operator_compat_plan matching target OpenShift channels (e.g. stable-4.16).", bold_prefix="1. Compatibility Scan: ")
    add_b(doc, "roles/operator_upgrade discovers unapproved manual InstallPlans (spec.approved: false) and sequentially approves them via JSON merge patch.", bold_prefix="2. InstallPlan Approval: ")
    add_b(doc, "Tracks ClusterServiceVersions (CSVs) in a bounded loop until reaching phase: Succeeded. If a CSV fails, Tier 2 recovery deletes the failed CSV once to trigger clean OLM subscription reconciliation.", bold_prefix="3. CSV Rollout Tracking & Tier 2 Retry: ")
    add_b(doc, "roles/operator_validate verifies all installed subscriptions reference healthy, Succeeded CSVs and renders output/<cluster>_operators_<ts>.html via health-overview.j2.", bold_prefix="4. Health Validation & Report: ")
    add_b(doc, "Gathers all 4 audit artifacts, dispatches the final Upgrade-Complete digest email via roles/sendmail, and executes definitive terminal logout via roles/logout.", bold_prefix="5. Closeout & Teardown: ")

    return doc

print("sections_part2 module loaded successfully.")
