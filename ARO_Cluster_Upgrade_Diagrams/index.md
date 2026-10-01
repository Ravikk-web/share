# ARO Cluster Upgrade Automation — Architectural Diagrams Catalog

This catalog indexes the complete set of 18 high-resolution architectural diagrams generated for the ARO Cluster Upgrade Automation production documentation and client presentation deliverables.

All diagrams are generated at **300 DPI**, adhering strictly to the enterprise design tokens defined in `context/ui-context.md` (Deep Navy `#0F2744`, Royal Blue `#1D4ED8`, Emerald Green `#1A7F37`, Amber `#B45309`, Crimson `#B42318`, and Slate `#334155`).

---

## Diagram Index

| Figure | Filename | Title | Architectural Scope & Significance | Deliverable Usage |
| :---: | :--- | :--- | :--- | :--- |
| **Figure 1** | `fig01_system_context.png` | **System Context & Integration Architecture** | Illustrates the platform operations team, RHEL 8 jump host, ARO Cluster API (port 6443), Corporate SMTP Gateway (port 25), and future CyberArk Conjur integration boundaries. | Word Doc (Sec 9), PPT (Slide 7) |
| **Figure 2** | `fig02_high_level_architecture.png` | **High-Level Architecture & Layered Model** | 6-layer system model: CLI/UX, Master Orchestrator, Phase Playbooks, 24 Modular Roles, Variables/Templates, Tooling & Write-Only Audit Boundaries. | Word Doc (Sec 9), PPT (Slide 8) |
| **Figure 3** | `fig03_seven_process_flow.png` | **Seven-Process-File Flowchart & Chaining Hierarchy** | Linear phase progression (`00_Run.sh` → `main.yml` → `01` through `06`), per-hop iteration of `tasks/hop.yml`, and post-Phase 02 dry-run early teardown. | Word Doc (Sec 10), PPT (Slide 9) |
| **Figure 4** | `fig04_end_to_end_workflow.png` | **End-to-End Upgrade Execution Flow** | Comprehensive 19-step chronological lifecycle from pre-flight checks, PID locking, and login to settle gates, operator rollouts, and terminal session teardown. | Word Doc (Sec 12), PPT (Slide 10) |
| **Figure 5** | `fig05_multihop_upgrade_flow.png` | **Multi-Hop Upgrade Model & Sequential Settle Gates** | Sequential Y-stream upgrade compliance without skipping minor releases (e.g. `4.18.09 → 4.19.15 → 4.20.08`) with live edge validation and settle gates. | Word Doc (Sec 13), PPT (Slide 11) |
| **Figure 6** | `fig06_auto_remediation_flow.png` | **Three-Tier Auto-Remediation Decision Logic** | Decision tree for Tier 1 Auto-Fix (cgroup v2, admin-acks, MCP unpause), Tier 2 Guided Recovery (CO restart, MCD force, CSV retry), and Tier 3 Hard Stops. | Word Doc (Sec 15), PPT (Slide 13) |
| **Figure 7** | `fig07_auth_session_sequence.png` | **Authentication & Session Lifecycle Sequence** | Sequence diagram demonstrating single `oc login` in Phase 01, dedicated kubeconfig derivation (`.kubeconfig-<cluster>`), phase reuse, and fail-safe teardown. | Word Doc (Sec 21), PPT (Slide 18) |
| **Figure 8** | `fig08_baseline_snapshot_dataflow.png` | **Baseline Snapshot Data Flow & Postvalidation Diff** | Single cross-phase state persistence model: Phase 01 capture (`snapshots/<cluster>_<ts>_baseline.json`) to Phase 05 structural diff auditing. | Word Doc (Sec 17), PPT (Slide 15) |
| **Figure 9** | `fig09_monitoring_loop.png` | **Live Monitoring Loop & Telemetry Engine** | Bounded 2-minute polling loop with 20-minute HTML progress heartbeats, immediate state-change alerts with RBAC remediation, and 90-minute timeout guard. | Word Doc (Sec 16), PPT (Slide 14) |
| **Figure 10** | `fig10_role_interaction.png` | **Role Interaction & Architectural Categorization** | Maps all 24 single-purpose roles across their 8 architectural domains and documents data contracts between playbooks and roles. | Word Doc (Sec 11), PPT (Slide 17) |
| **Figure 11** | `fig11_deployment_diagram.png` | **RHEL 8 Jump Server Deployment & Network Architecture** | Execution platform prerequisites (Ansible 2.7/2.14, oc, jq 1.5, Python 3), isolated file boundaries, and egress network flows (HTTPS 6443, SMTP 25). | Word Doc (Sec 22), PPT (Slide 20) |
| **Figure 12** | `fig12_security_trust_boundaries.png` | **Security Trust Boundaries & Data Protection** | 4 trust zones: Secrets repository (zero plaintext), Runtime execution (`no_log: true`), Cluster session (dedicated kubeconfig), and Output audit sanitization. | Word Doc (Sec 21), PPT (Slide 18) |
| **Figure 13** | `fig13_validation_pipeline.png` | **Recommended CI/CD & Automated Verification Pipeline** | 5-stage automated quality pipeline: Static analysis, Dual-version compatibility linting, jq 1.5 compliance, Jinja2 type audit, and dry-run integration testing. | Word Doc (Sec 28), PPT (Slide 21) |
| **Figure 14** | `fig14_reporting_notification_flow.png` | **Reporting Architecture & Notification Engine** | Flow from in-memory health facts to `report` and `sendmail` roles, rendering `health-overview.j2`, `progress-mail.j2`, `error-report.j2`, and 4 digest attachments. | Word Doc (Sec 24), PPT (Slide 14) |
| **Figure 15** | `fig15_storage_concurrency.png` | **Storage Architecture, Persistence & Concurrency Model** | Tripartite storage model: PID lock file (`/tmp/aro-upgrade-<cluster>.lock`), ephemeral facts (memory), baseline JSON (disk), and write-only audit outputs. | Word Doc (Sec 25), PPT (Slide 19) |
| **Figure 16** | `fig16_venn_diagram.png` | **Three-Way Health, Remediation & Postval Overlap** | Mathematical Venn diagram demonstrating intersections between 14 Preval checks, 8 Auto-Remediation blockers, and 10 Postval checks. | Word Doc (Sec 14), PPT (Slide 12) |
| **Figure 17** | `fig17_production_readiness_summary.png` | **Production Readiness Assessment & Quality Scorecard** | Visual scorecard across 10 production dimensions classifying controls as `VERIFIED`, `PARTIALLY VERIFIED`, `GAP IDENTIFIED`, or `RECOMMENDATION`. | Word Doc (Sec 29), PPT (Slide 21) |
| **Figure 18** | `fig18_module_wiring_fact_flow.png` | **Complete Module Wirings, Caller-Callee Bindings & Fact Flow** | Exhaustive architectural schematic showing exact caller-callee hierarchies, fact exports/imports, task inclusions, and presentation consumers. | Word Doc (Sec 19), PPT (Slide 17) |

---

## Directory Contents

All diagram image assets are stored directly in this directory (`ARO_Cluster_Upgrade_Diagrams/`):
- `fig01_system_context.png`
- `fig02_high_level_architecture.png`
- `fig03_seven_process_flow.png`
- `fig04_end_to_end_workflow.png`
- `fig05_multihop_upgrade_flow.png`
- `fig06_auto_remediation_flow.png`
- `fig07_auth_session_sequence.png`
- `fig08_baseline_snapshot_dataflow.png`
- `fig09_monitoring_loop.png`
- `fig10_role_interaction.png`
- `fig11_deployment_diagram.png`
- `fig12_security_trust_boundaries.png`
- `fig13_validation_pipeline.png`
- `fig14_reporting_notification_flow.png`
- `fig15_storage_concurrency.png`
- `fig16_venn_diagram.png`
- `fig17_production_readiness_summary.png`
- `fig18_module_wiring_fact_flow.png`
