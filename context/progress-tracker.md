# Progress Tracker — ARO Cluster Upgrade Automation

Update this file after **every meaningful implementation change**.

---

## Current Phase
- **Phase 3 — Review Remediation (deep review findings + admin-ack, Developer perspective, mail de-duplication)**

## Current Goal
- **Code complete and verified offline** (2026-10-01): all review findings fixed, admin-ack per minor hop, Developer perspective, mail rework. Next: jump-host validation on Ansible 2.7.17 / 2.14.18 (see Next Up). Nothing committed — the user commits when ready.

---

## v1 Build History & Baseline Summary
The v1 prototype successfully constructed and validated all 21 units of the ARO Cluster Upgrade Automation:
- **Scaffolding & Session (Units 01–03)**: `playbooks/` structure, 6 `vars/` files, CLI entrypoint `00_Run.sh`, `main.yml` orchestrator, `login` and `logout` session lifecycle roles.
- **Reporting & Error Handling (Units 04–06)**: Jinja2 templates (`error-report.j2`, `progress-mail.j2`, `health-overview.j2`), `sendmail` role (native `mail` module direct SMTP), `error_handle` and `report` roles.
- **Phase 01 Baseline & Edge Check (Unit 07)**: `snapshot` role capturing cluster JSON baseline, edge verification against `oc adm upgrade`.
- **Health & Disruption Roles (Units 08–16)**: `api_check`, `api_readiness`, `co`, `mcp`, `node`, `etcd`, `utilization`, `pv`, `pvc`, `pdb`, `operator_compat`, and `prevalidation` aggregator (15-check contract).
- **Upgrade Engine & Monitoring (Units 17–18)**: `upgrade` role, `tasks/hop.yml` per-hop loop, `monitor` role with 2-min polling, 20-min heartbeat, and settle-gate.
- **Postvalidation & Closeout (Unit 19)**: `postvalidation` role with 10-check contract and baseline diff against Phase 01 snapshot.
- **Operator Upgrades (Unit 20)**: `operator_compat`, `operator_upgrade`, `operator_validate` roles (Phase 06).
- **Documentation Prompt (Unit 21)**: Antigravity prompt for Word/PowerPoint generation.

---

## v1 Lessons Learned & Anti-Patterns Catalog

During v1 development and testing, 20+ critical operational and syntax issues were resolved. These must **never be repeated** in the rebuild:

1. **Jinja2 Self-Referencing Variables**: Passing `vars: failure_reason: "{{ failure_reason }}"` into `include_role` triggers infinite recursion and crashes Ansible. Always pre-compute facts with `set_fact` and let the role consume host facts directly.
2. **`ansible_failed_task.name` Crash**: In rescue blocks, referencing `ansible_failed_task.name` crashes Ansible because it is an internal `FieldAttribute` object. Extract errors strictly from `ansible_failed_result.stderr` or `ansible_failed_result.msg`.
3. **Sendmail Fact Caching**: The `sendmail` role must always render `mail_template` fresh on each invocation and explicitly clear `mail_html_body` and `mail_final_body` post-dispatch to avoid sending stale bodies across hops.
4. **OpenShift Condition Boolean Normalization**: OpenShift conditions may deserialize to Python `bool True` instead of string `"True"`. Always normalize condition strings with `| string | trim` before comparing.
5. **Kubernetes JSON Array Key Clashes**: In Jinja2/JSON queries, accessing `.items` triggers Python's built-in `dict.items()` method. Always use bracket notation `['items']` to access Kubernetes item lists.
6. **jq v1.5 Compatibility**:
   - `round` is not defined in jq 1.5. Custom rounding functions must not start with `round` (e.g. use `def rnd2: . * 100 | floor / 100;`).
   - Conditional operands (`or`/`and`) must be explicitly parenthesized to prevent boolean coercion in string functions.
7. **Shell `set -o pipefail` Execution**: Ansible defaults to `/bin/sh` (which may be `dash` on Debian/Ubuntu). Shell tasks using `set -o pipefail` must set `args: executable: /bin/bash`.
8. **Multi-line `shell: |` vs `shell: >-`**: Use `shell: |` with explicit line continuations (`\`). `shell: >-` strips newlines and breaks complex multi-argument CLI pipelines.
9. **CLI Extra-Vars Format**: Passing extra-vars as `key=value` stringifies lists through Ansible's `parse_kv`. Pass extra-vars as a single valid JSON string: `-e '{"cluster_name":"...","upgrade_path":[...]}'`.
10. **Transient Network Blips**: All `oc` CLI commands must implement retry loops (`retries: 3 / delay: 10 / until: rc == 0`) to withstand API server restarts and transient 503 errors.
11. **RBAC Error Detection**: Extract error text hierarchically (`stderr` → `stderr_lines` → `msg`) and search for `forbidden`, `cannot patch`, `unauthorized` to surface actionable remediation commands.
12. **CGroup v1 Blocker (OpenShift 4.19+)**: Clusters running cgroup v1 block upgrades to 4.19+. Must detect and auto-patch `nodes.config/cluster` to `cgroupMode: "v2"`.
13. **Dynamic Admin-Acks**: Admin-acks must be parsed dynamically from `ClusterVersion` conditions and applied to `openshift-config/admin-acks`.
14. **Paused MachineConfigPools**: Paused pools stall rollouts; detect and auto-unpause permitted pools in prevalidation.
15. **Boolean-String Equality Anti-Pattern**: In Ansible `set_fact`, values like `"True"` or `"False"` deserialize into Python booleans `True`/`False`. Comparing `etcd_co_available == 'True'` evaluates `True == 'True'`, which is **`False`** in Python. Always normalize with `| string | trim | lower == 'true'` and evaluate with `(var | bool)`.
16. **System PDB False Positive Deadlocks**: Platform components (such as Loki logging) run with `disruptionsAllowed: 0`. Strict PDB gates (`fail_on_zero_disruption_pdb: true`) cause fatal prevalidation halts. Default to `fail_on_zero_disruption_pdb: false` (WARN advisory) and filter out core system namespaces (`openshift-*`, `kube-*`).
17. **CGroup Remediation Target Version Guard & Error Extraction**: Auto-remediation tasks must not attempt cgroupMode v2 patches unless the target version requires it (`>= 4.19`). When `oc patch` fails, never swallow `stderr` or rely on unset jsonpath fields that render blank `observed: ` messages; capture `stderr` explicitly.
18. **Regex backreferences in YAML-quoted Jinja** (`'\1'`) are decoded to control characters: the old Check 14 never required cgroup v2 and the old postvalidation Check 04 expected kubelet `v1.13.`. Parse with `split('.')`.
19. **`ansible_date_time` is frozen** at fact gathering: every monitor duration, heartbeat and stall timer read 0. Read `date +%s` per use.
20. **`lineinfile` on the run log** replaced the file by rename and detached the CLI's `tee`: the rest of the console log was lost. Only `tasks/log_event.yml` (append) writes logs.
21. **`until` + retries exhausted = failed task** even with `failed_when: false` (Phase 05 operator settle crashed the phase). Waits whose result is data are in-shell loops.
22. **Attribute access on undefined facts** raises on Ansible 2.7 before `| default` applies; guard with `(x | default({})).attr`.
23. **Facts beat task vars**: `include_role … vars:` cannot override a fact set earlier (use `set_fact`).
24. **Remediation marking whole checks fixed** hid other failures of the same check; fixes now only record attempts and Phase 02 re-runs the full scan.
25. **`conditionalUpdates[].version` does not exist** — the version is `conditionalUpdates[].release.version`; conditional edges were never matched.
26. **Nested rescues each sent an alert** (hop + Phase 03) and alerts reused the previous mail's subject; one alert per run (`failure_alert_sent`) and per-mail `notify_*` inputs reset after each send.

---

## Completed (Rebuild Phase)
- [x] **Implementation Plan**: Approved by user. Incorporates Phase 06 renumbering, 14 CLI improvements, 8-blocker auto-remediation engine, and 18 consolidated feature specs.
- [x] `context/code-standards.md`: Rewritten with exception hierarchy, Jinja2 anti-patterns, jq 1.5 rules, auto-remediation standards, status types (`AUTO-FIXED`, `FIX-FAILED`), and developer comment standards.
- [x] `context/architecture.md`: Rewritten with seven-process surface (`00`–`06`), 24 roles, auto-remediation resilience model, concurrency locks, and updated invariants.
- [x] `context/project-overview.md`: Rewritten with one-touch automation goals, 14 CLI features, 8 auto-remediation blockers, Phase 06 operator lifecycle, and updated success criteria.
- [x] `context/ui-context.md`: Rewritten with `AUTO-FIXED`/`FIX-FAILED` status pills, operator validation report styling, 4-attachment completion digest, and CLI terminal conventions.
- [x] `context/ai-workflow-rules.md`: Rewritten with rebuild-mode workflow, auto-remediation toggle rules, protected files, and expanded pre-completion checklist.
- [x] **Unit 01: Project Scaffold & Variable Inputs**:
  - `playbooks/` folder hierarchy established (`vars/`, `scripts/`, `roles/`, `tasks/`, `templates/`, `logs/`, `output/`, `snapshots/`).
  - All 6 variable files created with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`) and validated for syntax:
    - `vars/upgrade.yml`: Global targets, paths, thresholds, cadences, and auto-remediation toggles.
    - `vars/secrets.yml`: Variable references (`{{ vault_* }}`) with zero plaintext secrets and cluster metadata map.
    - `vars/smtp.yml`: Direct SMTP host, port, credentials, and notification subject prefixes.
    - `vars/paths.yml`: Dynamic path derivations anchored strictly to `playbook_dir`.
    - `vars/report_vars.yml`: UI color tokens, background tints, and badge constants matching `context/ui-context.md`.
    - `vars/api_regex.yml`: Validation regex for cluster API URLs, version numbers, and cluster names.
  - `.gitkeep` anchors placed in write-only and role/task/template directories.
  - `playbooks/scripts/cli_helpers.sh` library stub created with ANSI colors, UTF-8 box characters, and logging functions.

- [x] **Unit 02: CLI Entrypoint (`00_Run.sh`), Helper Library (`scripts/cli_helpers.sh`) & Orchestrator Skeleton (`main.yml`)**:
  - `playbooks/scripts/cli_helpers.sh`: Expanded into complete terminal UI engine. Sourced guard, ANSI color codes with TTY detection, 72-col box primitives (`draw_box_header`, `draw_box_row`, `draw_box_divider`, `draw_box_footer`), ANSI escape sequence stripping for exact visible width alignment, status message loggers (`msg_ok`, `msg_warn`, `msg_err`, `msg_info`, `msg_step`, `msg_autofix`), ASCII banner art, visual journey formatter (`print_journey`), risk assessment box (`print_risk_assessment`), interactive 72-column selection menu (`render_menu`), and post-run summary formatter (`render_post_run_summary`).
  - `playbooks/00_Run.sh`: Complete CLI entrypoint. `set -euo pipefail`, signal traps for `EXIT INT TERM` ensuring automatic lock removal and terminal sanity, comprehensive flag parsing (`-c/--cluster`, `-p/--path`, `-d/--dry-run`, `-y/--yes`, `--no-menu`, `-s/--skip-to-phase`, `-r/--resume`, `-v/--verbose`, `-q/--quiet`, `-h/--help`), pre-flight validation checking `bash >= 4`, `ansible-playbook`, `oc`, `jq`, and functional `python3`/`python`, Python-based YAML validation of all 6 `vars/*.yml` files with schema and cluster verification, interactive selection menus for cluster, upgrade path, and run mode, visual hop sequence and tier-aware risk assessment, production safety gate requiring typing `UPGRADE`, PID-based concurrency locking (`/tmp/aro-upgrade-<cluster>.lock`) blocking concurrent executions with stale PID cleanup, extra-vars formatting as single valid JSON object strings, live console tee'd logging to `logs/<cluster>_<ts>.txt`, and structured exit codes (0, 1, 2, 3, 10, 20, 30, 99).
  - `playbooks/main.yml`: Orchestrator skeleton with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`), anchored vars loading for all 6 vars files, mandatory asserts on `cluster_name` and `upgrade_path`, formatted dispatch debug banner, and structured phase execution placeholders (Phases 01 through 06).
  - Tested: Bash syntax verification (`bash -n`), help screen, invalid option rejection (code 1), pre-flight dependency failure handling (code 1), missing/invalid configuration detection (code 3), concurrency run lock blocking (code 1) with trap cleanup, full dry-run execution with tee'd logging and aligned 72-column post-run summary (code 0).

---

- [x] **Unit 03: Session Lifecycle Roles (`login`, `logout`)**:
  - `playbooks/roles/login/defaults/main.yml`: Default paths scoped to cluster (`.kubeconfig-<cluster>`), API regex pattern (`desired_cluster_api_regex: "^https://api\\.[a-zA-Z0-9.-]+:6443/?$"`), TLS verification flag (`insecure_skip_tls_verify: true`), CLI binary name (`oc_binary: "oc"`), and transient retry controls (`oc_command_retries: 3`, `oc_command_retry_delay: 10`). Dual-version headers and full developer comments.
  - `playbooks/roles/login/tasks/main.yml`:
    - Added dynamic OpenShift CLI binary discovery (`/usr/local/bin/oc` or system PATH).
    - Extended fact resolution to support flat variables (`cluster_*`), dictionary objects (`cluster.*`), and inventory maps (`clusters[...]`).
    - Switched execution to `shell: |` using bash with robust parameter quoting (`--username`, `--password`, API endpoint) and `--insecure-skip-tls-verify={{ insecure_skip_tls_verify | bool | lower }} 2>&1`, aligning with validated jump host execution scripts.
    - Added compatibility support for appending to `master_results` if defined by caller.
    - Updated identity assertion to use `{{ oc_binary }}` and generalized API URL pattern.
  - `playbooks/roles/logout/defaults/main.yml`: Centralized cluster-scoped kubeconfig path default with dual-version headers.
  - `playbooks/roles/logout/tasks/main.yml`: Fail-safe session teardown with `failed_when: false` and `changed_when: false` on token revocation (`{{ oc_binary | default('oc') }} logout`), idempotent file removal (`file: state=absent`), fact clearing to prevent leakage, and clean debug confirmation.
  - `playbooks/vars/api_regex.yml` & `playbooks/roles/api_check/defaults/main.yml`: Broadened `desired_cluster_api_regex` to `'^https://api\.[a-zA-Z0-9.-]+:6443/?$'` to support both hyphenated (`aro-d01`) and non-hyphenated (`arod01`) endpoint names.
  - `playbooks/vars/upgrade.yml`: Added default `insecure_skip_tls_verify: true` for enterprise ARO clusters using internal/cluster certificates.
  - `playbooks/vars/paths.yml`: Added `oc_binary: "oc"` default.
  - Tested: Python-based YAML syntax validation, endpoint regex assertions across cluster name patterns, and deprecation checks.

- [x] **Unit 04: Email Notification System & Templates (`sendmail` role, `error-report.j2`, `progress-mail.j2`, `health-overview.j2`)**:
  - `playbooks/roles/sendmail/defaults/main.yml`: Default SMTP configuration parameters (host, port 25, sender, empty recipient list, empty attachments, UTF-8 charset, optional auth/TLS modes) with dual-version headers.
  - `playbooks/roles/sendmail/tasks/main.yml`: Flexible template path resolution (relative, absolute, or prefixed), fresh lookup template rendering into `mail_html_body`, pre-dispatch parameter assertions (`mail_html_body` and `mail_to`), native direct SMTP dispatch on localhost via Ansible `mail` module with attachment support, and mandatory post-dispatch fact cleanup (`mail_html_body`, `mail_final_body`, `mail_attachments`, `mail_template`, `resolved_template_path`) preventing cross-hop caching.
  - `playbooks/templates/error-report.j2`: High-visibility failure alert card (`≤ 580px`, `#b42318` top border) featuring `UPGRADE HALTED ✖` header verdict, conditional RBAC warning callout with missing verbs/resources and actionable copy-paste remediation command (`oc adm policy add-cluster-role-to-user ...`), diagnostic failure matrix, pre-formatted error output block, safe session teardown confirmation, and run log reference.
  - `playbooks/templates/progress-mail.j2`: Compact upgrade progress and heartbeat card (`≤ 580px`) featuring Hop counter, target version, progress bar and percentage, elapsed duration, MachineConfigPool table (always visible with machine counts and status pills), active updating node table (healthy nodes suppressed), degraded/pressured node warning callouts, and `HOP COMPLETE ✔` settle-gate state with report attachment notice.
  - `playbooks/templates/health-overview.j2`: Multi-purpose HTML audit report (`max-width: 1080px`) for Prevalidation, Postvalidation, and Operator Validation. Renders header band with overall verdict pill, 5-tile summary metrics (total, passed, warnings, auto-fixed, failed), structured status table supporting `PASS ✔`, `WARN !`, `FAIL ✖`, `AUTO-FIXED ⚙` (blue `#1d4ed8`), and `FIX-FAILED ⚠` (orange `#c2410c`) status pills, conditional auto-remediation callout with Red Hat documentation links, OLM operator compatibility and CSV lifecycle table, collapsible `<details>` deep diagnostics with `@media print` expansion, and interactive copy-to-clipboard action.
  - Tested: Python PyYAML syntax verification, task naming and deprecation audit, native `mail` module argument verification, post-dispatch fact reset assertion, and Jinja2 rendering tests across all templates with empty/default variables, RBAC errors, active upgrade progress, hop completion, status pills, operator matrices, and universal boolean compatibility.

- [x] **Unit 05: Reporting & Error Handling Foundation (`error_handle` and `report` roles)**:
  - `playbooks/roles/error_handle/defaults/main.yml`: Default parameters (`current_step_no`, `current_task_name`, `current_gate_type: HARD`, `failure_reason`, `failure_observed`, `resolved_error`, `is_rbac_error`, `log_dir`, `run_timestamp`, `mail_template`, RBAC remediation defaults) with dual-version headers.
  - `playbooks/roles/error_handle/tasks/main.yml`: Standardized rescue block handler. Implements hierarchical error extraction (`stderr` -> `stderr_lines` -> `msg` -> fallback string) without referencing internal task objects, RBAC authorization error detection (`forbidden`, `cannot patch`, `unauthorized`, `cannot get`, `cannot list`), structured failure recording into `failed_checks` and `health_summary`, dual audit logging to human-readable `.txt` and machine-parseable `.csv` (with automatic header initialization), and failure alert email dispatch via `sendmail` with `error-report.j2`.
  - `playbooks/roles/report/defaults/main.yml`: Default parameters (`report_type: prevalidation`, `report_title: Pre-Upgrade Validation Report`, `overall_status: PASS`, `cluster_name`, `output_dir`, `report_template`, `is_operator_report`) with dual-version headers.
  - `playbooks/roles/report/tasks/main.yml`: Client-facing HTML report generator. Consolidates checks from `checks` or `health_summary`, derives 5-tile summary metrics (total, passed, warnings, auto-fixed, failed) with support for both health checks and OLM operator matrices, determines overall verdict badge (`FAIL` > `AUTO-FIXED` > `WARN` > `PASS`), auto-populates `autofix_items` from checks, renders `health-overview.j2`, writes standalone HTML artifact to `output/{{ cluster_name }}_{{ report_type }}_{{ run_timestamp }}.html` via `copy:` with `content:`, and exports `report_file_path` for downstream notification attachments.
- [x] **Unit 06: Snapshot Role & Phase 01 Playbook (`01_Policy_Check.yaml`, `snapshot` role)**:
  - `playbooks/roles/snapshot/defaults/main.yml`: Default paths, snapshot directory, target cluster, filename convention (`snapshots/<cluster>_<ts>_baseline.json`), and transient query retry settings (`retries: 3 / delay: 10`).
  - `playbooks/roles/snapshot/tasks/main.yml`: Resilient `oc` CLI query wrappers with retry protection and `args: executable: /bin/bash`, `set -o pipefail`, and `changed_when: false`. Implements strict **jq v1.5-compatible** filters extracting cluster metadata (`current_version`, `channel`, `cluster_id`), node inventory (`name`, roles parsed from `node-role.kubernetes.io/*` labels, `kubelet_version`, `Ready` condition, `unschedulable`), cluster operators (`name`, version, `Available`, `Progressing`, `Degraded` states), and exposed routes (`name`, `namespace`, `host`). Assembles structured `baseline_dict`, persists formatted JSON artifact via `copy: content="{{ baseline_dict | to_nice_json }}"`, and exports `baseline_snapshot_file_path` for Phase 05 postvalidation diffing.
  - `playbooks/01_Policy_Check.yaml`: Complete Phase 01 playbook with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`). Connects to localhost, ingests all 6 `vars/` files, establishes session in `pre_tasks:` via `login` role, captures baseline snapshot via `snapshot` role, queries live `availableUpdates` and `conditionalUpdates` from `ClusterVersion`, consolidates valid update edges, enforces a HARD gate (`fail:`) with detailed diagnostic output if `upgrade_path[0]` is not a valid edge, and logs confirmation to `.txt` and `.csv` (with automatic header initialization). Implements standardized `rescue:` block extracting error hierarchy, calling `error_handle`, setting `phase_01_failed: true`, and invoking `logout`, with guaranteed teardown verification in `always:` block.
  - Tested: Python PyYAML validation across all files, dual-version header compliance audit, 100% named tasks (10 snapshot tasks, 21 Phase 01 tasks), zero forbidden patterns (`warn:`, bare `include:`, `ansible_failed_task.name`), jq v1.5 filter execution on mock cluster payloads, update edge validation logic (available/conditional/invalid), baseline dictionary serialization/deserialization, and CSV logging schema compliance.

- [x] **Unit 07: Health Check Roles (`api_check`, `api_readiness`, `co`, `mcp`, `node`, `etcd`)**:
  - `playbooks/roles/api_check/`: API context verification role. Queries live active server URL via `oc whoami --show-server` with transient retry protection (`retries: 3 / delay: 10`), validates URL against `desired_cluster_api_regex` pattern from `vars/api_regex.yml`, records structured result to `health_summary`, and enforces HARD gate (`fail:`) naming observed vs expected on mismatch.
  - `playbooks/roles/api_readiness/`: API endpoint health verification role. Queries raw `/readyz` endpoint via `oc get --raw=/readyz` with retry protection (`until: rc == 0 and stdout == 'ok'`), verifies payload equals `ok`, records structured result to `health_summary`, and enforces HARD gate (`fail:`) naming observed payload on non-200 / unhealthy responses.
  - `playbooks/roles/co/`: ClusterOperator health evaluation role. Queries `oc get clusteroperators -o json` with jq v1.5 parsing, extracts status conditions (`Available`, `Degraded`, `Progressing`), applies `co_allow_list` exclusions, exports `co_all_operators`, `co_degraded`, `co_unavailable`, and `co_unhealthy_operators`, records structured result to `health_summary`, and enforces HARD gate (`fail:`) naming all degraded and unavailable operators.
  - `playbooks/roles/mcp/`: MachineConfigPool synchronization role. Queries `oc get mcp -o json` with jq v1.5 parsing, extracts pool conditions (`Updated`, `Updating`, `Degraded`), pause state (`spec.paused`), and machine counts, exports `mcp_parsed_data` and `mcp_all_pools` for direct consumption by `monitor` and `remediate` roles, records structured result to `health_summary`, and enforces HARD gate (`fail:`) naming offending pools.
  - `playbooks/roles/node/`: Node health and conditions evaluation role. Queries `oc get nodes -o json` with jq v1.5 parsing, verifies `Ready=True` across all nodes, detects `DiskPressure`, `MemoryPressure`, and `PIDPressure`, evaluates unschedulable nodes against `allowed_unschedulable_nodes` threshold (default: 0), exports `nodes_parsed_data` and offending node lists, records structured result to `health_summary`, and enforces HARD gate (`fail:`).
  - `playbooks/roles/etcd/`: Control-plane etcd database health verification role. Queries `oc get pods -n openshift-etcd -l app=etcd -o json` with jq v1.5 parsing to ensure all control-plane pods are Running and Ready, queries `oc get clusteroperator etcd -o json` for `Available=True` and `Degraded=False`, verifies HA quorum threshold (expected >= 3 pods), records structured result to `health_summary`, and enforces HARD gate (`fail:`).
  - Tested: Python-based YAML validation across all 12 files (defaults and tasks for all 6 roles), 100% named tasks (43 tasks total), zero deprecated parameters (`warn:`), zero bare `include:` statements, `executable: /bin/bash` with `pipefail` on all shell tasks, transient command retry loops on all `oc` tasks, mock verification of jq 1.5 expressions and data filtering, and end-to-end Jinja2 rendering test with `health-overview.j2` (17,030 bytes).

- [x] **Unit 08a: Auto-Remediation Engine (`remediate` Role)**:
  - `playbooks/roles/remediate/defaults/main.yml`: Default configuration, feature toggles (Tier 1 `auto_fix_cgroup_v2`, `auto_apply_admin_acks`, `auto_unpause_mcp` default `true`; Tier 2 `auto_restart_degraded_operators`, `auto_force_stalled_node` default `false`), `mcp_auto_unpause_list: ['worker', 'master']`, grace periods (`operator_restart_grace_seconds: 180`), and transient retry controls (`retries: 3 / delay: 10`).
  - `playbooks/roles/remediate/tasks/main.yml`: Master dispatcher. Verifies master `auto_remediation_enabled` switch, routes selectively via specific trigger flags (`trigger_*_remediation`) or sweeps all enabled remediation modules during prevalidation passes, and formats execution summaries.
  - `playbooks/roles/remediate/tasks/cgroup_v2.yml` (Blocker 1): Detects `cgroupMode: "v1"` via `nodes.config/cluster`, applies deterministic merge patch setting `spec.cgroupMode: "v2"`, re-verifies state via jsonpath, records `AUTO-FIXED` (or `FIX-FAILED`) to `health_summary`, appends audit details to `autofix_items`, and emits dual run logs (`.txt` and `.csv`).
  - `playbooks/roles/remediate/tasks/admin_acks.yml` (Blocker 2): Dynamically queries `ClusterVersion` conditions for `Upgradeable=False` and `reason: AdminAckRequired`, extracts ack keys matching `ack-[0-9]+\.[0-9]+-api-removals-in-[0-9]+\.[0-9]+`, ensures `openshift-config/admin-acks` ConfigMap exists, patches required keys to `true`, re-verifies ConfigMap contents, records `AUTO-FIXED` to `health_summary`, and emits dual audit logs.
  - `playbooks/roles/remediate/tasks/unpause_mcp.yml` (Blocker 3): Queries live MachineConfigPools, partitions paused pools against `mcp_auto_unpause_list`, unpauses permitted pools via JSON patch (`spec.paused: false`), re-verifies pool states, records `AUTO-FIXED` (or `WARN` for non-permitted pools) to `health_summary`, and emits dual audit logs.
  - `playbooks/roles/remediate/tasks/restart_operator.yml` (Blocker 4, Tier 2 Guided): Detects degraded ClusterOperators excluding allow-lists, resolves controller pods across namespaces, forces pod deletion with `wait: false`, pauses for `operator_restart_grace_seconds` reconciliation, re-verifies `Available=True` and `Degraded=False`, records outcome to `health_summary`, and emits dual audit logs.
  - Tested: Python-based YAML validation across all 6 files, 100% named tasks (84 tasks total), zero deprecated parameters (`warn:`), zero bare `include:`, shell tasks with pipefail declare `executable: /bin/bash`, regex key extraction verification, MCP partition testing, and end-to-end Jinja2 report rendering with `health-overview.j2` verifying `AUTO-FIXED` status pills and automated remediation callout cards.

- [x] **Unit 08: Capacity, Storage & Disruption Roles (`utilization`, `pv`, `pvc`, `pdb`)**:
  - `playbooks/roles/utilization/`: Cluster-wide node capacity headroom evaluation role. Queries allocatable CPU/memory across nodes and sum of resource requests across all running pods (`oc get pods -A --field-selector=status.phase=Running`). Implements strict **jq v1.5-compliant** calculations with custom rounding `def rnd2: . * 100 | floor / 100;`, compares against `max_cpu_percent: 90` and `max_memory_percent: 90` thresholds from `vars/upgrade.yml`, appends structured record to `health_summary`, and enforces a HARD gate (`fail:`) with detailed cores/GiB metrics to prevent node eviction deadlock during upgrade evacuation.
  - `playbooks/roles/pv/`: PersistentVolume health and phase verification role. Resiliently queries `oc get pv -o json` with jq v1.5 parsing, verifies all volumes are in `Bound` or `Available` phase, cleanly handles empty clusters without failing, surfaces `Failed` and `Released` volumes. Explicitly casts counts with `| int` to eliminate `AnsibleUnsafeText` type comparison crashes in Python 3. Enforced strictly as a non-blocking `WARN` advisory (`gate: WARN`, completely removed `fail:` task, never halts upgrade).
  - `playbooks/roles/pvc/`: PersistentVolumeClaim status verification role. Resiliently queries `oc get pvc -A -o json` with jq v1.5 parsing across all namespaces, verifies all claims are in `Bound` phase, cleanly handles empty clusters, surfaces `Pending` and `Lost` claims. Explicitly casts counts with `| int` to eliminate `AnsibleUnsafeText` type comparison crashes. Enforced strictly as a non-blocking `WARN` advisory (`gate: WARN`, completely removed `fail:` task, never halts upgrade).
  - `playbooks/roles/pdb/`: PodDisruptionBudget deadlock audit role. Resiliently queries `oc get pdb -A -o json` with jq v1.5 parsing, audits for zero-disruption budgets (`disruptionsAllowed == 0` and `expectedPods > 0`) that would permanently block node draining during MCP rollouts, ignores scaled-to-zero workloads (`expectedPods == 0`), surfaces offending budget namespaces and names, and enforces configurable gate (HARD if `fail_on_zero_disruption_pdb: true` is enabled, WARN otherwise).
  - `playbooks/roles/prevalidation/tasks/main.yml`: Suppresses `pv_enforce_gate: false` and `pvc_enforce_gate: false` in scan initialization, guaranteeing storage warnings never escalate to HARD gates during prevalidation.
  - `playbooks/vars/upgrade.yml`: Added explicit `pv_enforce_gate: false` and `pvc_enforce_gate: false` controls.
  - Tested: Python PyYAML validation across all 8 files, Jinja2 template rendering test with string-typed counts (`AnsibleUnsafeText` simulation), verified WARN gate exclusion from prevalidation hard gate filters, and 100% clean validation.

- [x] **Unit 09: Prevalidation Aggregator Role & Phase 02 (`prevalidation` Role, `02_Pre_upgrade_check.yaml`)**:
  - `playbooks/roles/prevalidation/defaults/main.yml`: Default thresholds, target version fallback resolution, gate suppression control, advisory warning switches (`preval_warn_on_pending_csrs`, `preval_warn_on_pod_crashloops`), and transient query retry settings with dual-version headers.
  - `playbooks/roles/prevalidation/tasks/main.yml`: Full implementation of the **14-check prevalidation contract** (Check 01: `co`, Check 02: `node`, Check 03: `mcp`, Check 04: `api_check`, Check 05: `api_readiness`, Check 06: `etcd`, Check 07: `admin_acks`, Check 08: `utilization`, Check 09: `csr`, Check 10: `pv`, Check 11: `pvc`, Check 12: `pdb`, Check 13: `critical_pods`, Check 14: `cgroup_mode`). Suppresses individual role gates during the initial scan to guarantee a complete 14-check evaluation, constructs structured records `{num, name, gate, status, observed}` into `health_summary`, and emits formatted terminal summaries. Fixed Jinja2 syntax error in Check 14 observed template (removed backslash-escaped quotes `\'` causing unexpected char lexer crashes on jump host).
  - `playbooks/02_Pre_upgrade_check.yaml`: Complete Phase 02 playbook with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`). Reuses authenticated session from Phase 01 (with fallback login), executes the 14-check scan via `prevalidation` role, evaluates initial HARD failures, dynamically executes the auto-remediation pass via `remediate` role (targeting CGroup v2, Admin-Acks, MCP unpausing, or degraded operator restart), evaluates residual HARD gates halting on persistent failures, generates client-facing HTML prevalidation report via `report` role (`output/<cluster>_prevalidation_<ts>.html`), emits dual `.txt` and `.csv` audit logs, and guarantees fail-safe session teardown on any failure via `block/rescue/always`.
  - Tested: Python PyYAML validation across all 3 files, dual-version header compliance audit, 100% named tasks, zero deprecated parameters (`warn:`), zero bare `include:` statements, `executable: /bin/bash` with `pipefail` on all shell tasks, transient command retry loops on all `oc` query tasks, simulated evaluation of all 4 inline checks (admin-acks, pending CSRs, critical namespace pods, cgroupMode compatibility across OpenShift 4.14–4.20), auto-remediation and residual gate lifecycle verification, and end-to-end Jinja2 report rendering with `health-overview.j2` (23,205 bytes) displaying all 14 checks and automated remediation callout cards.

- [x] **Unit 10: Upgrade Role, Per-Hop Task (`tasks/hop.yml`) & Phase 03 Playbook (`03_Initiate_upgrade.yaml`)**:
  - `playbooks/roles/upgrade/defaults/main.yml`: Default parameters (`target_version`, `target_channel`, `target_channel_prefix: stable`, `allow_force_upgrade: false`, `force_image_pullspec`, `force_upgrade_confirm_token`, transient command retry settings) with dual-version headers.
  - `playbooks/roles/upgrade/tasks/main.yml`: Upgrade driver role. Implements semantic regex parsing for major.minor prefix extraction (`target_major_minor`), dynamic upgrade channel resolution (`resolved_target_channel`), channel updating (`oc adm upgrade channel`), edge re-verification with retries against live `availableUpdates` and `conditionalUpdates`, dynamic administrator acknowledgement check via `admin_acks.yml`, safety guard requiring explicit `CONFIRM_FORCE_UPGRADE` token for `--force` emergency upgrades, and single cluster mutation trigger via `oc adm upgrade --to={{ target_version }}` (with dry-run simulation support).
  - `playbooks/tasks/hop.yml`: The per-hop sequence task driven per item in `upgrade_path`. Implements 7-step sequence: (1) hop metadata computation (`hop_number`, `hop_total`, `hop_label`), (2) hop start banner and dual `.txt`/`.csv` logging, (3) pre-hop settle assertion (verifying cluster is stable, unblocked, not actively updating, and has zero degraded MCPs/COs), (4) `roles/upgrade` execution with pre-computed facts, (5) hand-off to live monitoring (`04_Live_monitoring_upgrade.yaml`), (6) settle-gate verification (asserting clusterversion at target, Available=True, Progressing=False, zero degraded/progressing/unavailable COs, and all MCPs Updated=True), (7) hop completion notification dispatch via `sendmail` with Prevalidation HTML audit report attached and dual `.txt`/`.csv` logging. Full `block/rescue` with hierarchical error extraction, RBAC error detection, alert dispatch via `error_handle`, and guaranteed session logout.
  - `playbooks/04_Live_monitoring_upgrade.yaml`: Phase 04 tasks file entrypoint with dual-version headers, displaying live monitoring configuration and handing off to `roles/monitor` when present.
  - `playbooks/03_Initiate_upgrade.yaml`: Phase 03 playbook with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`). Reuses authenticated session from Phase 01/02 (with login fallback), ingests all 6 `vars/` files, validates non-empty `upgrade_path`, sequentially executes minor-version upgrade hops via `tasks/hop.yml` using `include_tasks:` with `loop: "{{ upgrade_path }}"`, and encloses execution in `block/rescue/always` with fail-safe error handling and guaranteed session logout.
- [x] **Unit 11: Live Monitoring & Settle-Gate (`monitor` Role, `04_Live_monitoring_upgrade.yaml`)**:
  - `playbooks/roles/monitor/defaults/main.yml`: Default monitoring parameters (`poll_interval_minutes: 2`, `hop_timeout_minutes: 90`, `heartbeat_minutes: 20`, `auto_force_stalled_node: false`, `node_stall_threshold_minutes: 30`, `monitor_enforce_gate: true`, `dry_run: false`, `oc_command_retries: 3`, `oc_command_retry_delay: 10`, `co_allow_list: []`, `heartbeat_subject_prefix: "[ARO Upgrade]"`, `mail_to: []`, hop context defaults) with dual-version headers.
  - `playbooks/roles/monitor/tasks/main.yml`: Master driver for live monitoring. Validates non-empty target version, initializes start epochs and state signatures, displays initiation banner, logs start to `.txt` run log, drives bounded polling loop (`range(1, max_iterations)`) via `include_tasks: poll_iteration.yml`, enforces HARD hop timeout guard (`fail:`) if loop concludes without settling, displays settle-gate verification banner on pass, exports `hop_settled`, `settle_gate_passed`, and `hop_elapsed_duration` facts for downstream notifications, and emits dual `.txt` and `.csv` audit logs.
  - `playbooks/roles/monitor/tasks/poll_iteration.yml`: Single poll iteration task file. Implements dry-run simulation mode, computes elapsed duration, queries live `clusterversion`, `mcp`, `clusteroperators`, and `nodes` via `oc get ... -o json` with jq v1.5 parsing, calculates rollout progress percentage across control plane and worker MCPs, detects state changes vs previous poll signature, dispatches notification email via `sendmail` with `progress-mail.j2` on state change or 20-min heartbeat cadence, detects single active updating nodes stalled exceeding `node_stall_threshold_minutes` and executes Tier 2 auto-remediation (`oc debug node/<node> -- chroot /host touch /run/machine-config-daemon-force`), evaluates strict settle-gate conditions (CV at target with Available=True, Progressing=False, and history Completed; all COs healthy; all MCPs updated), and sleeps `poll_interval_minutes * 60` seconds before next iteration only when not settled.
  - `playbooks/04_Live_monitoring_upgrade.yaml`: Phase 04 task playbook entrypoint with dual-version headers. Displays live monitoring banner, normalizes hop context facts (`hop_target_version`, `hop_label`, `hop_number`, `hop_total`), logs initiation to text run log, invokes `roles/monitor` via `include_role`, and logs completion.
  - `playbooks/tasks/hop.yml`: Integrated `elapsed_time` and `percent_complete` into hop completion notification facts for full template compatibility with `progress-mail.j2`.
  - Tested: Python PyYAML syntax validation across all 5 files, dual-version header compliance audit, 100% named tasks (82 tasks total), zero deprecated parameters (`warn:`), zero bare `include:` statements, `executable: /bin/bash` with `pipefail` on all shell tasks, transient command retry loops on all `oc` tasks, and end-to-end Jinja2 template rendering tests for `progress-mail.j2` across in-progress, state-change with degraded nodes, and hop-complete states.

- [x] **Unit 12: Postvalidation Role & Phase 05 Playbook (`postvalidation` Role, `05_post_Upgrade_Checks.yaml`)**:
  - `playbooks/roles/postvalidation/defaults/main.yml`: Default parameters (`baseline_snapshot_file`, `final_target_version`, `postval_enforce_gate: true`, `co_allow_list: []`, `allowed_unschedulable_nodes: 0`, `oc_command_retries: 3`, `oc_command_retry_delay: 10`) with dual-version headers.
  - `playbooks/roles/postvalidation/tasks/main.yml`: Full implementation of the **10-check postvalidation contract**:
    - Check 01: Final ClusterVersion (`cv` matches `final_target_version`, `Available=True`, `Progressing=False`, `Degraded=False`) — HARD gate.
    - Check 02: ClusterOperators Status (all operators `Available=True`, `Degraded=False`, `Progressing=False`, allow-list exclusions) — HARD gate.
    - Check 03: MachineConfigPool Status (all pools `Updated=True`, `Updating=False`, `Degraded=False`) — HARD gate.
    - Check 04: Node Readiness & Version (all nodes `Ready=True`; kubelet versions derived from target minor `1.(Y+13)` e.g. `v1.29.*` for OCP 4.16) — HARD gate.
    - Check 05: Node Pressures (zero `DiskPressure`, `MemoryPressure`, `PIDPressure`; unschedulable threshold check) — HARD gate.
    - Check 06: etcd Cluster Health (>= 3 control-plane pods Running/Ready, `co/etcd` Available=True & Degraded=False) — HARD gate.
    - Check 07: PersistentVolume Status (all storage volumes in `Bound` or `Available` phase) — WARN gate.
    - Check 08: Core Namespace Pods (`openshift-*` platform pods free of CrashLoopBackOff/Error) — WARN gate.
    - Check 09: Firing Critical Alerts (Prometheus API queried for active firing critical alerts) — WARN gate.
    - Check 10: **Baseline Diff Audit** (ingests Phase 01 baseline snapshot via `slurp`/`from_json`, queries live nodes, operators, and routes, and verifies parity or surfaces missing items) — WARN gate.
  - `playbooks/05_post_Upgrade_Checks.yaml`: Complete Phase 05 playbook with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`). Connects to localhost, ingests all 6 `vars/` files, reuses existing authenticated session from previous phases (fallback login check), executes 10-check postvalidation contract and baseline diff via `roles/postvalidation`, generates client-facing HTML postvalidation report via `roles/report` (`output/<cluster>_postvalidation_<ts>.html`), emits dual `.txt` and `.csv` audit logs, preserves the authenticated session on success for Phase 06 operator upgrades, and guarantees fail-safe session logout on any failure via `block/rescue/always`.
  - Tested: Python PyYAML validation across all 3 files, dual-version header compliance audit, 100% named tasks (37 tasks total), zero deprecated parameters (`warn:`), zero bare `include:` statements, `executable: /bin/bash` with `pipefail` on all shell tasks, transient command retry loops on all `oc` tasks, mock verification of all 10 checks including kubelet version prefix derivation and baseline diff comparisons, and end-to-end Jinja2 report rendering with `health-overview.j2` (19,731 bytes).

- [x] **Unit 13: Operator Lifecycle Roles & Phase 06 Playbook (`operator_compat`, `operator_upgrade`, `operator_validate`, `06_Operator_Upgrade.yaml`)**:
  - `playbooks/roles/operator_compat/`: Compatibility scan role. Resiliently queries all installed OLM `Subscription` resources (`oc get subscriptions.operators.coreos.com -A -o json`), inspects `PackageManifest` across source namespaces, parses available update channels matching the target OpenShift minor version prefix (e.g. `stable-4.16`, `fast-4.16`, or `4.16`), builds `operator_compat_plan`, handles empty clusters cleanly, and exposes compatibility findings.
  - `playbooks/roles/operator_upgrade/`: Manual InstallPlan approval and CSV rollout role. Discovers unapproved manual InstallPlans (`spec.approved == false`), sequentially approves each via deterministic merge patch (`oc patch installplan <name> -n <ns> --type=merge -p '{"spec":{"approved":true}}'`), monitors CSV rollout in a bounded loop calculated from `operator_upgrade_timeout_seconds // operator_upgrade_poll_interval_seconds` (default: 600s / 15s = 40 iterations), and implements **Tier 2 one-shot recovery** deleting failed/stalled CSVs once (`oc delete csv <name> -n <ns>`) to trigger OLM subscription reconciliation.
  - `playbooks/roles/operator_validate/`: Post-upgrade operator health validation role. Asserts that all installed subscriptions reference valid installed CSVs, confirms all active CSVs report `phase: Succeeded`, generates client-facing HTML report via `roles/report` (`output/<cluster>_operators_<ts>.html`) with subscription namespaces, installed CSVs, target channels, approval modes, and status pills, and enforces HARD gate halting on unrecovered failures.
  - `playbooks/06_Operator_Upgrade.yaml`: Complete Phase 06 playbook with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`). Ingests all 6 `vars/` files, verifies/establishes cluster session in `pre_tasks:`, executes all 3 operator roles, resolves all 4 core audit attachments (prevalidation, postvalidation, operators, run log), dispatches the final Upgrade-Complete digest email via `roles/sendmail` with `progress-mail.j2` displaying `ALL PHASES COMPLETE ✔`, and executes definitive terminal session logout via `roles/logout` in both success and rescue branches.
  - `playbooks/main.yml`: Orchestrator imports un-commented for all five phase entrypoint playbooks (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`).
  - Tested: Python PyYAML validation across all 12 files (71 tasks total, 100% named, 0 deprecations, 0 bare `include:`, 0 `ansible_failed_task.name`), Jinja2 rendering tests for `progress-mail.j2` (13,743 bytes) and `health-overview.j2` (16,292 bytes), and bash syntax validation (`bash -n`).
- [x] **Unit 14: Master Wiring & End-to-End Integration (`main.yml`)**:
  - `playbooks/main.yml`: Master orchestrator wired with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`) and migration comments. Sequential chaining across all five phase entrypoint playbooks (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`).
  - **Input Validation & Initialization**: Ingests all 6 `vars/` files (`vars/upgrade.yml`, `vars/secrets.yml`, `vars/paths.yml`, `vars/smtp.yml`, `vars/report_vars.yml`, `vars/api_regex.yml`), asserts non-empty `cluster_name` and `upgrade_path`, and displays 1-touch initialization debug banner.
  - **Dry-Run Intercept & Early Teardown**: Dedicated localhost intercept play following Phase 02 (`when: dry_run | default(false) | bool`). Logs dry-run completion, teardowns authenticated session via `roles/logout`, and cleanly terminates playbook execution via `meta: end_play`. Downstream mutation phases (03, 05, 06) are protected with `when: not (dry_run | default(false) | bool)`.
  - **Selective Execution (`skip_to_phase`)**: Enforces `(skip_to_phase | int) <= N` guards on all phase imports, permitting recovery or targeted executions directly into Phase 02, 03, 05, or 06 without triggering prior phases.
  - Tested: Python PyYAML syntax verification, 100% named tasks (6 tasks across 2 plays), 0 deprecations, dry-run intercept logic audit, selective phase evaluation matrix (scenarios for full-run, dry-run, skip-to-05, skip-to-06), `bash -n` validation of CLI entrypoint, and mock dry-run and `--skip-to-phase` execution flows via `00_Run.sh` (exit code 0).

- [x] **Unit 15: Exception Handling & Error Extraction Patterns (Cross-Cutting Specification)**:
  - Standardized hierarchical error extraction cascade (`ansible_failed_result.stderr` -> `ansible_failed_result.stderr_lines` -> `ansible_failed_result.msg` -> fallback) across all 6 rescue blocks (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `tasks/hop.yml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`) and `roles/error_handle`.
  - Implemented comprehensive OpenShift RBAC & authorization error detection (`is_rbac_error`) detecting `forbidden`, `cannot patch`, `unauthorized`, `cannot get`, `cannot list`, and `cannot create` across all rescue blocks and `roles/error_handle`.
  - Enforced fail-safe teardown invariant: guaranteed cluster session token revocation and kubeconfig removal by invoking `logout` role with `failed_when: false` in both `rescue:` and `always:` blocks across all phase playbooks.
  - Eliminated Jinja2 self-referencing variable passes: all facts (`current_step_no`, `current_task_name`, `current_gate_type`, `failure_reason`, `failure_observed`, `resolved_error`, `is_rbac_error`, `phase_XX_failed: true`) are pre-computed via `set_fact` before invoking `error_handle` or `logout`.
  - Verified zero `ansible_failed_task.name` references across all roles/playbooks to prevent non-serializable `FieldAttribute` crashes.
  - Verified 100% of `oc` shell tasks using pipes specify `args: executable: /bin/bash` with `set -o pipefail`.
  - Tested: Python automated validation across all 6 verification checklist criteria (100% pass), 100% PyYAML syntax validation across all playbooks/roles, Jinja2 rendering tests for `error-report.j2` (standard and RBAC modes), and `bash -n` syntax validation.

- [x] **CLI Interactive Menu & Terminal Geometry Fix (`scripts/cli_helpers.sh`, `00_Run.sh`)**:
  - **ANSI Escape Codes Resolution**: Switched all terminal color variables (`C_RESET`, `C_BOLD`, `C_GREEN_BOLD`, etc.) from double-quoted strings (`"\033[...m"`) to Bash ANSI-C quoting (`$'\033[...m'`), ensuring genuine escape bytes (0x1B) are outputted and eliminating raw escape code rendering in menus.
  - **Loop Index Scoping Fix**: Declared `local i` and scoped loop variables across all box drawing and menu functions (`render_menu`, `draw_box_row`, `draw_box_header`, `draw_box_divider`, `draw_box_footer`, `draw_horizontal_line`), resolving the global `i` pollution bug that prematurely aborted menu rendering and omitted option 3 (`cluster_p01`).
  - **Fast Row Padding**: Replaced slow string concatenation loops with `printf -v padding "%*s" "$pad_len" ""` guaranteeing instant O(1) padding with zero loop collisions.
  - **Box Geometry Correction**: Corrected header embellishment padding offset (`total_title_len=$((title_len + 6))` for `" [ "` and `" ] "`), ensuring exact 72-column alignment across top header, content rows, dividers, and bottom border.
  - **Subprocess-Free ANSI Stripping**: Implemented pure-Bash regex pattern removal in `strip_ansi` and `visible_length`, stripping both genuine ANSI escape sequences and literal strings with zero `sed` subprocess fork overhead.
  - **Terminal Compatibility & ASCII Fallback**: Auto-normalizes locale to `C.UTF-8` if unset, and provides clean 72-column ASCII fallback (`+`, `-`, `|`, `* (Default)`) when `ARO_CLI_ASCII=true` or terminal locale lacks UTF-8.
  - **Clean `return 0` & `MENU_CHOICE` Export**: Replaced error-prone `return "$choice"` with clean `return 0` in `render_menu`, directly exporting single-word fact `MENU_CHOICE`. Eliminated complex parameter expansion `${MENU_SELECTED_INDEX:-$SELECTED_CHOICE}` which threw `bad substitution` when double underscores were converted to spaces/italics during copy-paste.
  - **Tested**: 6-part automated verification test suite + full 3-menu simulated interactive test (Cluster, Path, Mode) running under `set -euo pipefail` (100% pass).

- [x] **Ansible IncludeRole Syntax & Phase 06 Block Indentation Fix (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`, `tasks/hop.yml`)**:
  - **IncludeRole Attribute Fix**: Removed `failed_when: false` from all 11 `include_role: name: logout` tasks across all 5 playbooks and `tasks/hop.yml`. The `logout` role tasks internally already enforce `failed_when: false` on every task (`oc logout` and file removal), guaranteeing safe, un-masking teardown without illegal task-level syntax attributes.
  - **Phase 06 Block Indentation Fix (`06_Operator_Upgrade.yaml`)**: Corrected indentation of `always:` section from 2 spaces (which caused Ansible to treat it as an invalid play-level attribute `ERROR! 'always' is not a valid attribute for a Play`) to 6 spaces, properly embedding it within the main tasks `block:`/`rescue:` structure. Indented child tasks to 8 spaces.
  - **Standalone `upgrade_path` Guards (`06_Operator_Upgrade.yaml`)**: Guarded `upgrade_path[-1]` in banner, email params, and CSV logging with conditional length checks (`upgrade_path[-1] if (upgrade_path is defined and upgrade_path | length > 0) else ...`), preventing `IndexError: list index out of range` when running Phase 06 standalone with default empty list `upgrade_path: []`.
  - **Tested**: Automated Python validation verified 0 illegal attributes across all playbooks/tasks, PyYAML syntax check validated 100% pass across all 6 files, and Jinja rendering test passed in both standalone and populated contexts.

- [x] **Prevalidation Contract Residual HARD Gate Fix (Checks 06, 12, and 14)**:
  - **Check 06 (etcd Health Type Normalization)**: Fixed Jinja2 type mismatch in `roles/etcd/tasks/main.yml` where `etcd_co_available == 'True'` evaluated `True == 'True'` to `False`. Normalized status with `| string | trim | lower == 'true'` and evaluated quorum validity using `(etcd_co_available | bool)` and `(not (etcd_co_degraded | bool))`.
  - **Check 12 (PDB Gate Alignment & System Namespace Filtering)**: Reset default `fail_on_zero_disruption_pdb: false` in `vars/upgrade.yml` and `roles/pdb/defaults/main.yml`, aligning with the 14-Check Prevalidation Contract specification (non-blocking `WARN` advisory). Added `pdb_ignore_system_namespaces: true` in `roles/pdb/tasks/main.yml` to filter out `openshift-*` and `kube-*` namespaces (e.g. Loki logging) if strict gate is ever enabled.
  - **Check 14 (CGroup Mode Compatibility & Non-Admin / ARO Support)**:
    - **Target Version Gating**: If target version is `< 4.19`, cgroupMode v2 is not required; Check 14 evaluates `PASS` and skips auto-remediation cleanly.
    - **Skip Toggle (`skip_cgroup_check`)**: Added `skip_cgroup_check: false` in `vars/upgrade.yml` and `--skip-cgroup` flag in `00_Run.sh` to allow operators to completely bypass Check 14 validation and remediation.
    - **Advisory Gate Policy (`cgroup_enforce_gate`)**: Defaulted `cgroup_enforce_gate: false` so cgroupMode v1 status surfaces as a non-blocking `WARN` advisory rather than halting upgrades at the HARD gate.
    - **RBAC Error Handling**: In `roles/remediate/tasks/cgroup_v2.yml`, detected cluster-scope patch authorization failures (`is_rbac_error`: `forbidden` / `cannot patch`). Instead of failing with `FIX-FAILED`, downgraded status to `WARN` with a clear explanation: user account lacks cluster-scoped patch permission on `nodes.config/cluster`, and managed cluster infrastructure will control node rollout.
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
  - **Tested**: YAML syntax validation of all 6 operator task files, Python `from_json` resilience test covering empty, single, multi-line, and whitespace edge cases (exit code 0).

- [x] **Phase 06 Operator Mutation Bypass & Validation-Only Control (`skip_operator_upgrade`, `06_Operator_Upgrade.yaml`, `00_Run.sh`, `vars/upgrade.yml`)**:
  - **Operator Mutation Bypass Guard**: Added `skip_operator_upgrade: false` in `playbooks/vars/upgrade.yml` and `roles/operator_upgrade/defaults/main.yml`. Guarded Step 2 in `playbooks/06_Operator_Upgrade.yaml` with `when: not (skip_operator_upgrade | default(false) | bool)` and added explicit informational notification when bypassed.
  - **Non-Mutating Validation-Only Mode**: Allows operators to execute Phase 06 to scan version compatibility (`roles/operator_compat`), bypass manual `oc patch installplan` mutations (preventing RBAC 403 Forbidden halts on restricted namespaces such as `openshift-lightspeed`), execute full health validation and HTML report generation (`roles/operator_validate`), and deliver the final Upgrade-Complete email digest with all 4 audit attachments.
  - **CLI Flag Integration (`00_Run.sh`)**: Exposed `--skip-operator-upgrade` flag in `playbooks/00_Run.sh` and routed it through the Python extra-vars JSON assembly script.
  - **Phase 06 Exit Code Mapping (`00_Run.sh`)**: Added `Exit Code 35: Operator Upgrade / Validation Failed (Phase 06)` and placed Phase 06 log inspection regex evaluation before Phase 05 checks to prevent misleading attribution in the post-run CLI execution summary table.

- [x] **Phase 06 Consolidated Operator Failure Notification & Attached HTML Report (`06_Operator_Upgrade.yaml`, `error_handle`, `error-report.j2`)**:
  - **Fail-Safe Operator Report Generation on Failure**: Added check and fail-safe execution of `roles/operator_validate` (`operator_validate_enforce_gate: false`) within `06_Operator_Upgrade.yaml`'s rescue block. Guarantees that `output/<cluster>_operators_<ts>.html` is generated on disk even if failure occurred early during `roles/operator_upgrade` (e.g. InstallPlan RBAC error or CSV settle timeout).
  - **Consolidated Audit Attachments on Failure**: Gathers all available audit reports (`operators_<ts>.html`, `postvalidation_<ts>.html`, `prevalidation_<ts>.html`, run log) into `mail_attachments` and `attached_reports`.
  - **User Recipient Routing & Subject Personalization**: Updated `error_handle` to merge `mail_to` (the operator/user who ran the playbook or passed via `--mail-to`) and `alert_mail_to`, ensuring the user receives the failure notification. Sets customized subject: `[ARO Upgrade ALERT] Phase 06 Operator Failure — <cluster>`.
  - **Email Template Visualization (`error-report.j2`)**: Added "Attached Diagnostic Reports" callout section in `error-report.j2` displaying all attached audit artifacts alongside diagnostic details, error outputs, and RBAC remediation guidance.
  - **SMTP Resilience**: Wrapped failure alert email dispatch in `block/rescue` within `error_handle` to ensure SMTP relay errors never prevent subsequent session logout and cluster teardown.

- [x] **Dry-Run Multi-Report Email Dispatch & Validation Lifecycle Enhancements (`main.yml`, `02_Pre_upgrade_check.yaml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`, `progress-mail.j2`, `00_Run.sh`, `vars/smtp.yml`, `vars/upgrade.yml`)**:
  - **Comprehensive Multi-Attachment Email Dispatch**: Replaced interim single-report email during dry run with a unified, multi-attachment validation digest dispatched upon workflow completion. Uses an automated disk audit via Ansible `stat` loop across `_phase01_*.html`, `_prevalidation_*.html`, `_postvalidation_*.html`, and dual `.txt` / `.csv` run logs, dynamically attaching all generated artifacts for the run timestamp.
  - **Full Non-Mutating Validation Suite (`dry_run_include_postval`)**: Enabled Dry Run mode to execute Phase 01 (Policy Check), Phase 02 (15-Check Prevalidation), and Phase 05 (Postvalidation / Cluster Health Audit & Baseline Diff in read-only mode targeting `'current'` cluster version) with zero mutating operations, skipping only Phase 03/04 (Upgrade Initiation/Monitoring) and Phase 06 InstallPlan mutations. Generates all 3 HTML reports for complete 360-degree cluster health validation.
  - **Phase 05 Dry-Run Advisory Audit Mode (`postval_enforce_gate: false`)**: Resolved Exit Code 25 false-positive failure on live clusters where non-critical operators (e.g. `image-registry`) are in `Progressing=True` state. In `05_post_Upgrade_Checks.yaml`, dynamically set `postval_enforce_gate: false` and `final_target_version: "current"` when `dry_run` is enabled, treating Phase 05 as an advisory health & baseline diff audit. Added `postval_enforce_gate: true` default in `vars/upgrade.yml`.
  - **Fact Isolation & Rescue Report Resilience**: Cleared `report_file_path: ""` at the start of Phase 05 to eliminate state bleeding from Phase 02 facts, guaranteeing that postvalidation HTML reports generate cleanly even on rescue. Updated run logs and completion banner to dynamically report passed, warning, and failed check counts without hardcoding `Failed: 0`.
  - **Email Consolidation & Interim Suppression**: In `02_Pre_upgrade_check.yaml`, suppressed interim single-attachment email during dry-run mode (`when: ... and not (dry_run | bool)`), routing delivery cleanly to the terminal Dry-Run Intercept play in `main.yml` to prevent duplicate emails.
  - **Email Template Visualization (`progress-mail.j2`)**: Enhanced `progress-mail.j2` with dedicated `is_dry_run` presentation mode featuring `DRY RUN VALIDATION COMPLETE ✔` badge, dry-run validation callout box, and an interactive "Attached Audit Reports & Logs" table categorizing each artifact by type and purpose with `ATTACHED ✔` status pills.
  - **Configuration & CLI Integration**: Added `dry_run_mail_to`, `dry_run_subject_prefix: "[ARO Upgrade DRY-RUN]"`, and `send_dry_run_email: true` in `vars/smtp.yml`; added `dry_run_include_postval: true` in `vars/upgrade.yml`. Updated `00_Run.sh` to map CLI `--mail-to` overrides to `dry_run_mail_to` and updated `render_post_run_summary` to display Phase 01 Policy Check HTML reports.
  - **Full Upgrade Attachment Parity**: Updated Phase 06 (`06_Operator_Upgrade.yaml`) to audit and attach `_phase01_` Policy Check HTML report and `.csv` run log alongside prevalidation, postvalidation, operator report, and text log.
  - **Tested**: Verified with Python YAML syntax validator across all modified YAML files, simulated postvalidation execution with `postval_enforce_gate: false`, Jinja2 template rendering tests for dry run, simulated attachment discovery (5/5 discovered), and Bash syntax validation (`bash -n`) on `00_Run.sh` and `cli_helpers.sh` (exit code 0).

---

- [x] **Unit 16: Developer Comments & Documentation Standards (Cross-Cutting Specification)**:
  - **Standardized File Header Blocks**: Applied the 6-field standardized header schema (`Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)`, `MIGRATION 2.14:`, `Purpose:`, `Role / Playbook Dependencies:`, `Gate Type:`, `Outputs:`) across all 71 YAML files and bash entrypoint/library scripts.
  - **Jinja2 Presentation Template Documentation**: Prepend structured Jinja2 comment blocks (`{# ... #}`) across all 3 presentation templates (`error-report.j2`, `progress-mail.j2`, `health-overview.j2`) declaring target rendering context (Email vs Standalone HTML), inbound fact dependencies, and layout/accessibility constraints (max-width 580px/1080px, Outlook/MIME compatibility, WCAG AA contrast).
  - **Role Defaults Variable Documentation (`defaults/main.yml`)**: Fully standardized all 24 role defaults files so that 100% of variables define explicit data type annotations (`(string, mandatory)`, `(integer)`, `(boolean)`), operational purposes, and override source references (`Sourced from vars/upgrade.yml`, `Sourced from CLI`).
  - **Task-Level Inline `# Why:` Logic Comments**: Added explanatory `# Why:` annotations across all 53 shell tasks utilizing `set -o pipefail` (explaining `/bin/bash` requirement over default Debian dash), jq 1.5 workarounds (custom `rnd2` rounding avoiding lexer collisions), and Kubernetes bracket queries `['items']`.
  - **Rescue Block Commentary**: Documented the 3-point exception contract above all `rescue:` blocks across phase playbooks (`01`–`06`, `hop.yml`, and `roles/error_handle`): (1) error extraction cascade (`stderr` -> `stderr_lines` -> `msg` -> fallback), (2) alerts dispatched (email and dual run logs), and (3) teardown guarantees via `always:` or inline logout.
  - **Tested**: Comprehensive 8-point automated verification suite (`scratch/verify_unit16.py`) validating 100% header compliance across 71 files, 100% named tasks, 100% why comments, 100% variable annotations, 100% template headers, 100% rescue documentation, PyYAML syntax validation, and Jinja2 rendering tests (100% pass).

- [x] **Dry-Run / Pre-Check Intercept Session Teardown & Kubeconfig Path Resolution (`main.yml`, `logout`, `login`, `00_Run.sh`)**:
  - **Play-Level Variable Scope Resolution (`main.yml`)**: Added complete `vars_files:` list (`vars/upgrade.yml`, `vars/secrets.yml`, `vars/paths.yml`, `vars/smtp.yml`, `vars/report_vars.yml`, `vars/api_regex.yml`) to the standalone intercept plays `Prevalidation / Dry-Run Intercept & Early Teardown` and `Post-Check Intercept & Early Teardown` in `playbooks/main.yml`. Eliminates undefined variable errors (`'kubeconfig_path' is undefined`) across Ansible play boundaries.
  - **Role Defaults Variable Alignment (`logout`, `login`)**: Added `kubeconfig_path` alongside `cluster_kubeconfig` in `roles/logout/defaults/main.yml` and `roles/login/defaults/main.yml`, ensuring both names resolve identically. Added `oc_binary: "oc"` to logout defaults.
  - **Defensive Default Fallbacks in Tasks**: Updated `roles/logout/tasks/main.yml` and `roles/login/tasks/main.yml` to use `{{ kubeconfig_path | default(cluster_kubeconfig | default(playbook_dir ~ '/.kubeconfig-' ~ (cluster_name | default('default')))) }}`, ensuring fail-safe execution even when invoked in isolation.
  - **Host-Fact Exporting**: Exported `kubeconfig_path` as a host fact on `localhost` in `roles/login/tasks/main.yml` alongside `cluster_kubeconfig`, guaranteeing multi-play fact persistence.
  - **Timestamp Synchronization (`00_Run.sh`)**: Moved `TIMESTAMP=$(date +"%Y%m%d_%H%M%S")` before extra-vars generation in `00_Run.sh` and injected `"run_timestamp": run_timestamp` into the JSON payload. Eliminates 5-second drift between CLI and Ansible, ensuring HTML report filenames generated on disk match the paths evaluated in `render_post_run_summary`.
  - **Tested**: Verified with Python YAML safe loader across all modified files and AST validation of embedded Python in `00_Run.sh` (all clean).

- [x] **OpenShift CLI Login Syntax & Argument Quoting Resolution (`roles/login/tasks/main.yml`)**:
  - **Resolved Exit Code 2 (Cobra Usage / Syntax Error)**: Identified that `shell: |` bash block with positional argument `"{{ cluster_api_url }}"` placed between flags violated Cobra's `oc login [URL] [flags]` specification, triggering `len(args) > 1` and `Only the server URL may be specified as an argument` usage error.
  - **Eliminated Bash Shell Expansion**: Replaced `shell: |` with native Ansible `command:` module utilizing `argv:` list syntax. In Ansible 2.7+ and 2.14+, `argv:` bypasses shell invocation completely via `execve()`, preventing Bash variable expansion (`$`), quote escaping issues, and whitespace argument splitting on passwords containing special characters.
  - **Strict Positional Ordering**: Positioned `{{ cluster_api_url }}` as the immediate first positional argument directly following `"login"`, guaranteeing strict adherence to Cobra CLI conventions and `len(args) == 1`.
  - **Sanitized Diagnostic Surfacing**: Enhanced `TASK [login : Validate login success]` to surface `oc_login_result.stderr` (falling back to `stdout`) protected by dynamic password masking `| replace(cluster_password, '******')`, ensuring operators receive full error clarity on any connectivity, TLS, or authentication issue without leaking credentials.
- [x] **Logout Role Kubeconfig Path Resolution & Template Syntax Fix (`roles/logout/tasks/main.yml`)**:
  - **Resolved Jinja2 Syntax Error (`unexpected ')'`)**: Identified that an unbalanced nested Jinja2 filter on line 23 contained an extra closing parenthesis (`default(playbook_dir ~ '/.kubeconfig-' ~ (cluster_name | default('default'))))`), causing Jinja2 to abort during task compilation with `unexpected ')'`.
  - **Explicit Fact Resolution (`logout_kubeconfig`)**: Introduced dedicated `Resolve target kubeconfig path for teardown` task at the start of `roles/logout/tasks/main.yml` to resolve `logout_kubeconfig` safely across `kubeconfig_path`, `cluster_kubeconfig`, and `cluster_name` fallbacks.
  - **Simplified Command & File Invocations**: Refactored token revocation (`command: "{{ oc_binary | default('oc') }} logout --kubeconfig={{ logout_kubeconfig }}"`) and file removal (`file: path: "{{ logout_kubeconfig }}" state: absent`) to reference the clean fact, eliminating nested parenthesis traps.
- [x] **Unit 17: Verification & Testing Standards (Cross-Cutting Specification)**:
  - **Suite 1: Dual-Version Syntax & AST Validation**:
    - Audited all 71 YAML files across the codebase (7 process playbooks, 6 variable files, 24 role defaults, all task files).
    - 100% PyYAML syntax validation pass.
    - 456/456 tasks (100%) uniquely named with descriptive labels.
    - 71/71 files verified with standardized 6-field dual-version headers (`Targets: Ansible 2.7.17 / 2.14.18`).
    - 0 instances of deprecated/removed `warn:` parameter across all plays and tasks.
    - 0 bare `include:` statements (all inclusions use `include_tasks:`, `import_tasks:`, or `include_role:`).
    - 0 instances of illegal `ansible_failed_task.name` references in rescue blocks or error handlers.
    - 71 shell tasks using pipes or `set -o pipefail` explicitly declare `args: executable: /bin/bash`.
    - All `oc` CLI query and mutation tasks implement transient retry loops (`retries: 3 / delay: 10`).
  - **Suite 2: jq v1.5 Compatibility Tests**:
    - Audited 56 jq pipelines across playbooks, tasks, and bash helper scripts.
    - Verified 0 bare `round` expressions (zero modern jq 1.6+ built-ins).
    - Verified custom rounding function definition adheres strictly to jq 1.5 syntax (`def rnd2: . * 100 | floor / 100;`).
    - Verified parenthesized logical expressions for all conditional operands.
    - Mock JSON data transformation verified against live cluster schemas (`ClusterVersion`, `ClusterOperator`, `Node`, `MachineConfigPool`).
  - **Suite 3: Jinja2 Type & Templating Checks**:
    - Audited bracket notation: 0 unbracketed `.items` access in Jinja2 (bracket notation `['items']` enforced throughout).
    - Audited condition string normalization: 0 non-normalized boolean string comparisons in `when:` statements.
    - Full template rendering verified across all 3 presentation templates:
      - `error-report.j2`: Rendered successfully (13,083 bytes) with RBAC remediation commands and attached reports.
      - `progress-mail.j2`: Rendered successfully (14,799 bytes) with MachineConfigPool status table, active node tracking, and settle-gate banner.
      - `health-overview.j2`: Rendered successfully (15,038 bytes) with 14-check prevalidation contract, `AUTO-FIXED ⚙` badges, and auto-remediation callouts.
  - **Suite 4: Auto-Remediation Toggle Testing**:
    - Verified all 6 feature toggles in `roles/remediate/defaults/main.yml` and `vars/upgrade.yml`: master toggle (`auto_remediation_enabled: true`), Tier 1 auto-fixes (`auto_fix_cgroup_v2: true`, `auto_apply_admin_acks: true`, `auto_unpause_mcp: true`), and Tier 2 guided remediations (`auto_restart_degraded_operators: false`, `auto_force_stalled_node: false`).
    - Verified conditional routing logic across 8 dispatch tasks in `roles/remediate/tasks/main.yml` and child task files (`cgroup_v2.yml`, `admin_acks.yml`, `unpause_mcp.yml`, `restart_operator.yml`).
  - **Suite 5: CLI Pre-Flight & Concurrency Tests (`00_Run.sh`)**:
    - Syntax verification with `bash -n` on `00_Run.sh` and `scripts/cli_helpers.sh` passed cleanly.
    - CLI argument handling: `--help` screen verified, invalid option rejection returns exit code 1 with usage hint.
    - Dependency validation: Verified pre-flight failure and formatted diagnostic reporting (exit code 1) when `ansible-playbook`, `oc`, `jq`, or `python` are missing.
    - Concurrency lock verification: Tested `/tmp/aro-upgrade-<cluster>.lock` against active running PID; confirmed immediate blocking with exit code 1. Tested stale PID cleanup and verified automatic lock removal via `EXIT INT TERM` signal traps.
    - Extra-vars JSON serialization: Confirmed single-string JSON extra-vars assembly via Python `json.dumps()` eliminating `parse_kv` list truncation.
  - **Pre-Merge Master Checklist Audit (11/11 Items Passed)**:
    - [PASS] Item 01: All 7 process playbooks pass syntax
    - [PASS] Item 02: Zero tasks use removed 'warn:' parameter
    - [PASS] Item 03: Zero bare 'include:' exists (use include_tasks/import_tasks)
    - [PASS] Item 04: Zero self-referencing variable assignments in vars blocks
    - [PASS] Item 05: Zero rescue blocks template 'ansible_failed_task.name'
    - [PASS] Item 06: 'sendmail' clears mail_html_body and mail_final_body facts
    - [PASS] Item 07: Shell tasks with pipefail set 'args: executable: /bin/bash'
    - [PASS] Item 08: All oc CLI queries implement retry loops (retries: 3 / delay: 10)
    - [PASS] Item 09: All 14 prevalidation checks mapped in prevalidation contract
    - [PASS] Item 10: Concurrency lock file creation and cleanup on exit/trap verified
    - [PASS] Item 11: progress-tracker.md, README.md, and Documentation.md in sync

- [x] **Unit 18: Production Documentation, Client Presentation & Complete Architectural Wirings**:
  - **18 High-Resolution Architecture Diagrams (300 DPI)**:
    - Generated all 18 vector-quality diagrams in `ARO_Cluster_Upgrade_Diagrams/` with consistent Navy/Blue/Amber enterprise styling.
    - Catalog created in `ARO_Cluster_Upgrade_Diagrams/index.md` cross-referencing all 18 figures to `.docx` chapters and `.pptx` slides.
  - **Comprehensive Production Word Document (`ARO_Cluster_Upgrade_Production_Documentation.docx`)**:
    - Compiled complete 34-chapter enterprise specification (5.63 MB, 445 paragraphs, 23 styled tables).
    - Includes dedicated **Chapter 19 on Complete Module Wirings & Architectural Interconnections** detailing the 4-tier pipeline, caller-callee bindings (36 invocations), 31 global facts, and settle-gate mathematical proofs.
    - Embeds all 18 diagrams with figure captions, callout warning boxes, and full variable schemas.
  - **Client Executive Presentation (`ARO_Cluster_Upgrade_Client_Presentation.pptx`)**:
    - Compiled 24 widescreen (16:9) slides (4.94 MB) featuring card layouts, status pills, KPI summary banners, and tabular risk matrices.
    - Embedded diagrams on 15 core architectural slides including Slide 17 dedicated to Complete Module Wirings.
    - **Substantive speaker notes on 100% of substantive slides (Slides 2–24)** with architectural explanations and exact source code file references.
  - **Zero Plaintext Secrets**: Verified 0 hardcoded passwords, tokens, or private keys across all generated deliverables.

---

## In Progress
- None. Review-remediation units 1–10 are complete and verified offline; awaiting jump-host validation and the user's commit decision.

---

## Next Up
1. **Jump-host validation** (in order): `ansible-playbook --syntax-check` on every playbook with Ansible 2.7.17 and 2.14.18; confirm the `mail` module is available on 2.14 (community.general); `jq --version` is 1.5+; `curl` reaches `upgrade_graph_url` (or set `upgrade_graph_proxy`); `./00_Run.sh --cluster <dev> --dry-run`; `--pre-check` on DEV; a full DEV upgrade (one minor hop) watching the heartbeat / degradation mails and the admin-ack step.
2. Non-Production staging soak test (multi-hop with workloads).
3. SRE operational handover and runbook drills; CAB submission.
4. Regenerate the Unit 18 Word / PowerPoint / diagram deliverables from the updated context docs (they describe the previous design).


## Architecture Decisions (Locked)

1. **One-Touch Automation with Verified Auto-Remediation**:
   - Phase 02 (default ON): cgroup v2 migration, unpause allow-listed MCPs; (default OFF) degraded operator pod restart. Node rollouts are monitored, then all 15 checks re-run; AUTO-FIXED only if the check passes.
   - Phase 03, per minor hop: removed-API usage check, then admin-ack, then wait for `Upgradeable=True`.
   - Phase 04 (default OFF): machine-config daemon force on a daemon-Degraded node.
   - Phase 06: one operator Deployment restart for a Failed CSV of an approved operator (CSVs are never deleted).
   - Hard stop with the exact reason for everything else (conditional-update risks, removed APIs in use, foreign update in progress).
2. **Seven-File Process Surface**: Exactly seven main files: `00_Run.sh`, `main.yml`, and `01`–`06` playbooks. Operator upgrade is Phase 06 (`06_Operator_Upgrade.yaml`).
3. **No AI in Runtime**: 100% rule-based and deterministic (`when:`, `fail:`, deterministic `oc patch`).
4. **Dual-Version Runtime Compatibility**: Single codebase runs unmodified on Ansible 2.7.17 and 2.14.18.
5. **Concurrency Safety**: flock-based lock (`/tmp/aro-upgrade-<cluster>.lock`, atomic mkdir fallback) prevents concurrent runs against the same cluster; only the owner releases it.
6. **Native SMTP Notification through one composer**: `tasks/notify.yml` → `roles/sendmail`; prevalidation mail (full runs), 20-min heartbeat, degradation alerts, one failure alert, one closing summary; SMTP failures never fail the run.
7. **Fail-Safe Session Teardown**: identity-checked login in Phase 01; later phases log in only without an active session; the `main.yml` close-out play logs out after success; every rescue and `always:` guard logs out on failure.
9. **Whole-Path Validation**: every remaining edge validated against the OpenShift Update Service graph of the hop's channel before any change (TLS verification skipped by configuration, per the user).
10. **Run Status File**: `logs/<cluster>_<ts>.status` carries the failure exit class to the CLI (5 / 10 / 20 / 25 / 30 / 35 / 99).
8. **Ephemeral Cluster State**: All cluster state is queried live; only `snapshots/<cluster>_<ts>_baseline.json` is persisted across phases.

---

## Session Notes

### Session: Prevalidation Contract Expansion (14 → 15 Checks)
**Date**: 2026-09-11

**Summary**: Expanded prevalidation contract from 14 to 15 checks by adding OLM Operator Upgrade Compatibility (Check 15) to Phase 02. This check reuses the existing `operator_compat` role from Phase 06 with gate suppression (`operator_compat_enforce_gate: false`).

**Changes Made**:
- `playbooks/roles/prevalidation/defaults/main.yml`: Added `operator_compat_enforce_gate: false`, updated header from 14-check to 15-check
- `playbooks/roles/prevalidation/tasks/main.yml`: Added Check 15 (OLM Operator Upgrade Compatibility) after Check 14 (CGroup Mode), updated all 14→15 references in banners, comments, and summary display
- `playbooks/02_Pre_upgrade_check.yaml`: Updated all 14→15 references in headers and task names
- `context/project-overview.md`: Updated all 14-check references to 15-check
- `context/architecture.md`: Updated Phase 02 table row and prevalidation check count
- `context/code-standards.md`: Updated gates section check count
- `context/progress-tracker.md`: Added session note, updated v1 build history
- `README.md`: Updated all 14-check references, added `operator_compat` to role list
- `Documentation.md`: Updated references, appended new §5.1 documenting the expansion with full 15-check contract table
- `ARO_Cluster_Upgrade_Client_Presentation.pptx`: Updated Slides 2, 4, 8, 12, 13, 21, 22, 23 to reflect 15-check prevalidation contract and Check 15 OLM operator upgrade compatibility
- `ARO_Cluster_Upgrade_Production_Documentation.docx`: Updated all executive summaries, TOC, List of Tables (Table 4), Table 1, Table 7, Table 8, Table 9 (promoted Check 14 to HARD and added Check 15 row), Table 12, Table 18, and Table 19

**Rationale**: The `operator_compat` role was previously only invoked in Phase 06, meaning incompatible operator channels were not detected until after cluster mutations had been committed. Promoting this check to Phase 02 ensures early detection and gives operators a chance to resolve incompatibilities before any irreversible changes.

**Impact**: 9 HARD gates + 6 WARN advisories = 15 total checks. No auto-remediation exists for operator channel incompatibility — this is a hard stop requiring manual intervention. All engineering playbooks, context files, client presentations, and production architecture specifications are fully synchronized.

### Session: Phase 01 HTML Report Template & Integration
**Date**: 2026-09-16

**Summary**: Added a dedicated Jinja2 report template (`phase01-policy-check.j2`) and integrated HTML report generation into `01_Policy_Check.yaml`, giving Phase 01 the same client-facing audit reporting as Phases 02, 05, and 06.

**Changes Made**:
- `playbooks/templates/phase01-policy-check.j2` **(NEW)**: Dedicated Phase 01 report template with upgrade journey visualization, step-by-step execution table, baseline snapshot grid, edge validation detail (available + conditional edges), session lifecycle cards, artifacts table, and collapsible diagnostics. Uses project design tokens from `report_vars.yml`.
- `playbooks/01_Policy_Check.yaml`: Added phase start time capture (`phase01_start_epoch`), duration calculation, structured check assembly (`phase01_checks` list of 11 execution steps), report parameter configuration (`report_type: phase01`, `report_template: phase01-policy-check.j2`), and `include_role: name=report` invocation on success. Added fail-safe HTML report generation to `rescue:` block (checks disk presence, builds failure step list, adds diagnostic context, calls `report` role, attaches report to `mail_attachments` for `error_handle` alert email, and logs status).
- `playbooks/templates/phase01-policy-check.j2`: Added dynamic failure presentation support (FAIL status badges, red metric counts on failure, invalid edge tag in edge validation box, failure handoff callout box stating zero mutations occurred, and collapsible deep diagnostic error trace).
- `playbooks/roles/report/tasks/main.yml`: Added `phase01` to the `report_title` resolution chain.
- `playbooks/roles/report/defaults/main.yml`: Updated description to include Phase 01.
- `context/architecture.md`: Added `phase01-policy-check.j2` to templates listing, updated Phase 01 process surface description.
- `context/ui-context.md`: Added Phase 01 report specifics section documenting unique template components.

**Rationale**: Phase 01 previously had no client-facing HTML report, unlike Phases 02, 05, and 06. Generating the report on both success and failure provides an auditable compliance record showing exactly which step succeeded, which step failed, and the full root-cause error trace before cluster mutations begin.

**Impact**: Phase 01 now generates `output/<cluster>_phase01_<timestamp>.html` on both success and failure alongside existing prevalidation/postvalidation/operator reports. On failure, the report is attached to the error alert email dispatched by `roles/error_handle`. The template uses a dedicated structure because Phase 01 content (edge validation, snapshot grid, session lifecycle) differs structurally from the health-check table format in `health-overview.j2`.

### Session: Phase 01 Failure HTML Report Generation Fix
**Date**: 2026-09-16

**Summary**: Resolved an issue where `01_Policy_Check.yaml` failed to generate the HTML report on error or HARD gate halt. Eliminated nested rescue anti-patterns, moved cluster login inside the protected tasks block, refactored `roles/report` to use the native `template:` module with automatic template resolution, and added a fail-safe direct disk write fallback guarantee.

**Root Causes & Fixes**:
1. **Login in `pre_tasks:`**: Previously, authentication failure in `pre_tasks:` halted the play before `tasks:` or `rescue:` could execute. Moved `login` to Step 1 inside `tasks: block:` so all authentication failures jump to `rescue:`, generating a failure report with Step 0 marked `FAIL`.
2. **Nested `block / rescue` in `rescue:`**: Nested blocks with rescue sections inside an outer rescue are prohibited in Ansible syntax and caused tasks to be skipped. Flattened all failure handling tasks directly into `rescue:`.
3. **`roles/report` Rendering Model**: Replaced `lookup('template')` + `copy: content:` with atomic `template:` module generation (`src: "{{ resolved_report_template }}" dest: "{{ report_file_path }}" mode: '0644'`), pre-creating `output/` and auto-resolving `phase01-policy-check.j2` whenever `report_type in ['phase01', 'policy_check']`.
4. **Dual-Layer Generation Guarantee**: Added direct `template:` module fallback in `01_Policy_Check.yaml` rescue block that verifies report presence via `stat` and generates the file directly if `roles/report` did not write it to disk.
5. **Robust Jinja2 Fallbacks**: Guarded all template variables (`target_first_hop | default('N/A')`, `baseline_current_version | default('N/A')`, dynamic authentication card) preventing `UndefinedError` during early phase halts.

### Session: Phase 02 Prevalidation HTML Report Overhaul & 15-Check Checklist Integration
**Date**: 2026-09-16

**Summary**: Overhauled Phase 02 Prevalidation reporting to resolve missing check reports and checklists. Introduced dedicated Jinja2 presentation template `phase02-prevalidation.j2` implementing the full 15-check prevalidation contract, added domain-specific check report breakdown panels, and re-engineered `02_Pre_upgrade_check.yaml` for guaranteed HTML report generation on both success and failure.

**Deficiencies Resolved**:
1. **Missing 15-Check Contract Checklist**: The prevalidation HTML report previously relied on generic `health-overview.j2`, which lacked structured domain cards, granular metric counts, and did not guarantee an immutable 15-item contract checklist.
2. **Missing Failure Report on Residual HARD Gate Abort**: In `02_Pre_upgrade_check.yaml`, report generation was located at Step 8, but residual HARD gate failure assertions occurred at Step 7. When any check failed after remediation, the playbook aborted at Step 7, entirely skipping Step 8 and producing no HTML report for operator review.
3. **Session Verification in `pre_tasks:`**: Session login checks in `pre_tasks:` bypassed the `tasks: block:` and `rescue:` error handling, causing any early connectivity or auth failure to exit without an audit report.
4. **Incomplete Check Contract on Early Halts**: If a check aborted execution prematurely, `health_summary` only held partial items. The new failure handler constructs the full canonical 15-check list, marking reached checks with actual status, the failing check as `FAIL`, and unreached checks as `SKIPPED ⏸`.

**Changes Made**:
- `playbooks/templates/phase02-prevalidation.j2` **(NEW)**: Dedicated Phase 02 client audit template (1,325 lines, ~61KB). Features:
  - Header band with `Phase 02 of 06` badge, cluster name, first target hop, run timestamp, and overall verdict pill (`PASS ✔`, `WARN !`, `FAIL ✖`, `AUTO-FIXED ⚙`, `FIX-FAILED ⚠`).
  - 6 summary metric tiles: Total Contract Checks (15), Passed, Auto-Fixed, Warnings, Failed, Skipped.
  - Planned upgrade journey visualization bar.
  - Auto-remediation callouts for applied Tier 1/2 fixes (cgroup v2, admin-acks, unpaused MCPs, operator restarts) with direct Red Hat documentation links.
  - Master 15-Check Contract Checklist Table (#01–#15) with check numbers, names, role/inline type, gate type (HARD/WARN), observed state, and status badges.
  - 15 granular check domain cards: ClusterOperators breakdown, Node readiness & pressure tallies, MachineConfigPool sync, API context, API readiness, etcd quorum & HA, admin acknowledgements, capacity headroom (CPU/Mem request %), pending CSRs, PV statuses, PVC statuses, PDB zero-disruptions with system namespace exclusions, critical platform pods, cgroupMode compatibility, and OLM operator compatibility.
  - OLM Subscription compatibility table with package, channel, install plan, CSV, and status.
  - Session lifecycle and safety model cards.
  - Deep diagnostics collapsible sections with `@media print` expansion.
  - Standalone copy-to-clipboard actions for run IDs, API endpoints, and failure commands.
- `playbooks/roles/report/tasks/main.yml`: Updated template resolution to automatically resolve `phase02-prevalidation.j2` whenever `report_type in ['prevalidation', 'preval']`.
- `playbooks/roles/report/defaults/main.yml`: Documented `phase02-prevalidation.j2` auto-resolution.
- `playbooks/02_Pre_upgrade_check.yaml`:
  - Moved session verification and `login` role from `pre_tasks:` into protected `tasks: block:` so all auth failures jump to `rescue:`.
  - Added phase start epoch and duration tracking (`phase02_start_epoch`, `phase02_duration_seconds`).
  - Updated Step 8 to explicitly pass `report_template: "phase02-prevalidation.j2"`.
  - Updated Step 11 email notification to use `mail_template: "phase02-prevalidation.j2"`.
  - Re-engineered `rescue:` block with full fail-safe checklist compilation: merges existing `health_summary` items, marks failing step as `FAIL`, fills remaining checks through #15 as `SKIPPED ⏸`, invokes `roles/report` with `overall_status: FAIL` (using `ignore_errors: true` instead of invalid `failed_when: false` on `include_role`), provides direct `template:` module fallback, and attaches `report_file_path` to `mail_attachments` for `roles/error_handle` failure alert emails.
- `playbooks/01_Policy_Check.yaml`: Resolved Jinja2 `TemplateSyntaxError` in rescue block task `Phase 01 Rescue: Assemble execution step records for failure report` (line 398): replaced backslash-escaped quotes `\'` in check 6 `observed` expression with double quotes, preventing Ansible's multi-pass string evaluation from double-escaping backslashes and failing with `expected token ')', got 'unknown'`.
- `context/architecture.md`: Registered `phase02-prevalidation.j2` under presentation templates.
- `context/ui-context.md`: Added Phase 02 Prevalidation report specifics section.

**Rationale & Impact**:
- Gives Phase 02 prevalidation the same auditable, executive-ready HTML presentation as Phase 01.
- Guarantees that whether prevalidation passes, auto-remediates, or encounters residual HARD gate failures, a complete 15-row contract checklist is ALWAYS rendered to `output/<cluster>_prevalidation_<timestamp>.html` and attached to failure emails.
- Fully compatible with dual Ansible runtime (2.7.17 and 2.14.18) and standard Jinja2 rendering engines. Zero git operations performed.

### Session: Strict Phase-Specific Error Notification Attachments & Phase 05 Postvalidation Failure Report Overhaul
**Date**: 2026-09-16

**Summary**: Diagnosed and resolved an issue where failure alert emails for Phase 05 (Post-Upgrade Checks & Baseline Diff) erroneously attached the Phase 02 prevalidation HTML report. Implemented strict phase-boundary attachment enforcement across `roles/error_handle`, presentation template `error-report.j2`, `playbooks/05_post_Upgrade_Checks.yaml`, `playbooks/03_Initiate_upgrade.yaml`, `playbooks/tasks/hop.yml`, and `roles/sendmail`.

**Root Causes**:
1. **Fact Cache Persistence Across Plays**: `report_file_path` set during Phase 02 persisted in the host fact cache of `localhost`. When Phase 02 ran in dry-run mode (or success email was deferred), `roles/sendmail` was not invoked, leaving `report_file_path` active in memory.
2. **Phase 05 Guard Skipped Failure Report Generation**: In `05_post_Upgrade_Checks.yaml`, the rescue condition `when: (report_file_path is not defined) or (report_file_path | length == 0)` evaluated to `false` because `report_file_path` pointed to the Phase 02 prevalidation report, preventing postvalidation report generation.
3. **Unsanitized Fallback in `roles/error_handle`**: When `mail_attachments` was empty, `roles/error_handle` blindly fell back to `[report_file_path]`, attaching the lingering Phase 02 report.
4. **Missing Phase Guard in `error-report.j2`**: The template rendered all passed attachments without verifying whether they corresponded to the current failed phase.

**Fixes Applied**:
1. **`playbooks/roles/error_handle/tasks/main.yml`**:
   - Added phase context detector (`error_phase_tag`) evaluating `current_step_no`, `current_task_name`, and `failed_task_name`.
   - Strictly sanitized `mail_attachments` so reports only attach if they match the failed phase:
     - Phase 01: only `*phase01*` / `*policy*` reports.
     - Phase 02: only `*prevalidation*` / `*preval*` reports.
     - Phase 03: zero HTML validation reports.
     - Phase 05: only `*postvalidation*` / `*postval*` reports.
     - Phase 06: only operator or consolidated reports.
   - Synchronized `attached_reports` directly from sanitized `mail_attachments`.
2. **`playbooks/templates/error-report.j2`**:
   - Added phase-aware attachment filtering in the "Attached Diagnostic Reports" callout.
   - Restricts `prevalidation` reports strictly to Phase 02 (or Phase 06 consolidated).
   - Restricts `postvalidation` reports strictly to Phase 05 (or Phase 06 consolidated).
   - Completely suppresses the attached reports section when no valid attachments match the failed phase.
3. **`playbooks/05_post_Upgrade_Checks.yaml`**:
   - Resets `report_file_path`, `mail_attachments`, `attached_reports`, and `report_template` at playbook initiation.
   - Re-engineered rescue block to assemble the full 10-check postvalidation contract checklist (`p05_failure_checks`) with failing check as `FAIL` and unreached checks as `SKIPPED ⏸`.
   - Generates client-facing HTML failure report `output/<cluster>_postvalidation_<ts>.html` via `roles/report` (with direct template fallback).
   - Sets `mail_attachments: ["<p05_rescue_report_path>"]` and `report_file_path: "<p05_rescue_report_path>"`.
4. **`playbooks/03_Initiate_upgrade.yaml` & `playbooks/tasks/hop.yml`**:
   - Explicitly clear `mail_attachments: []`, `attached_reports: []`, and `report_file_path: ""` at initiation and in rescue blocks.
5. **`playbooks/roles/sendmail/tasks/main.yml`**:
   - Expanded post-dispatch cleanup to reset `attached_reports: []` and `report_file_path: ""` alongside `mail_attachments: []`.

---

### Operational CLI Enhancements: Help Banner, Artifact Purge & Isolated Phase Execution

- **Status**: Completed
- **Date**: 2026-09-16
- **Artifacts Modified**:
  - `playbooks/scripts/cli_helpers.sh`: Added `print_help_banner` and `purge_artifacts` functions.
  - `playbooks/00_Run.sh`: Added `--clean`/`--clear` flag and handler, `--phase <NN>` flag with normalization, interactive sub-menus for isolated phase execution (Final or Dry-Run), interactive clean option, and startup help banner.
  - `playbooks/main.yml`: Added isolated Phase 03 termination intercept when `stop_after_phase == 3` and refined Phase 05 validation intercept condition.

#### Key Capabilities Added:
1. **Operational Artifact Purge (`--clean` / `--clear`)**:
   - Purges generated `.txt`, `.csv`, `.html`, and `.json` artifacts from `logs/`, `output/`, and `snapshots/` while strictly preserving repository tracking files (`.gitkeep`).
   - Supports interactive confirmation (`[y/N]`) or non-interactive bypass (`-y` / `--yes`).
   - Available both via CLI flag and interactive execution menu (Option 6).
2. **Startup Help Banner (`print_help_banner`)**:
   - Displays a formatted 72-column guidance box upon triggering `./00_Run.sh` in interactive mode, ensuring operators immediately recognize the `--help` option and available non-interactive flags.
3. **Isolated Phase Execution (`--phase <NN>`)**:
   - Allows running any individual phase (01, 02, 03, 05, 06) completely separated from other phases.
   - Supports both Final/Live execution and read-only Dry-Run modes.
   - Phase 06 Dry-Run maps cleanly to `skip_operator_upgrade: true` (compatibility scan & validation only without InstallPlan approval).
   - Refined safety guard ensures non-mutating isolated audits on production clusters do not require typing `UPGRADE`.

---

### Isolated Phase Execution Fix: Direct Playbook Dispatch & Task-Level Lifecycle Guards

- **Status**: Completed
- **Date**: 2026-09-17
- **Root Causes Diagnosed**:
  1. `import_playbook` does not evaluate `when:` conditionals in Ansible (both 2.7.17 and 2.14.18 statically import all playbooks at parse time).
  2. `meta: end_play` terminates only the active play, causing Ansible to continue into subsequent imported plays.
  3. Individual phase playbooks lacked task-level phase boundary checks.
  4. `00_Run.sh` unconditionally dispatched `main.yml` even when single-phase execution was selected.
- **Architectural Solution Implemented (Defense-in-Depth)**:
  1. **Direct Playbook Dispatch in `00_Run.sh`**:
     - When `--phase <NN>` or Menu Option 5 is selected (`SKIP_TO_PHASE == STOP_AFTER_PHASE`), `00_Run.sh` directly invokes the designated phase playbook (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`) instead of `main.yml`.
     - Passes `"standalone_phase": true` in `EXTRA_VARS`.
     - Multi-phase flows (Full Upgrade, Dry Run across all phases, Pre-check only 01+02) continue to dispatch `main.yml`.
  2. **Task-Level Phase Lifecycle Guards**:
     - Added block-level `when:` guards inside each phase playbook (`01`, `02`, `03`, `05`, `06`) checking `skip_to_phase` and `stop_after_phase`.
     - Cleaned up invalid `when:` lines under `import_playbook:` in `main.yml`.
  3. **Guaranteed Standalone Session Teardown**:
     - Added session logout (`roles/logout`) at completion of each phase playbook when running with `standalone_phase: true` or when stopping at that phase.

---

### Session: Deep Review Remediation — Admin-Ack per Hop, Developer Perspective, Mail De-duplication

- **Status**: Code complete, verified offline (no Ansible on the development workstation); not committed.
- **Date**: 2026-10-01
- **User decisions**: admin-ack applied automatically per minor hop after an APIRequestCount check (stop if removed APIs are in use); Developer perspective enabled in the Phase 06 closeout on live runs only (dry runs / post-checks report); in-hop mails limited to the 20-minute heartbeat and degradation alerts; failure alert and final summary always; full runs send the prevalidation mail + final summary; Phase 06 approves only each subscription's current InstallPlan; whole path validated against the update graph (internet available); TLS verification stays skipped.
- **Units delivered**:
  1. CLI (`00_Run.sh`, `cli_helpers.sh`): PROD confirmation cannot be bypassed, flock lock, static path validation, change scope, exit code from the status file, `--pre-check` / `--dry-run` semantics.
  2. Session: password on stdin, no retry on bad credentials, identity checks (URL, cluster ID pin, regex), logout removes the kubeconfig, `.gitignore` for kubeconfigs and run artifacts.
  3. Notifications: `tasks/notify.yml`, `tasks/send_run_summary.yml`, `tasks/log_event.yml`, `roles/sendmail`, `roles/error_handle` (one alert, status file), templates `email-summary.j2` (new), `progress-mail.j2`, `error-report.j2`.
  4. Admin-acks: `roles/api_usage` (new), `remediate/tasks/admin_acks.yml` evaluate / apply engine.
  5. Prevalidation and remediation: Checks 07 / 14 / 15 rewritten; remediations record attempts only; Phase 02 rollout wait, full re-scan, AUTO-FIXED / FIX-FAILED merge, report before gate.
  6. Path and hops: `tasks/validate_upgrade_path.yml` (new), `roles/upgrade` (plan `main.yml` + `apply.yml`), `tasks/hop.yml`, Phase 01 / 03 / 04 playbooks, `roles/monitor` rewritten (`poll_body.yml` new: real clock, outage tolerance, progress-based timeouts, degradation alerts, rollout mode).
  7. Postvalidation: kubelet parse, Ready=Unknown, operator settle loop, alerts "not checked" state, baseline path; Phase 05 playbook.
  8. Reports: report role inputs cleared per render; Phase 02 cards data-driven (no invented values); status ordering and escaping in all report templates.
  9. Phase 06: `operator_upgrade` (current InstallPlan per subscription, CSV wait, one restart), `operator_validate` (approved / regression gate), `roles/console` (new), Phase 06 playbook; `main.yml` reduced to phase imports + one close-out play.
  10. Docs: architecture, code standards, project overview, UI context, this tracker, README, Documentation.md.
- **Verification (offline, in the session scratchpad)**: YAML parse + Jinja compile of every file and template; all 75 embedded jq programs compiled with libjq and scanned for post-1.5 syntax; 45 jq behaviour tests on sample cluster JSON; 16 path-validation scenarios; 27 monitor state-machine scenarios (settle, heartbeat cadence, degradation alert-once, no-progress / outage / release / Failing aborts, rollout mode, dry run); 70 phase-flow checks (Phase 02 remediation and gate, hop plan, hop + Phase 03 single alert and exit codes, operator validation, console, report, routing, summaries, close-out); report templates rendered under strict undefined. Issues found by these tests and fixed: Ansible 2.7 attribute access on an undefined `poll_cv`, console `visibility` access, fact-vs-vars precedence for the Phase 06 compatibility target.
- **Not verified here**: execution on a real cluster and on Ansible itself (the workstation is Windows; Ansible cannot run on a Windows control node). See Next Up item 1.

