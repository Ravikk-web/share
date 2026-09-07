# ARO Cluster Upgrade Automation

Deterministic, rule-based, one-touch Ansible automation suite for **sequential Y-stream (minor) upgrades of Azure Red Hat OpenShift (ARO) clusters**, featuring an integrated **auto-remediation engine** for known upgrade blockers and automated **OLM operator upgrades**.

Single codebase engineered to run unmodified on **Ansible 2.7.17 (test jump hosts)** and **Ansible 2.14.18 (production)** using native modules, `oc`, `jq` (v1.5), and shell.

---

## Current Status

- **Current Phase**: Phase 1 — Project Scaffolding & Initial Components
- **Current Goal**: Antigravity Word & PPT Documentation Generation Prompt (`Documentation_Prompt.md`)

### What's Built
- [x] **Context Foundation**: Project overview, architecture specification, UI design tokens, code standards, AI workflow rules, and progress tracker.
- [x] **Unit 01: Project Scaffold & Variable Inputs**:
  - `playbooks/` execution directory structure with write-only directory anchors (`logs/`, `output/`, `snapshots/`).
  - 6 variable files in `playbooks/vars/` with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`):
    - `upgrade.yml`: Global cluster targets, sequential upgrade path, capacity thresholds, monitoring cadences, and auto-remediation toggles.
    - `secrets.yml`: Conjur Vault-ready credential variable references (`{{ vault_* }}`) with zero plaintext secrets and cluster metadata map.
    - `smtp.yml`: Direct SMTP configuration, recipient lists, and email subject prefixes.
    - `paths.yml`: Centralized runtime paths dynamically derived from `playbook_dir`.
    - `report_vars.yml`: UI color tokens, background tints, and badge constants matching `context/ui-context.md`.
    - `api_regex.yml`: Regex patterns for validating cluster API URLs, version numbers, and cluster names.
  - `playbooks/scripts/cli_helpers.sh`: ANSI colors, UTF-8 box characters, and logging functions.
- [x] **Unit 02: CLI Entrypoint & Orchestrator Skeleton**:
  - `playbooks/scripts/cli_helpers.sh`: Complete terminal UI engine with UTF-8 box primitives, visible width ANSI stripping, message formatters, visual journey diagrams, risk assessment, interactive menu selector, and post-run summary tables.
  - `playbooks/00_Run.sh`: One-touch CLI entrypoint with traps, pre-flight dependency checking, Python-based vars schema validation, concurrency run locks (`/tmp/aro-upgrade-<cluster>.lock`), visual journey confirmation, production safety gate, single JSON string extra-vars formatting, tee'd logging, and structured exit codes (0, 1, 2, 3, 10, 20, 30, 99).
  - `playbooks/main.yml`: Master orchestrator skeleton with dual-version headers, anchored vars imports, mandatory input assertions, dispatch debug banner, and Phase 01 through Phase 06 execution placeholders.
- [x] **Unit 03: Session Lifecycle Roles (`login`, `logout`)**:
  - `playbooks/roles/login/`: Dedicated cluster-scoped session authentication (`oc login` with `no_log: true`), dynamic OpenShift CLI binary discovery (`/usr/local/bin/oc` or PATH), multi-format credential resolution (`cluster_*`, `cluster.*`, `clusters[...]`), shell invocation with bash and strict parameter quoting, default TLS verification bypass (`--insecure-skip-tls-verify=true`), server identity validation (`oc whoami --show-server`), regex matching against `desired_cluster_api_regex` (`^https://api\.[a-zA-Z0-9.-]+:6443/?$`), and KUBECONFIG fact export.
  - `playbooks/roles/logout/`: Guaranteed fail-safe session teardown (`{{ oc_binary | default('oc') }} logout` with `failed_when: false`), temporary `.kubeconfig-<cluster>` removal, fact clearing, and clean debug confirmation.
- [x] **Unit 04: Email Notification System & Templates (`sendmail`, Jinja2 templates)**:
  - `playbooks/roles/sendmail/`: Native Ansible `mail` module direct SMTP dispatch on localhost, flexible template path resolution, parameter validation (`mail_html_body` and `mail_to`), attachment handling, and mandatory post-dispatch fact cleanup (`mail_html_body`, `mail_final_body`, `mail_attachments`, `mail_template`, `resolved_template_path`) preventing cross-hop caching.
  - `playbooks/templates/error-report.j2`: Failure alert email card (`≤ 580px`) featuring `UPGRADE HALTED ✖` header verdict, conditional RBAC warning callout with missing verbs/resources and actionable remediation commands (`oc adm policy add-cluster-role-to-user ...`), diagnostic failure matrix, error trace container, and safe teardown confirmation.
  - `playbooks/templates/progress-mail.j2`: Upgrade progress and heartbeat email card (`≤ 580px`) with Hop counter, progress bar and percentage, elapsed time, MachineConfigPool table (always visible with machine counts and status pills), active updating node list (healthy nodes suppressed), degraded node alerts, and `HOP COMPLETE ✔` settle-gate state with attachment notices.
  - `playbooks/templates/health-overview.j2`: Multi-purpose HTML audit report (`max-width: 1080px`) for Prevalidation, Postvalidation, and Operator Validation. Renders header band with overall verdict pill, 5-tile summary metrics (total, passed, warnings, auto-fixed, failed), structured status table supporting `PASS ✔`, `WARN !`, `FAIL ✖`, `AUTO-FIXED ⚙` (blue `#1d4ed8`), and `FIX-FAILED ⚠` (orange `#c2410c`) status pills, conditional auto-remediation callouts with Red Hat documentation links, OLM operator compatibility table, collapsible `<details>` deep diagnostics with `@media print` expansion, and interactive copy-to-clipboard action.
- [x] **Unit 05: Reporting & Error Handling Foundation (`error_handle`, `report` roles)**:
  - `playbooks/roles/error_handle/`: Standardized rescue block handler with hierarchical error extraction (`stderr` -> `stderr_lines` -> `msg` -> fallback) without referencing internal task objects, automated RBAC permission denial detection (`forbidden`, `cannot patch`, `unauthorized`), structured failure recording into `failed_checks` and `health_summary`, dual audit logging to human-readable `.txt` and machine-parseable `.csv` (with automatic header initialization), and failure alert email dispatch via `sendmail` with `error-report.j2`.
  - `playbooks/roles/report/`: Client-facing HTML audit report generator. Consolidates check facts from `checks` or `health_summary`, derives 5-tile summary metrics (total, passed, warnings, auto-fixed, failed) with support for health checks and OLM operator matrices, determines overall verdict badge (`FAIL` > `AUTO-FIXED` > `WARN` > `PASS`), auto-populates `autofix_items`, renders `health-overview.j2`, writes standalone HTML artifacts to `output/{{ cluster_name }}_{{ report_type }}_{{ run_timestamp }}.html` via `copy:` with `content:`, and exports `report_file_path` for notification attachments.
- [x] **Unit 06: Snapshot Role & Phase 01 Playbook (`01_Policy_Check.yaml`, `snapshot` role)**:
  - `playbooks/roles/snapshot/`: Baseline cluster state capture role. Resilient `oc` queries (`retries: 3 / delay: 10`) with jq v1.5 parsing for `clusterversion`, `clusteroperators`, `nodes`, and `routes`. Formats structured `baseline_dict`, writes immutable JSON artifact (`snapshots/<cluster>_<ts>_baseline.json`), and exports `baseline_snapshot_file_path` for Phase 05 diffing.
  - `playbooks/01_Policy_Check.yaml`: Phase 01 playbook. Connects to localhost, ingests all 6 `vars/` files, authenticates via `login` role, invokes `snapshot` role, queries live `availableUpdates` and `conditionalUpdates` from `ClusterVersion`, validates that `upgrade_path[0]` is a confirmed edge, enforces HARD gate (`fail:`), logs to `.txt` and `.csv` (with automatic header check), and manages fail-safe session lifecycle (`rescue`/`always`).
- [x] **Unit 07: Health Check Roles (`api_check`, `api_readiness`, `co`, `mcp`, `node`, `etcd`)**:
  - `playbooks/roles/api_check/`: API context verification role. Queries active server URL via `oc whoami --show-server` with retry loops (`retries: 3 / delay: 10`), validates pattern against `desired_cluster_api_regex`, records structured record to `health_summary`, and enforces HARD gate (`fail:`).
  - `playbooks/roles/api_readiness/`: API endpoint health verification role. Queries `/readyz` raw endpoint via `oc get --raw=/readyz` with retries, validates payload equals `ok`, records to `health_summary`, and enforces HARD gate (`fail:`).
  - `playbooks/roles/co/`: ClusterOperator health evaluation role. Queries `oc get clusteroperators -o json` with jq v1.5 parsing, checks `Available=True` and `Degraded=False`, supports `co_allow_list` exclusions, exports `co_all_operators`, `co_degraded`, `co_unavailable`, and `co_unhealthy_operators`, records to `health_summary`, and enforces HARD gate (`fail:`).
  - `playbooks/roles/mcp/`: MachineConfigPool synchronization role. Queries `oc get mcp -o json` with jq v1.5 parsing, checks `Updated=True`, `Degraded=False`, and `spec.paused=false`, exports `mcp_parsed_data` and `mcp_all_pools`, records to `health_summary`, and enforces HARD gate (`fail:`).
  - `playbooks/roles/node/`: Node health evaluation role. Queries `oc get nodes -o json` with jq v1.5 parsing, validates all nodes `Ready=True`, checks `DiskPressure`, `MemoryPressure`, `PIDPressure`, evaluates unschedulable nodes against `allowed_unschedulable_nodes` threshold, records to `health_summary`, and enforces HARD gate (`fail:`).
  - `playbooks/roles/etcd/`: Control-plane etcd database health verification role. Queries control plane pods via `oc get pods -n openshift-etcd -l app=etcd -o json` to ensure pods are Running/Ready, checks `clusteroperator etcd` for `Available=True` and `Degraded=False`, verifies HA quorum (>= 3 pods), records to `health_summary`, and enforces HARD gate (`fail:`).
- [x] **Unit 08a: Auto-Remediation Engine (`remediate` Role)**:
  - `playbooks/roles/remediate/`: Dedicated, deterministic auto-fix engine. Centralizes automated resolution of known OpenShift upgrade blockers to realize one-touch automation.
  - `tasks/main.yml`: Dispatcher supporting selective invocation via `trigger_*_remediation` or full prevalidation sweeps across enabled modules.
  - `tasks/cgroup_v2.yml` (Tier 1): Detects cgroup v1, applies deterministic merge patch to `nodes.config/cluster` (`spec.cgroupMode: "v2"`), re-verifies via jsonpath, records `AUTO-FIXED`, appends to `autofix_items`, and emits dual `.txt`/`.csv` audit logs.
  - `tasks/admin_acks.yml` (Tier 1): Dynamically extracts required admin-ack keys (`ack-[0-9]+\.[0-9]+-api-removals-in-[0-9]+\.[0-9]+`) from `ClusterVersion` conditions, applies patch to `openshift-config/admin-acks`, re-verifies ConfigMap data, records `AUTO-FIXED`, and emits dual audit logs.
  - `tasks/unpause_mcp.yml` (Tier 1): Detects paused MachineConfigPools, partitions against `mcp_auto_unpause_list` (`worker`, `master`), unpauses permitted pools via JSON patch (`spec.paused: false`), re-verifies pool states, records `AUTO-FIXED`, and emits dual audit logs.
  - `tasks/restart_operator.yml` (Tier 2 Guided): Detects degraded ClusterOperators excluding allow-lists, resolves controller pods across namespaces, forces pod deletion, pauses for `operator_restart_grace_seconds` (180s) reconciliation, re-verifies `Available=True` / `Degraded=False`, records outcome, and emits dual audit logs.
- [x] **Unit 08: Capacity, Storage & Disruption Roles (`utilization`, `pv`, `pvc`, `pdb`)**:
  - `playbooks/roles/utilization/`: Node capacity headroom evaluation role. Calculates aggregate cluster CPU and memory request allocations against allocatable node capacity using jq v1.5 `rnd2` expressions, enforces `max_cpu_percent: 90` and `max_memory_percent: 90` HARD gates to prevent node evacuation deadlock during reboots.
  - `playbooks/roles/pv/`: PersistentVolumes health verification role. Resiliently queries `oc get pv -o json` with jq v1.5 parsing, checks `Bound` or `Available` phase, cleanly handles empty clusters without failing, surfaces `Failed` or `Released` volumes. Configured strictly as a non-blocking `WARN` advisory that never halts the upgrade workflow.
  - `playbooks/roles/pvc/`: PersistentVolumeClaims status verification role. Resiliently queries `oc get pvc -A -o json` with jq v1.5 parsing across all namespaces, verifies `Bound` phase, cleanly handles empty clusters, surfaces `Pending` or `Lost` claims. Configured strictly as a non-blocking `WARN` advisory that never halts the upgrade workflow.
  - `playbooks/roles/pdb/`: PodDisruptionBudgets deadlock audit role. Resiliently queries `oc get pdb -A -o json` with jq v1.5 parsing, audits for zero-disruption budgets (`disruptionsAllowed == 0` and `expectedPods > 0`) that would block node draining during MCP rollouts, ignores scaled-to-zero workloads, surfaces offending budgets with namespace/name, filters system namespaces (`openshift-*`, `kube-*`), and enforces configurable gate (`fail_on_zero_disruption_pdb: false` WARN advisory by default).
- [x] **Prevalidation 14-Check Contract Residual HARD Gate Fix (Checks 06, 12, 14)**:
  - Check 06 (`etcd`): Fixed Jinja2 string-to-boolean type comparison bug (`etcd_co_available == 'True'`) by normalizing conditions with `| string | trim | lower == 'true'` and testing with boolean filters.
  - Check 12 (`pdb`): Reset `fail_on_zero_disruption_pdb: false` default (non-blocking WARN) and added `pdb_ignore_system_namespaces: true` to prevent false positive halts on internal platform logging/monitoring PDBs.
  - Check 14 (`cgroup`): Gated auto-remediation to only execute when target version requires v2 (`>= 4.19`), added `skip_cgroup_check: false` (and `--skip-cgroup` CLI flag) to completely bypass check/patching, defaulted `cgroup_enforce_gate: false` (non-blocking WARN advisory), and handled cluster-scope RBAC patch restrictions gracefully without halting upgrades.
- [x] **Unit 09: Prevalidation Aggregator Role & Phase 02 (`prevalidation` Role, `02_Pre_upgrade_check.yaml`)**:
  - `playbooks/roles/prevalidation/`: Orchestrates the full **14-check prevalidation contract** (8 HARD gates, 6 WARN advisories) without premature abort during initial scanning. Coordinates roles `co`, `node`, `mcp`, `api_check`, `api_readiness`, `etcd`, `utilization`, `pv`, `pvc`, and `pdb`, alongside inline evaluation for admin acknowledgements, pending CSRs, critical namespace pod health, and cgroupMode compatibility.
  - `playbooks/02_Pre_upgrade_check.yaml`: Phase 02 playbook. Reuses authenticated session from Phase 01, executes 14-check prevalidation scan, evaluates initial HARD failures, dynamically invokes `remediate` role for auto-fixable blockers (CGroup v2, Admin-Acks, MCP unpausing, or degraded operator restart), re-evaluates residual HARD gates, generates client-facing HTML prevalidation report via `report` role (`output/<cluster>_prevalidation_<ts>.html`), emits dual `.txt` and `.csv` audit logs, and guarantees fail-safe session teardown on failure.
- [x] **Unit 10: Upgrade Role, Per-Hop Task (`tasks/hop.yml`) & Phase 03 Playbook (`03_Initiate_upgrade.yaml`)**:
  - `playbooks/roles/upgrade/`: Upgrade mutation driver role (`defaults/main.yml`, `tasks/main.yml`). Implements `target_version` assertion, semantic regex parsing for major.minor prefix extraction (`target_major_minor`), dynamic upgrade channel resolution (`resolved_target_channel`), channel updating (`oc adm upgrade channel`), edge re-verification with retries against live `availableUpdates` and `conditionalUpdates`, dynamic administrator acknowledgement check via `admin_acks.yml`, safety guard requiring explicit `CONFIRM_FORCE_UPGRADE` token for `--force` emergency upgrades, and single cluster mutation trigger via `oc adm upgrade --to={{ target_version }}` (with dry-run simulation support).
  - `playbooks/tasks/hop.yml`: The per-hop sequence task driven per item in `upgrade_path`. Implements 7-step sequence: (1) hop metadata computation (`hop_number`, `hop_total`, `hop_label`), (2) hop start banner and dual `.txt`/`.csv` logging, (3) pre-hop settle assertion (verifying cluster is stable, unblocked, not actively updating, and has zero degraded MCPs/COs), (4) `roles/upgrade` execution with pre-computed facts, (5) hand-off to live monitoring (`04_Live_monitoring_upgrade.yaml`), (6) settle-gate verification (asserting clusterversion at target, Available=True, Progressing=False, zero degraded/progressing/unavailable COs, and all MCPs Updated=True), (7) hop completion notification dispatch via `sendmail` with Prevalidation HTML audit report attached and dual `.txt`/`.csv` logging. Full `block/rescue` with hierarchical error extraction, RBAC error detection, alert dispatch via `error_handle`, and guaranteed session logout.
  - `playbooks/04_Live_monitoring_upgrade.yaml`: Phase 04 tasks file entrypoint with dual-version headers, displaying live monitoring configuration and handing off to `roles/monitor` when present.
  - `playbooks/03_Initiate_upgrade.yaml`: Phase 03 playbook with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`). Reuses authenticated session from Phase 01/02 (with login fallback), ingests all 6 `vars/` files, validates non-empty `upgrade_path`, sequentially executes minor-version upgrade hops via `tasks/hop.yml` using `include_tasks:` with `loop: "{{ upgrade_path }}"`, and encloses execution in `block/rescue/always` with fail-safe error handling and guaranteed session logout.
- [x] **Unit 11: Live Monitoring & Settle-Gate (`monitor` Role, `04_Live_monitoring_upgrade.yaml`)**:
  - `playbooks/roles/monitor/`: Live upgrade monitoring engine (`defaults/main.yml`, `tasks/main.yml`, `tasks/poll_iteration.yml`). Coordinates 2-minute polling of `clusterversion`, `mcp`, `clusteroperators`, and `nodes`, enforces 90-minute timeout guard, calculates control plane and worker MCP rollout progress percentages, detects cluster state changes for immediate alert dispatch, sends 20-minute heartbeat progress emails via `sendmail` with `progress-mail.j2`, executes Tier 2 auto-remediation for stalled updating nodes (`touch /run/machine-config-daemon-force`), and verifies strict settle-gate conditions before declaring hop complete.
  - `playbooks/04_Live_monitoring_upgrade.yaml`: Phase 04 task playbook entrypoint. Normalizes hop context facts, coordinates live monitoring via `roles/monitor`, and logs audit trails.
- [x] **Unit 12: Postvalidation Role & Phase 05 Playbook (`postvalidation` Role, `05_post_Upgrade_Checks.yaml`)**:
  - `playbooks/roles/postvalidation/`: Full implementation of the **10-check postvalidation contract** (Check 01: Final ClusterVersion match, Available=True, Progressing=False; Check 02: ClusterOperators status and allow-list; Check 03: MachineConfigPools updated and healthy; Check 04: Node readiness and target kubelet minor version `v1.<Y+13>.` alignment; Check 05: Node resource pressures and unschedulable limits; Check 06: etcd quorum and CO health; Check 07: PersistentVolumes Bound/Available; Check 08: Core namespace platform pod health; Check 09: Firing Prometheus critical alerts; Check 10: **Baseline Diff Audit** comparing node inventory, operator versions, and route availability against Phase 01 baseline snapshot).
  - `playbooks/05_post_Upgrade_Checks.yaml`: Phase 05 playbook. Connects to localhost, ingests all 6 `vars/` files, reuses authenticated session from previous phases, executes 10-check postvalidation and baseline diff, generates client HTML report via `report` role (`output/<cluster>_postvalidation_<ts>.html`), emits dual `.txt`/`.csv` audit logs, preserves authenticated session for Phase 06 operator upgrades, and guarantees fail-safe logout on error via `block/rescue/always`.
- [x] **Unit 13: Operator Lifecycle Roles & Phase 06 Playbook (`operator_compat`, `operator_upgrade`, `operator_validate`, `06_Operator_Upgrade.yaml`)**:
  - `playbooks/roles/operator_compat/`: Compatibility scan role. Resiliently queries all installed OLM `Subscription` resources (`oc get subscriptions.operators.coreos.com -A -o json`), inspects `PackageManifest` across source namespaces, parses available update channels matching the target OpenShift minor version prefix (e.g. `stable-4.16`, `fast-4.16`, or `4.16`), builds `operator_compat_plan`, handles empty clusters cleanly, and exposes compatibility findings.
  - `playbooks/roles/operator_upgrade/`: Manual InstallPlan approval and CSV rollout role. Discovers unapproved manual InstallPlans (`spec.approved == false`), sequentially approves each via deterministic merge patch (`oc patch installplan <name> -n <ns> --type=merge -p '{"spec":{"approved":true}}'`), monitors CSV rollout in a bounded loop calculated from `operator_upgrade_timeout_seconds // operator_upgrade_poll_interval_seconds` (default: 600s / 15s = 40 iterations), and implements **Tier 2 one-shot recovery** deleting failed/stalled CSVs once (`oc delete csv <name> -n <ns>`) to trigger OLM subscription reconciliation.
  - `playbooks/roles/operator_validate/`: Post-upgrade operator health validation role. Asserts that all installed subscriptions reference valid installed CSVs, confirms all active CSVs report `phase: Succeeded`, generates client-facing HTML report via `roles/report` (`output/<cluster>_operators_<ts>.html`) with subscription namespaces, installed CSVs, target channels, approval modes, and status pills, and enforces HARD gate halting on unrecovered failures.
  - `playbooks/06_Operator_Upgrade.yaml`: Complete Phase 06 playbook with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`). Ingests all 6 `vars/` files, verifies/establishes cluster session in `pre_tasks:`, executes all 3 operator roles, resolves all 4 core audit attachments (prevalidation, postvalidation, operators, run log), dispatches the final Upgrade-Complete digest email via `roles/sendmail` with `progress-mail.j2` displaying `ALL PHASES COMPLETE ✔`, and executes definitive terminal session logout via `roles/logout` in both success and rescue branches.
  - `playbooks/main.yml`: Orchestrator imports un-commented for all five phase entrypoint playbooks (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`).
  - Tested: Python PyYAML validation across all 12 files (71 tasks total, 100% named, 0 deprecations, 0 bare `include:`, 0 `ansible_failed_task.name`), Jinja2 rendering tests for `progress-mail.j2` (13,743 bytes) and `health-overview.j2` (16,292 bytes), and bash syntax validation (`bash -n`).
- [x] **Unit 14: Master Wiring & End-to-End Integration (`main.yml`)**:
  - `playbooks/main.yml`: Master orchestrator wired with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`) and migration comments. Sequential chaining across all five phase entrypoint playbooks (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`).
  - **Input Validation & Initialization**: Ingests all 6 `vars/` files, asserts non-empty `cluster_name` and `upgrade_path`, and displays 1-touch initialization debug banner.
  - **Dry-Run Intercept & Early Teardown**: Dedicated localhost intercept play following Phase 02 (`when: dry_run | default(false) | bool`). Logs dry-run completion, tears down authenticated session via `roles/logout`, and cleanly terminates playbook execution via `meta: end_play`. Downstream mutation phases (03, 05, 06) are protected with `when: not (dry_run | default(false) | bool)`.
  - **Selective Execution (`skip_to_phase`)**: Enforces `(skip_to_phase | int) <= N` guards on all phase imports, permitting recovery or targeted executions directly into Phase 02, 03, 05, or 06 without triggering prior phases.
  - Tested: Python PyYAML syntax verification, 100% named tasks (6 tasks across 2 plays), 0 deprecations, dry-run intercept logic audit, selective phase evaluation matrix (scenarios for full-run, dry-run, skip-to-05, skip-to-06), `bash -n` validation of CLI entrypoint, and mock dry-run and `--skip-to-phase` execution flows via `00_Run.sh` (exit code 0).
- [x] **Unit 15: Exception Handling & Error Extraction Patterns (Cross-Cutting Specification)**:
  - Standardized hierarchical error extraction cascade (`ansible_failed_result.stderr` -> `ansible_failed_result.stderr_lines` -> `ansible_failed_result.msg` -> fallback) across all 6 rescue blocks (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `tasks/hop.yml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`) and `roles/error_handle`.
  - Comprehensive RBAC authorization failure detection (`is_rbac_error`) for `forbidden`, `cannot patch`, `unauthorized`, `cannot get`, `cannot list`, and `cannot create` across all rescue blocks and `roles/error_handle`.
  - Guaranteed fail-safe session teardown invoking `logout` with `failed_when: false` in both `rescue:` and `always:` blocks across all phase playbooks.
  - Zero `ansible_failed_task.name` references, zero Jinja2 self-referencing variable passes, and 100% shell pipes specify `args: executable: /bin/bash`.
  - Tested: Automated verification script covering all 6 checklist criteria (100% pass), PyYAML validation across all files, and Jinja2 rendering tests for `error-report.j2`.

- [x] **CLI Interactive Menu & Terminal Geometry Fix (`scripts/cli_helpers.sh`, `00_Run.sh`)**:
  - ANSI-C Quoting: Resolved raw `\033[...]` string escapes in menus by switching color variables to `$'\033[...m'`, emitting genuine terminal control bytes.
  - Loop Variable Scoping: Declared `local i` and scoped loop indices across all box drawing and menu functions, eliminating inner-loop collision that prematurely aborted menus and omitted option 3 (`cluster_p01`).
  - Strict 72-Column Geometry: Corrected header decoration offset to `title_len + 6` and implemented fast O(1) `printf -v padding "%*s" "$pad_len" ""` row padding, guaranteeing perfect right-border alignment at column 72.
  - Subprocess-Free ANSI Stripping: Replaced pipe-and-fork `sed` calls in `strip_ansi` and `visible_length` with instant pure-Bash regex parsing.
  - Dual-Mode Terminal Compatibility: Auto-normalizes locale to `C.UTF-8` and supports clean 72-column ASCII fallback (`+`, `-`, `|`, `* (Default)`) via `ARO_CLI_ASCII=true`.
  - Clean `return 0` & `MENU_CHOICE` Export: Replaced `return "$choice"` with clean `return 0` in `render_menu`, directly assigning `SELECTED_CHOICE="$MENU_CHOICE"`, `PATH_CHOICE="$MENU_CHOICE"`, `MODE_CHOICE="$MENU_CHOICE"`. Completely eliminated `${...}` parameter expansions that caused `bad substitution` errors when copy-pasted across terminals.
  - Tested: 6-part automated verification test suite + full 3-menu simulated interactive test (Cluster, Path, Mode) running under `set -euo pipefail` (100% pass).

- [x] **Ansible IncludeRole Syntax & Phase 06 Block Indentation Fix (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`, `tasks/hop.yml`)**:
  - Resolved `ERROR! 'failed_when' is not a valid attribute for a IncludeRole` by removing `failed_when: false` from all 11 `include_role: name: logout` tasks.
  - Corrected `06_Operator_Upgrade.yaml` indentation: shifted `always:` block from play-level (2 spaces, which triggered `ERROR! 'always' is not a valid attribute for a Play`) to block-level (6 spaces) and indented tasks to 8 spaces.
  - Guarded `upgrade_path[-1]` references in Phase 06 with conditional checks to support standalone playbook runs with empty `upgrade_path: []`.
  - Tested: Automated attribute verification (0 invalid attributes found), PyYAML validation (100% pass), and Jinja template rendering across standalone and populated contexts.

- [x] **Execution Mode Boundary & Phase Isolation Fix (Pre-check Only / Dry Run / Post-check Only) (`00_Run.sh`, `main.yml`)**:
  - **Option 3 Root Cause Resolution**: Resolved critical flaw where selecting Menu Option 3 ("Pre-check Only") set `SKIP_TO_PHASE="02"` and `DRY_RUN=false`. Because `main.yml` evaluated `(skip_to_phase | int) <= 3`, Phase 03 ("Initiate Upgrade Hops") was erroneously triggered, attempting to mutate cluster state with `oc adm upgrade` and failing with RBAC forbidden errors on unprivileged accounts.
  - **Phase Boundary Enforcement (`stop_after_phase`)**: Added `stop_after_phase` execution bounds across `main.yml` and `00_Run.sh` to complement `skip_to_phase`, providing strict start-at (`>=`) and stop-after (`<=`) lifecycle control.
  - **Dedicated Phase Intercept Plays**:
    - **Prevalidation Intercept (Post-Phase 02)**: Triggers when `dry_run: true` OR `stop_after_phase <= 2`. Performs clean cluster session logout via `roles/logout` and cleanly halts execution via `meta: end_play`, guaranteeing Phase 03/04/05/06 never execute.
    - **Post-Check Intercept (Post-Phase 05)**: Triggers when `stop_after_phase <= 5`. Performs clean session logout via `roles/logout` and halts execution via `meta: end_play`, preventing Mode 4 from cascading into Phase 06 operator upgrades.
  - **Execution Mode Mapping in `00_Run.sh`**:
    - Mode 1 (Full Upgrade): `dry_run: false`, `skip_to_phase: ""`, `stop_after_phase: ""` (Phases 01 -> 06).
    - Mode 2 (Dry Run): `dry_run: true`, `stop_after_phase: "02"`, `auto_remediation_enabled: false` (Zero mutations).
    - Mode 3 (Pre-check Only): `dry_run: true`, `stop_after_phase: "02"`, `auto_remediation_enabled: true` (Runs 01 & 02 with auto-remediation, stops cleanly before Phase 03).
    - Mode 4 (Post-check Only): `dry_run: false`, `skip_to_phase: "05"`, `stop_after_phase: "05"` (Runs Phase 05, stops cleanly before Phase 06).
  - **CLI Flags & Production Guard Refinement**: Added `--pre-check`, `--post-check`, and `--stop-after-phase <NN>` flags to `00_Run.sh`. Refined PROD safety gate to require typing `UPGRADE` only for mutating runs, allowing non-mutating validation on PROD without the `UPGRADE` confirmation prompt.
  - **Tested**: Bash syntax verification (`bash -n`), help screen validation, mock CLI execution testing for `--pre-check` and `--post-check` (exit code 0), and Python boolean matrix verification validating 100% phase isolation across all 5 operational scenarios.

- [x] **Prevalidation HTML Report Email Notification (`02_Pre_upgrade_check.yaml`, `vars/smtp.yml`, `00_Run.sh`)**:
  - **Automated Report Dispatch**: Added email notification dispatch to `playbooks/02_Pre_upgrade_check.yaml` immediately following report generation. Renders the interactive HTML report via `health-overview.j2` and attaches the generated `output/<cluster>_prevalidation_<ts>.html` report artifact.
  - **Option 3 & Pre-check Delivery**: Guarantees that running Option 3 ("Pre-check Only") or `--pre-check` automatically delivers the full prevalidation health report to operator inboxes rather than leaving it exclusively on disk.
  - **Configurable Routing & Subject**: Configured `preval_mail_to` (with automatic fallback to `mail_to`), `prevalidation_subject_prefix: "[ARO Upgrade PREVALIDATION]"`, and master toggle `send_prevalidation_email: true` in `vars/smtp.yml`.
  - **CLI Recipient Override (`--mail-to`)**: Added `-m, --mail-to <email>` flag in `playbooks/00_Run.sh` allowing operators to specify custom or ad-hoc report distribution lists directly from the command line.
  - **Resilient Dispatch**: Wrapped email delivery in a non-fatal `block/rescue` structure; if SMTP relay connectivity fails, the engine logs a clear `[WARN]` diagnostic without corrupting the prevalidation audit or halting execution.
  - **Tested**: YAML syntax validation of `02_Pre_upgrade_check.yaml` and `vars/smtp.yml`, Jinja2 rendering verification of `health-overview.j2` (13,683 bytes), bash syntax check (`bash -n`), and mock CLI execution testing with `--pre-check --mail-to "ops-team@company.com"` (exit code 0).

- [x] **Postvalidation HARD Gate Resolution & Diagnostic Observability (`postvalidation`, `05_post_Upgrade_Checks.yaml`, `00_Run.sh`, `vars/upgrade.yml`)**:
  - **Inverted JQ Fallback Corrections**: Corrected Check 01 JQ fallback for `progressing` from `// "True"` to `// "False"`. Corrected Check 02 JQ fallback for `degraded` from `// "True"` to `// "False"` and `progressing` to `// "False"`. Eliminates false-positive degradation when conditions are missing or null.
  - **Dynamic Target Version Resolution**: Added `postval_effective_target_version` in `roles/postvalidation/tasks/main.yml`. When `postval_resolved_target_version` is `'current'`, `'auto'`, or empty, postvalidation dynamically resolves to the cluster's current settled version (`postval_cv_data.current_version`), enabling standalone postvalidation sweeps on live clusters without requiring an upgrade path. Added `| string | trim` string normalization across version comparisons.
  - **ClusterOperator Settle Re-check Loop**: Implemented a 30-second automated settle window (up to 3 retries with 10s delay) in Check 02 to absorb transient telemetry or controller reconciliation spikes before declaring failure.
  - **Detailed Diagnostic Gate Failure Message**: Refactored `Enforce HARD postvalidation gate` to display each failed check's number, name, gate, and `observed` explanation, ensuring complete terminal and log visibility.
  - **Fail-Safe HTML Report Generation on Failure**: Added an automated report generation block within the `rescue:` block of `playbooks/05_post_Upgrade_Checks.yaml`. If postvalidation checks ran before a failure, the HTML report is always generated and saved to disk.
  - **Dedicated Exit Code 25 in CLI Entrypoint (`00_Run.sh`)**: Added `Exit Code 25: Postvalidation Gate Failed (Phase 05)` and updated log inspection regexes to evaluate Phase 05 failures before Phase 03/04 rules. Enhanced the interactive path selection menu in Mode 4 to offer `Current Live Cluster Version` as the default validation target.
  - **Global `co_allow_list` Configuration (`vars/upgrade.yml`)**: Exposed `co_allow_list: []` in `vars/upgrade.yml` with clear operator documentation for excluding non-critical or environment-specific components.
- [x] **Automated Post-Upgrade Validation & Upgrade Success Email System (`05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`, `vars/smtp.yml`, `00_Run.sh`)**:
  - **Automated Dispatch in Phase 05**: Added notification dispatch in `playbooks/05_post_Upgrade_Checks.yaml` upon successful postvalidation contract satisfaction. Formats interactive HTML report via `health-overview.j2` and attaches `output/<cluster>_postvalidation_<ts>.html`.
  - **Configurable Routing & Prefixes**: Added `postval_mail_to`, `postvalidation_subject_prefix: "[ARO Upgrade POSTVALIDATION]"`, and master toggles `send_postvalidation_email: true` and `send_upgrade_success_email: true` in `vars/smtp.yml`.
  - **CLI Recipient Override**: Extended `--mail-to` flag in `00_Run.sh` to route to `postval_mail_to`.
  - **Phase 06 Subject Standardization & Resilience**: Updated Phase 06 completion subject to `completion_subject_prefix: "[ARO Upgrade COMPLETE]"` and wrapped email delivery in non-fatal `block/rescue` for SMTP fault tolerance.
- [x] **Phase 06 Operator Upgrade InstallPlan Query & JSON Parsing Resolution (`operator_upgrade`, `operator_compat`, `operator_validate`)**:
  - **Eliminated Two-Step Shell Anti-Pattern**: Replaced two-step `oc get ... -o json 2>/dev/null || echo '...'` followed by `echo '{{ stdout }}' | jq` with single atomic tasks streaming JSON directly from `oc` to `jq` via memory pipe (`oc get ... -o json 2>/dev/null | jq -c '...' || echo '[]'`).
  - **Resolved JSONDecodeError ("Extra data: line 2 column 1 (char 3)")**: Eliminated multi-line JSON emission caused by sequential objects/echoes. Wrapped fact parsing in `((stdout | trim).split('\n') | first | from_json)` to guarantee clean JSON decode.
  - **Eliminated Bash Quoting Collisions**: Streaming directly to `jq` prevents shell breakout and character collisions when operator descriptions, messages, or annotations contain single quotes.
  - **Attached KUBECONFIG Environment Context**: Added `environment: KUBECONFIG: "{{ cluster_kubeconfig | default(...) }}"` across all tasks in `operator_upgrade`, `operator_compat`, and `operator_validate`.
- [x] **Phase 06 Operator Mutation Bypass & Validation-Only Control (`skip_operator_upgrade`, `06_Operator_Upgrade.yaml`, `00_Run.sh`, `vars/upgrade.yml`)**:
  - **Operator Mutation Bypass Guard**: Added `skip_operator_upgrade: false` in `playbooks/vars/upgrade.yml` and `roles/operator_upgrade/defaults/main.yml`. Guarded Step 2 in `playbooks/06_Operator_Upgrade.yaml` with `when: not (skip_operator_upgrade | default(false) | bool)` and added explicit informational notification when bypassed.
  - **Non-Mutating Validation-Only Mode**: Allows operators to execute Phase 06 to scan version compatibility (`roles/operator_compat`), bypass manual `oc patch installplan` mutations (preventing RBAC 403 Forbidden halts on restricted namespaces such as `openshift-lightspeed`), execute full health validation and HTML report generation (`roles/operator_validate`), and deliver the final Upgrade-Complete email digest with all 4 audit attachments.
  - **CLI Flag Integration (`00_Run.sh`)**: Exposed `--skip-operator-upgrade` flag in `playbooks/00_Run.sh` and routed it through the Python extra-vars JSON assembly script.
- [x] **Phase 06 Consolidated Operator Failure Notification & Attached HTML Report (`06_Operator_Upgrade.yaml`, `error_handle`, `error-report.j2`)**:
  - **Fail-Safe Operator Report Generation on Failure**: Added check and fail-safe execution of `roles/operator_validate` (`operator_validate_enforce_gate: false`) within `06_Operator_Upgrade.yaml`'s rescue block. Guarantees that `output/<cluster>_operators_<ts>.html` is generated on disk even if failure occurred early during `roles/operator_upgrade` (e.g. InstallPlan RBAC error or CSV settle timeout).
  - **Consolidated Audit Attachments on Failure**: Gathers all available audit reports (`operators_<ts>.html`, `postvalidation_<ts>.html`, `prevalidation_<ts>.html`, run log) into `mail_attachments` and `attached_reports`.
  - **User Recipient Routing & Subject Personalization**: Updated `error_handle` to merge `mail_to` (the operator/user who ran the playbook or passed via `--mail-to`) and `alert_mail_to`, ensuring the user receives the failure notification. Sets customized subject: `[ARO Upgrade ALERT] Phase 06 Operator Failure — <cluster>`.
  - **Email Template Visualization (`error-report.j2`)**: Added "Attached Diagnostic Reports" callout section in `error-report.j2` displaying all attached audit artifacts alongside diagnostic details, error outputs, and RBAC remediation guidance.
  - **SMTP Resilience**: Wrapped failure alert email dispatch in `block/rescue` within `error_handle` to ensure SMTP relay errors never prevent subsequent session logout and cluster teardown.

- [x] **Unit 16: Developer Comments & Documentation Standards (Cross-Cutting Specification)**:
  - **Standardized File Header Blocks**: Applied 6-field header schema (`Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)`, `MIGRATION 2.14:`, `Purpose:`, `Role / Playbook Dependencies:`, `Gate Type:`, `Outputs:`) across all 71 YAML files and bash scripts.
  - **Jinja2 Presentation Template Headers**: Structured documentation blocks in `error-report.j2`, `progress-mail.j2`, and `health-overview.j2` declaring context, inbound fact dependencies, and layout/accessibility constraints.
  - **Role Defaults Variable Documentation**: Fully standardized all 24 role `defaults/main.yml` files with explicit variable type annotations, descriptions, and source references.
  - **Task-Level Inline `# Why:` Logic Comments**: Added explanatory `# Why:` annotations across all 53 shell tasks using `set -o pipefail`, jq 1.5 workarounds (custom `rnd2` rounding), and bracket queries.
  - **Rescue Block Commentary**: Documented error extraction cascade, alerts dispatched, and session logout guarantees across all phase playbooks.
  - **Tested**: Comprehensive 8-point automated verification suite (`verify_unit16.py`) validating 100% compliance across all checklist criteria (100% pass).

### In Progress
- None (Ready for Documentation Prompt)

### What's Next
1. **Antigravity Word/PowerPoint Documentation Generation Prompt**: Generation prompt artifact (`Documentation_Prompt.md`).




---

## Architecture Overview

The automation operates through a **seven-file process surface**:
```
playbooks/
├── 00_Run.sh                    # CLI Entrypoint: pre-flight, menus, confirmation, locks, summary
├── main.yml                     # Master Orchestrator: chains phases 01 -> 06
├── 01_Policy_Check.yaml         # Phase 01: Auth, baseline snapshot, update edge validation
├── 02_Pre_upgrade_check.yaml    # Phase 02: 14-check prevalidation gate + auto-remediation
├── 03_Initiate_upgrade.yaml     # Phase 03: Per-hop driver looping tasks/hop.yml
├── 04_Live_monitoring_upgrade.yaml # Phase 04: 2-min polling, 20-min heartbeats, settle-gate
├── 05_post_Upgrade_Checks.yaml  # Phase 05: 10-check postvalidation gate + baseline diff
└── 06_Operator_Upgrade.yaml     # Phase 06: OLM operator scan, approval, and terminal logout
```

### Supporting Structure
```
playbooks/
├── vars/                        # Input variables (no executable logic)
├── scripts/                     # Sourced shell libraries (cli_helpers.sh)
├── roles/                       # 24 modular single-concern roles
├── tasks/                       # Sub-playbook workflow tasks (hop.yml)
├── templates/                   # Jinja2 presentation templates (.j2)
├── logs/                        # Write-only run logs (.txt and .csv)
├── output/                      # Write-only HTML audit reports
└── snapshots/                   # Immutable baseline JSON snapshots
```

---

## Key Invariants

1. **Deterministic & Rule-Based**: No AI, probabilistic models, or non-deterministic branching in the runtime execution path.
2. **Dual-Version Compatibility**: Runs identically on Ansible 2.7.17 and 2.14.18 with short module names and typed defaults (`| default('')`).
3. **Fail-Safe Session Lifecycle**: Authenticates once in Phase 01, persists session across phases, and guarantees immediate logout/token revocation on any failure via `block/rescue/always`.
4. **Auto-Remediation Engine**: Safely resolves non-destructive upgrade blockers (cgroup v1→v2 migration, dynamic admin-acks, paused MCPs) with before-and-after state verification.
5. **Zero Plaintext Secrets**: All credentials sourced as variable references (`{{ vault_* }}`) with `no_log: true`.

---

## How to Run (Once Built)

```bash
cd playbooks
./00_Run.sh
```

Or pass explicit flags to bypass interactive menus:
```bash
./00_Run.sh --cluster cluster_d01 --path "4.14.40,4.15.35,4.16.18" --mode full
```

Available run modes:
- `full`: Complete end-to-end upgrade (pre-flight → prevalidation → hops → postvalidation → operators).
- `precheck`: Run Phase 01 and Phase 02 health checks and report without initiating cluster hops.
- `dry-run`: Validate cluster connectivity, credentials, and update edges without mutating cluster state.
- `status`: Query live clusterversion, MCP status, and node conditions.
