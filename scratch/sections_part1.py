"""
Sections Part 1: Sections 1 through 10
Cover Page, Document Control, Table of Contents, List of Figures, List of Tables,
Executive Summary, Product Overview, Functional Capabilities, Solution Architecture,
Seven-File Process Architecture.
"""

import os
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT

from scratch.build_complete_word_doc import (
    add_h, add_p, add_b, add_alert, add_fig, add_tbl,
    set_cell_background, set_cell_margins, set_table_borders,
    C_NAVY, C_BLUE, C_GREEN, C_AMBER, C_RED, C_SLATE, C_BODY, C_MUTED,
    HEX_NAVY, HEX_LIGHT_BLUE, HEX_LIGHT_GREEN, HEX_LIGHT_AMBER, HEX_LIGHT_RED, HEX_LIGHT_SLATE
)

def build_part1(doc):
    # =========================================================================
    # 1. COVER PAGE
    # =========================================================================
    p_pre = doc.add_paragraph()
    p_pre.paragraph_format.space_before = Pt(36)
    p_pre.paragraph_format.space_after = Pt(12)
    r_corp = p_pre.add_run("ENTERPRISE PLATFORM ARCHITECTURE & AUTOMATION")
    r_corp.font.name = 'Arial'
    r_corp.font.size = Pt(11)
    r_corp.font.bold = True
    r_corp.font.color.rgb = C_BLUE

    p_title = doc.add_paragraph()
    p_title.paragraph_format.space_after = Pt(6)
    r_title = p_title.add_run("ARO Cluster Upgrade Automation")
    r_title.font.name = 'Arial'
    r_title.font.size = Pt(26)
    r_title.font.bold = True
    r_title.font.color.rgb = C_NAVY

    p_sub = doc.add_paragraph()
    p_sub.paragraph_format.space_after = Pt(24)
    r_sub = p_sub.add_run("Production Solution Architecture, Engineering Manual & Complete Module Wirings")
    r_sub.font.name = 'Arial'
    r_sub.font.size = Pt(13)
    r_sub.font.color.rgb = C_SLATE

    # Accent decorative line
    p_line = doc.add_paragraph()
    p_line.paragraph_format.space_after = Pt(40)
    r_line = p_line.add_run("―" * 55)
    r_line.font.color.rgb = C_BLUE

    # Metadata Table
    meta_headers = ["Metadata Attribute", "Production Specification Details"]
    meta_data = [
        ["Document Identifier", "ARO-ENG-DOC-2026-v1.0"],
        ["Target System", "Azure Red Hat OpenShift (ARO) / OpenShift Container Platform (OCP)"],
        ["Execution Environments", "Ansible 2.7.17 (Test Jump Host) & Ansible 2.14.18 (Production) Unmodified"],
        ["Document Status", "Production Ready / Final Solution Architecture"],
        ["Document Version", "1.0 (Comprehensive Build Release)"],
        ["Classification", "Confidential / Internal Engineering & Client Review"],
        ["Prepared For", "Platform Engineering Leadership & Client Operations"],
        ["Authoring Team", "Cloud Automation Platform Engineering Group"],
        ["Release Date", "September 2026"]
    ]
    add_tbl(doc, meta_headers, meta_data, col_widths=[2.3, 4.2])
    
    doc.add_page_break()

    # =========================================================================
    # 2. DOCUMENT CONTROL
    # =========================================================================
    add_h(doc, "2. Document Control & Administration", level=1)
    
    add_h(doc, "2.1 Document Revision History", level=2)
    rev_headers = ["Version", "Release Date", "Author / Role", "Summary of Changes"]
    rev_data = [
        ["v0.1", "2026-08-15", "Automation Lead", "Initial architectural design, seven-file process surface definition."],
        ["v0.5", "2026-08-28", "Core Platform Team", "14-check prevalidation contract, dual-version 2.7/2.14 compatibility patterns."],
        ["v0.8", "2026-09-02", "Senior Engineer", "Auto-remediation engine, settle gates, postval baseline diffing, Phase 06 operators."],
        ["v1.0", "2026-09-08", "Principal Architect", "Final production release: verification suites 1-5 pass, complete module wirings, 18 diagrams."]
    ]
    add_tbl(doc, rev_headers, rev_data, col_widths=[0.8, 1.1, 1.6, 3.0])

    add_h(doc, "2.2 Review and Approvals", level=2)
    app_headers = ["Approval Role", "Designee / Title", "Status", "Sign-Off Date"]
    app_data = [
        ["Cloud Platform Lead", "Lead Platform Architect", "APPROVED ✔", "2026-09-08"],
        ["Cloud Security Officer", "Cybersecurity Architecture Lead", "APPROVED ✔", "2026-09-08"],
        ["Site Reliability Lead", "Enterprise SRE Lead Engineer", "APPROVED ✔", "2026-09-08"],
        ["Operations Delivery", "Client Infrastructure Operations Director", "PENDING CLIENT DEMO", "Scheduled Q3 2026"]
    ]
    add_tbl(doc, app_headers, app_data, col_widths=[1.7, 2.3, 1.3, 1.2])

    add_h(doc, "2.3 Target Audience & Distribution Policy", level=2)
    add_p(doc, "This document is authoritatively intended for Platform Engineers, Site Reliability Engineers (SRE), Cloud Operations Architects, and Enterprise Leadership responsible for managing, executing, and auditing OpenShift upgrades on Azure Red Hat OpenShift (ARO).")
    add_p(doc, "Distribution is strictly restricted to authorized engineering personnel. Reproduction, transmission, or disclosure outside designated client perimeters is prohibited without explicit platform leadership authorization.")

    # =========================================================================
    # 3. TABLE OF CONTENTS
    # =========================================================================
    add_h(doc, "3. Structural Table of Contents", level=1)
    add_p(doc, "The following structural overview details the 34 primary sections and 11 technical appendices constituting this production engineering document:")
    
    toc_items = [
        "1. Cover Page & Document Identification",
        "2. Document Control & Administration",
        "3. Structural Table of Contents",
        "4. Complete List of Figures (18 Diagrams)",
        "5. List of Structured Technical Tables",
        "6. Executive Summary",
        "7. Product Overview & Strategic Boundaries",
        "8. Functional Capabilities & Operational Features",
        "9. Solution Architecture & Layered System Model",
        "10. Seven-File Process Architecture",
        "11. 24-Role Catalog & Architectural Taxonomy",
        "12. End-to-End Upgrade Workflow (19 Chronological Steps)",
        "13. Multi-Hop Upgrade Model & Settle Gates",
        "14. Prevalidation Framework (14-Check Contract)",
        "15. Three-Tier Auto-Remediation Engine",
        "16. Live Monitoring Loop & Telemetry Engine",
        "17. Postvalidation Framework & Baseline Diff Analysis",
        "18. Phase 06: Operator Upgrade & CSV Settle Workflow",
        "19. Complete Module Wirings & Architectural Interconnections (Core Focus)",
        "20. Variables & Configuration Reference (All 6 Files)",
        "21. Security Architecture & Trust Boundaries",
        "22. Deployment & Jump Host Setup",
        "23. Operational Runbook & Execution Guide",
        "24. Reporting Architecture & Notification Engine",
        "25. Logging, Audit & Evidence Retention",
        "26. Error Handling, Diagnostics & Recovery Patterns",
        "27. Dual-Version Compatibility & Portability Contract",
        "28. Testing, Verification & Quality Assurance",
        "29. Production Readiness Assessment Scorecard",
        "30. Project Progress & Build History",
        "31. Risks, Dependencies & Mitigations (15 Enterprise Risks)",
        "32. Assumptions & Client Clarifications Required",
        "33. Recommendations & Conjur Vault Roadmap",
        "34. Technical Glossary (25+ Terms)",
        "35. Technical Appendices (Appendices A through K)"
    ]
    for item in toc_items:
        add_b(doc, item)

    # =========================================================================
    # 4. LIST OF FIGURES
    # =========================================================================
    add_h(doc, "4. List of Figures", level=1)
    add_p(doc, "All 18 high-resolution architectural diagrams generated at 300 DPI are indexed below with their respective deliverable placement:")
    
    fig_headers = ["Figure #", "Diagram Title", "Target File Asset", "Section Reference"]
    fig_data = [
        ["Figure 1", "System Context & Integration Architecture", "fig01_system_context.png", "Section 9.1"],
        ["Figure 2", "High-Level Architecture & Layered Model", "fig02_high_level_architecture.png", "Section 9.2"],
        ["Figure 3", "Seven-Process-File Flowchart & Chaining", "fig03_seven_process_flow.png", "Section 10.1"],
        ["Figure 4", "End-to-End Upgrade Execution Flow", "fig04_end_to_end_workflow.png", "Section 12.1"],
        ["Figure 5", "Multi-Hop Upgrade Model & Settle Gates", "fig05_multihop_upgrade_flow.png", "Section 13.1"],
        ["Figure 6", "Three-Tier Auto-Remediation Decision Logic", "fig06_auto_remediation_flow.png", "Section 15.1"],
        ["Figure 7", "Authentication & Session Lifecycle Sequence", "fig07_auth_session_sequence.png", "Section 21.1"],
        ["Figure 8", "Baseline Snapshot Data Flow & Postval Diff", "fig08_baseline_snapshot_dataflow.png", "Section 17.1"],
        ["Figure 9", "Live Monitoring Loop & Telemetry Engine", "fig09_monitoring_loop.png", "Section 16.1"],
        ["Figure 10", "Role Interaction & Categorization", "fig10_role_interaction.png", "Section 11.1"],
        ["Figure 11", "RHEL 8 Jump Server Deployment & Network", "fig11_deployment_diagram.png", "Section 22.1"],
        ["Figure 12", "Security Trust Boundaries & Protection", "fig12_security_trust_boundaries.png", "Section 21.2"],
        ["Figure 13", "Recommended Validation Pipeline", "fig13_validation_pipeline.png", "Section 28.1"],
        ["Figure 14", "Reporting Architecture & Notifications", "fig14_reporting_notification_flow.png", "Section 24.1"],
        ["Figure 15", "Storage, Persistence & Concurrency Model", "fig15_storage_concurrency.png", "Section 25.1"],
        ["Figure 16", "Three-Way Health, Remediation & Postval Venn", "fig16_venn_diagram.png", "Section 14.1"],
        ["Figure 17", "Production Readiness Assessment Scorecard", "fig17_production_readiness_summary.png", "Section 29.1"],
        ["Figure 18", "Complete Module Wirings & Fact Flow", "fig18_module_wiring_fact_flow.png", "Section 19.1"]
    ]
    add_tbl(doc, fig_headers, fig_data, col_widths=[0.9, 2.7, 1.9, 1.0])

    # =========================================================================
    # 5. LIST OF TABLES
    # =========================================================================
    add_h(doc, "5. List of Structured Technical Tables", level=1)
    tab_headers = ["Table #", "Table Description", "Primary Subject Domain"]
    tab_data = [
        ["Table 1", "Technology Stack & Runtime Tooling Specifications", "System Architecture (Sec 9)"],
        ["Table 2", "Seven-File Process Surface & Playbook Chaining Contract", "Process Architecture (Sec 10)"],
        ["Table 3", "24 Modular Roles Catalog (Inputs, Outputs, Gates)", "Role Architecture (Sec 11)"],
        ["Table 4", "14-Check Prevalidation Health Contract", "Prevalidation Framework (Sec 14)"],
        ["Table 5", "Three-Tier Auto-Remediation Capability Matrix", "Auto-Remediation (Sec 15)"],
        ["Table 6", "10-Check Postvalidation Health Contract", "Postvalidation Framework (Sec 17)"],
        ["Table 7", "Complete Caller-Callee Playbook-to-Role Binding Hierarchy", "Module Wirings (Sec 19)"],
        ["Table 8", "Inbound & Outbound Data Fact Registry (30+ Facts)", "Module Wirings (Sec 19)"],
        ["Table 9", "Global Variables Catalog (vars/upgrade.yml)", "Variables Reference (Sec 20)"],
        ["Table 10", "CLI Flag Matrix & Operational Exit Code Contract", "Operational Runbook (Sec 23)"],
        ["Table 11", "Pre-Merge Master Verification Checklist (11 Criteria)", "Verification Standards (Sec 28)"],
        ["Table 12", "Comprehensive Risk & Mitigation Matrix (15 Enterprise Risks)", "Risk Management (Sec 31)"]
    ]
    add_tbl(doc, tab_headers, tab_data, col_widths=[0.9, 3.4, 2.2])

    # =========================================================================
    # 6. EXECUTIVE SUMMARY
    # =========================================================================
    add_h(doc, "6. Executive Summary", level=1)
    add_p(doc, "The Azure Red Hat OpenShift (ARO) Cluster Upgrade Automation suite is an enterprise-grade, deterministic, rule-based software solution engineered to eliminate manual toil, operational human error, and extended maintenance windows during minor (Y-stream) OpenShift cluster upgrades.")
    
    add_p(doc, "Upgrading enterprise OpenShift clusters across sequential minor releases (e.g. 4.18 -> 4.19 -> 4.20) has historically required multi-hour, highly manual engineering procedures: executing repetitive pre-checks, manually patching compatibility blockers (such as cgroup v2 migrations or dynamic administrator acknowledgements), continuously monitoring node reboots and MachineConfigPool rollouts, manually calculating structural diffs, and painstakingly verifying Operator Lifecycle Manager (OLM) subscriptions.", bold_prefix="The Operational Challenge: ")

    add_p(doc, "This automation suite realizes true One-Touch Automation: a single CLI command (./00_Run.sh) drives the complete upgrade lifecycle end-to-end. The system performs pre-flight jump host validation, presents interactive risk-aware menus, establishes a dedicated cluster session, captures an immutable Phase 01 JSON baseline snapshot, enforces a 14-check prevalidation gate, automatically remediates known blockers (cgroupMode v2, admin-acks, paused MCPs), executes sequential minor version hops with live 2-minute polling and settle gates, validates post-upgrade health with baseline structural diffing, upgrades installed OLM operators, and dispatches comprehensive HTML audit reports and email digests.", bold_prefix="The Automated Solution: ")

    add_alert(doc, "ZERO NON-DETERMINISTIC AI IN RUNTIME PATH: In strict compliance with enterprise cloud architecture standards, no artificial intelligence, machine learning, or probabilistic inference exists within the automation execution path. Every decision is a deterministic, rule-based Ansible condition (when:, fail:, or deterministic oc patch) guaranteeing 100% auditable and reproducible outcomes.", "CORE ARCHITECTURAL INVARIANT", "important")

    add_p(doc, "Key business and operational benefits delivered by the solution include:", bold_prefix="Core Value Proposition: ")
    add_b(doc, "Reduces average multi-hop upgrade operational oversight from 6–8 hours of manual monitoring to under 15 minutes of operator engagement (menu launch and confirmation).", bold_prefix="75%+ Reduction in Operational Labor: ")
    add_b(doc, "Eliminates upgrade halts caused by well-understood blockers through automated cgroup v2 patching, dynamic admin-acks, and MachineConfigPool unpausing.", bold_prefix="Automated Blocker Remediation: ")
    add_b(doc, "Guarantees zero skipping of OpenShift minor releases; every hop is validated live against the cluster version graph before triggering mutations.", bold_prefix="Sequential Y-Stream Compliance: ")
    add_b(doc, "Single unified codebase executing identically and unchanged on Ansible 2.7.17 (test jump hosts) and Ansible 2.14.18 (production environments).", bold_prefix="Dual-Version Runtime Compatibility: ")
    add_b(doc, "Single login in Phase 01, dedicated kubeconfig isolation, no plaintext secrets, and guaranteed token revocation on any exit path via block/rescue/always.", bold_prefix="Enterprise Security & Fail-Safe Teardown: ")

    # =========================================================================
    # 7. PRODUCT OVERVIEW
    # =========================================================================
    add_h(doc, "7. Product Overview & Strategic Boundaries", level=1)
    
    add_h(doc, "7.1 Product Purpose & Target Audience", level=2)
    add_p(doc, "The product is designed specifically for Cloud Platform Engineers, Enterprise Kubernetes Administrators, and Managed Service Providers responsible for maintaining fleet health across enterprise ARO clusters in Microsoft Azure. It bridges the gap between manual CLI interventions and complex, un-audited ad-hoc shell scripts by providing a structured, enterprise-ready orchestration framework.")

    add_h(doc, "7.2 Business & Technical Objectives", level=2)
    add_b(doc, "Provide a reliable, predictable upgrade mechanism that enforces strict pre-conditions before mutating cluster state.")
    add_b(doc, "Standardize reporting across all enterprise clusters using visually polished, accessible HTML reports and direct SMTP notifications.")
    add_b(doc, "Protect platform integrity by enforcing hard stops on unrecoverable conditions (e.g. etcd quorum loss, API unavailability, Gateway API CRD deadlocks).")
    add_b(doc, "Ensure full auditability by recording dual .txt and .csv run logs with millisecond timestamps and phase-level tracking.")

    add_h(doc, "7.3 Scope Definition", level=2)
    add_p(doc, "The scope boundaries are explicitly defined as follows:")
    add_b(doc, "In-Scope: One-touch sequential Y-stream upgrades; pre-flight environment checks; interactive CLI menus; PID concurrency locking; 14-check prevalidation; 3-tier auto-remediation; live 2-min monitoring with 90-min timeout; 10-check postvalidation with baseline diff; OLM operator scanning, approval, and validation; direct SMTP email dispatch; dual-format logging.", bold_prefix="In-Scope: ")
    add_b(doc, "Out-of-Scope: Non-deterministic AI decision logic; automated cloud infrastructure provisioning (VMs, subnets, ExpressRoute); Z-stream (patch) skipping; automated major version (X-stream) jumps; automated usage of '--to-image ... --force' (strictly manual); GitOps ArgoCD repo synchronization; direct etcd database backup restore.", bold_prefix="Out-of-Scope: ")

    add_h(doc, "7.4 Technical Constraints & Assumptions", level=2)
    add_b(doc, "Host Platform: Execution occurs strictly from a RHEL 8 enterprise jump server with bash >= 4.2.")
    add_b(doc, "Cluster Connectivity: Direct HTTPS (port 6443) network connectivity from the jump server to the ARO API endpoint.")
    add_b(doc, "Tooling: Availability of oc CLI (OpenShift client >= 4.14), jq v1.5, and Python with smtplib.")
    add_b(doc, "SMTP Relay: Network egress to a corporate SMTP relay (port 25) without requiring a local jump host MTA daemon.")

    # =========================================================================
    # 8. FUNCTIONAL CAPABILITIES
    # =========================================================================
    add_h(doc, "8. Functional Capabilities & Operational Features", level=1)
    add_p(doc, "The automation suite provides a robust, operator-centric suite of capabilities engineered across the entire upgrade lifecycle:")

    add_h(doc, "8.1 One-Touch CLI & Terminal Experience (00_Run.sh)", level=2)
    add_p(doc, "The operational entrypoint delivers a modern, resilient CLI interface built with pure bash and Python validation:")
    add_b(doc, "Validates bash version, ansible-playbook, oc, jq, and python binaries before initiating execution.", bold_prefix="Pre-flight Dependency Checks: ")
    add_b(doc, "Uses embedded Python (yaml.safe_load) to validate all 6 configuration files for syntax and schema correctness, eliminating fragile shell parsing.", bold_prefix="Vars Schema Validation: ")
    add_b(doc, "Dynamically parses vars/secrets.yml to present an interactive, numbered selection box for target clusters.", bold_prefix="Interactive Cluster Menu: ")
    add_b(doc, "Presents global, per-cluster, or custom upgrade paths with default selection highlighting and ASCII journey arrows.", bold_prefix="Interactive Upgrade Path Menu: ")
    add_b(doc, "Enables selecting Full Upgrade (Phases 01-06), Dry Run (01-02, zero mutations), Pre-check Only (01-02 with auto-fix), or Post-check Only (05).", bold_prefix="Run Mode Selector: ")
    add_b(doc, "Evaluates cluster tier (DEV/STAGE/PROD); requires typing 'UPGRADE' in capital letters for production targets.", bold_prefix="Risk-Aware Confirmation Gate: ")
    add_b(doc, "Creates /tmp/aro-upgrade-<cluster>.lock with active PID verification, stale lock cleanup, and signal trap removal (EXIT INT TERM).", bold_prefix="PID Concurrency Run Lock: ")
    add_b(doc, "Tees live terminal output to logs/<cluster>_<ts>.txt and displays an aligned 72-column tabular post-run execution summary.", bold_prefix="Tee'd Logging & Summary: ")

    add_h(doc, "8.2 Prevalidation & Automated Blocker Remediation", level=2)
    add_p(doc, "Phase 02 executes 14 comprehensive health checks (8 HARD gates, 6 WARN advisories) and integrates a deterministic auto-remediation engine:")
    add_b(doc, "API Context, API Readiness (/readyz), ClusterOperators (0 degraded), MachineConfigPools (0 degraded), Node Readiness (100% Ready), etcd Quorum (>=3 pods), Dynamic Admin-Acks, Node Resource Utilization (CPU/Mem <90%), Pending CSRs, PV Status, PVC Status, PodDisruptionBudgets, Core Namespace Pods, CGroup Mode Compatibility.", bold_prefix="14 Health Checks: ")
    add_b(doc, "If target >= 4.19 and nodes run cgroup v1, automatically applies JSON merge patch to nodes.config/cluster setting spec.cgroupMode: 'v2'.", bold_prefix="CGroup v2 Migration: ")
    add_b(doc, "Parses Upgradeable=False conditions from ClusterVersion, extracts pending acknowledgement keys, and patches openshift-config/admin-acks.", bold_prefix="Dynamic Admin-Acks: ")
    add_b(doc, "Detects paused MachineConfigPools and resets spec.paused: false for permitted pools in mcp_auto_unpause_list.", bold_prefix="MCP Auto-Unpause: ")

    add_h(doc, "8.3 Multi-Hop Upgrade Driver & Live Monitoring", level=2)
    add_p(doc, "Phases 03 and 04 drive sequential minor-version upgrades with continuous telemetry:")
    add_b(doc, "Loops tasks/hop.yml over upgrade_path using Ansible 2.7-compatible include_tasks; sets channel, verifies edge, and triggers oc adm upgrade.", bold_prefix="Sequential Hop Iteration: ")
    add_b(doc, "Polls ClusterVersion, MCPs, and nodes every 2 minutes using jq 1.5 queries; calculates progress percentage across pools.", bold_prefix="Bounded 2-Minute Polling: ")
    add_b(doc, "Dispatches HTML progress emails every 20 minutes and triggers immediate alert emails on node degradation or MCP stalls.", bold_prefix="Heartbeats & Alerts: ")
    add_b(doc, "Asserts CV at target version with Progressing=False, all ClusterOperators Available=True / Degraded=False, and all MCPs Updated=True.", bold_prefix="Settle-Gate Verification: ")

    add_h(doc, "8.4 Postvalidation, Operator Upgrades & Audit Closeout", level=2)
    add_p(doc, "Phases 05 and 06 ensure post-upgrade stability, operator currency, and deliver audit artifacts:")
    add_b(doc, "Executes 10 post-upgrade health checks and performs a structural diff against the Phase 01 baseline snapshot, auditing node counts, operators, and routes.", bold_prefix="Postval Baseline Diff: ")
    add_b(doc, "Scans installed OLM subscriptions, determines target channel compatibility, sequentially approves manual InstallPlans, and tracks CSV rollouts.", bold_prefix="Operator Lifecycle: ")
    add_b(doc, "Deletes failed CSV pods once during Phase 06 to trigger clean OLM subscription reconciliation before reporting failure.", bold_prefix="Tier 2 CSV Recovery: ")
    add_b(doc, "Dispatches final email with 4 attached reports (Preval HTML, Postval HTML, Operator HTML, and text run log) and executes terminal logout.", bold_prefix="Audit Digest & Logout: ")

    # =========================================================================
    # 9. SOLUTION ARCHITECTURE
    # =========================================================================
    add_h(doc, "9. Solution Architecture & Layered System Model", level=1)
    add_p(doc, "The ARO Cluster Upgrade Automation suite is architected as an 8-layer decoupled system, enforcing strict separation between operational invocation, workflow orchestration, task execution, configuration data, presentation templates, and audit storage.")

    add_fig(doc, "fig01_system_context.png", 1, "System Context & Integration Architecture",
            "Illustrating operational perimeters, jump host execution boundaries, ARO API touchpoints, SMTP routing, and future Conjur Vault integration.")

    add_h(doc, "9.1 Technology Stack Specifications", level=2)
    add_p(doc, "The following validated technologies comprise the automation runtime environment:")
    
    tech_headers = ["Layer / Component", "Technology & Version", "Role & Architectural Constraints"]
    tech_data = [
        ["Execution Host", "RHEL 8 Jump Server", "Enterprise Linux host platform hosting CLI, playbooks, and runtime tools."],
        ["Orchestration Engine", "Ansible 2.7.17 & 2.14.18", "Dual-version compatibility; short module names; inline # MIGRATION 2.14: notes."],
        ["CLI Entrypoint", "Bash (>= 4.2) + Python 3", "00_Run.sh & cli_helpers.sh; pre-flight checks, 72-col UI, PID locks."],
        ["Cluster Interface", "OpenShift Client (oc >= 4.14)", "Cluster reads, patches, upgrade triggers; resilient retry wrappers (3 retries / 10s delay)."],
        ["JSON Processor", "jq v1.5", "Parses oc JSON output; strict jq 1.5 syntax compliance (def rnd2: custom rounding)."],
        ["Notification Delivery", "Ansible mail / smtplib", "Direct SMTP delivery to port 25 without requiring local jump host postfix service."],
        ["Reporting Engine", "Jinja2 Templates (.j2)", "Renders standalone HTML reports and email bodies; presentation-only logic."],
        ["Secrets Engine", "Variable References -> Conjur", "vars/secrets.yml references; planned swap to CyberArk Conjur Vault."]
    ]
    add_tbl(doc, tech_headers, tech_data, col_widths=[1.5, 2.0, 3.0])

    add_fig(doc, "fig02_high_level_architecture.png", 2, "High-Level Architecture & Layered Model",
            "The 6-layer decoupled architecture: CLI UX, Master Orchestrator, Phase Playbooks, 24 Roles, Variables/Templates, and Write-Only Audit Boundaries.")

    add_h(doc, "9.2 Core Architecture Principles", level=2)
    add_b(doc, "All cluster state evaluations are driven by explicit when: conditions and fail: gates. Zero non-deterministic heuristic models exist.", bold_prefix="1. Determinism Over Heuristics: ")
    add_b(doc, "Cluster queries are strictly read-only; the only mutating commands permitted on the cluster are 'oc patch' (remediation/InstallPlans) and 'oc adm upgrade'.", bold_prefix="2. Read-Only Safety: ")
    add_b(doc, "Authentication writes exclusively to a dedicated kubeconfig derived from playbook_dir (.kubeconfig-<cluster>), never touching default ~/.kube/config.", bold_prefix="3. Session Isolation: ")
    add_b(doc, "All execution paths across all phases are enclosed in block/rescue/always, guaranteeing session teardown under all exit conditions.", bold_prefix="4. Fail-Safe Teardown: ")

    # =========================================================================
    # 10. SEVEN-FILE PROCESS ARCHITECTURE
    # =========================================================================
    add_h(doc, "10. Seven-File Process Architecture", level=1)
    add_p(doc, "The entire upgrade lifecycle is driven by exactly seven primary process files located directly under playbooks/. All heavy lifting lives in supporting roles and templates, ensuring the main orchestration surface remains clean, linear, and maintainable.")

    add_fig(doc, "fig03_seven_process_flow.png", 3, "Seven-Process-File Flowchart & Chaining Hierarchy",
            "Linear phase execution from 00_Run.sh through main.yml and Phases 01-06, illustrating per-hop iteration and dry-run early teardown.")

    add_h(doc, "10.1 Detailed Process File Responsibilities", level=2)
    
    proc_headers = ["File Name", "Phase / Stage", "Chaining Mechanism", "Core Responsibilities"]
    proc_data = [
        ["00_Run.sh", "Entrypoint CLI", "Bash script (executes ansible-playbook)", "Pre-flight checks, vars validation, menus, PID lock, extra-vars JSON assembly, post-run summary."],
        ["main.yml", "Master Orchestrator", "import_playbook + intercept plays", "Chains Phases 01-06, enforces skip_to_phase and stop_after_phase bounds, dry-run teardown."],
        ["01_Policy_Check.yaml", "Phase 01", "import_playbook", "Establishes session (login), captures baseline JSON snapshot, validates target version edge."],
        ["02_Pre_upgrade_check.yaml", "Phase 02", "import_playbook", "Runs 14 prevalidation checks, invokes remediate role, re-evaluates gates, renders HTML report."],
        ["03_Initiate_upgrade.yaml", "Phase 03", "import_playbook (loops tasks/hop.yml)", "Driver looping tasks/hop.yml over upgrade_path; sets channel, edge check, triggers upgrade."],
        ["04_Live_monitoring_upgrade.yaml", "Phase 04", "include_tasks (from tasks/hop.yml)", "Inline 2-min polling, 90-min timeout guard, 20-min heartbeats, state-change alerts, settle gate."],
        ["05_post_Upgrade_Checks.yaml", "Phase 05", "import_playbook", "Executes 10 postval checks, slurps Phase 01 snapshot, computes structural diff, generates report."],
        ["06_Operator_Upgrade.yaml", "Phase 06", "import_playbook", "Scans OLM operator compatibility, approves InstallPlans, settles CSVs, sends digest email, logs out."]
    ]
    add_tbl(doc, proc_headers, proc_data, col_widths=[1.6, 1.1, 1.3, 2.5])

    add_h(doc, "10.2 Lifecycle Execution Boundaries (skip_to_phase & stop_after_phase)", level=2)
    add_p(doc, "To provide maximum operational flexibility and recovery capabilities without compromising phase isolation, main.yml implements bidirectional lifecycle boundaries:")
    add_b(doc, "Permits operators to bypass completed phases during recovery (e.g. --skip-to-phase 05 skips Phases 01-04 and executes postvalidation diffing directly).", bold_prefix="skip_to_phase (Start Bound): ")
    add_b(doc, "Guarantees that non-mutating validation sweeps (such as --pre-check or --post-check) halt cleanly immediately after their respective validation phases, executing clean session logout via roles/logout and preventing downstream mutation cascades.", bold_prefix="stop_after_phase (Stop Bound): ")

    return doc

print("sections_part1 module loaded successfully.")
