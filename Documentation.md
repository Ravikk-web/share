# ARO Cluster Upgrade Automation — Engineering Documentation

This document serves as the **cumulative, running engineering record** of the ARO Cluster Upgrade Automation suite. It records every unit implemented, key design decisions and their architectural rationale, gate and threshold specifications, auto-remediation rules, dual-version migration notes, and operational procedures.

---

## 1. System Architecture & Design Principles

The ARO Cluster Upgrade Automation suite is an enterprise-grade, deterministic, rule-based automation system for executing sequential Y-stream upgrades of Azure Red Hat OpenShift (ARO) clusters, followed by OLM operator validation.

### Core Design Tenets
1. **Deterministic Execution**: No AI, probabilistic inference, or heuristic decision-making exists in the execution path. All branching is governed by explicit Ansible `when:` conditions, `fail:` gates, and verifiable `oc` CLI commands.
2. **Dual-Version Compatibility**: The identical codebase runs without modification on both **Ansible 2.7.17 (test jump hosts)** and **Ansible 2.14.18 (production environments)**.
3. **Seven-File Process Surface**: High-level workflow orchestration is driven by exactly seven process files (`00_Run.sh`, `main.yml`, and `01_Policy_Check.yaml` through `06_Operator_Upgrade.yaml`).
4. **Fail-Safe Session Lifecycle**: The suite authenticates once (`oc login`) in Phase 01, scoped to an ephemeral kubeconfig under `playbook_dir`. Session logout and token invalidation are guaranteed across all exit paths via `block/rescue/always`.
5. **Three-Tier Auto-Remediation**: Non-destructive, known upgrade blockers (e.g., cgroup v1→v2 migration, dynamic admin-acks, paused MCPs) are automatically detected, resolved, and verified prior to proceeding.

---

## 2. Directory Layout & Boundaries

```
playbooks/
├── 00_Run.sh                    # CLI entrypoint (Bash)
├── main.yml                     # Master orchestrator (Ansible)
├── 01_Policy_Check.yaml         # Phase 01: Auth, baseline snapshot, update edge validation
├── 02_Pre_upgrade_check.yaml    # Phase 02: 14-check prevalidation gate & auto-remediation
├── 03_Initiate_upgrade.yaml     # Phase 03: Per-hop driver looping tasks/hop.yml
├── 04_Live_monitoring_upgrade.yaml # Phase 04: Live polling, heartbeat, settle-gate
├── 05_post_Upgrade_Checks.yaml  # Phase 05: 10-check postvalidation gate & baseline diff
├── 06_Operator_Upgrade.yaml     # Phase 06: OLM operator upgrades & terminal logout
├── vars/                        # Input variables only (no tasks/logic)
│   ├── upgrade.yml              # Cluster targets, paths, thresholds, auto-remediation toggles
│   ├── secrets.yml              # Vault-ready credential variable references
│   ├── smtp.yml                 # SMTP configuration and alert recipients
│   ├── paths.yml                # Centralized dynamic paths anchored to playbook_dir
│   ├── report_vars.yml          # UI color tokens, background tints, badge constants
│   └── api_regex.yml            # Validation regex for URLs, versions, and names
├── scripts/                     # Sourced shell libraries (cli_helpers.sh)
├── roles/                       # 24 modular single-purpose roles
├── tasks/                       # Sub-playbook workflow tasks (hop.yml)
├── templates/                   # Presentation-only Jinja2 templates (.j2)
├── logs/                        # Write-only execution logs (.txt and .csv)
├── output/                      # Write-only client HTML reports
└── snapshots/                   # Write-only baseline JSON snapshots
```

---

## 3. Cumulative Unit Record

### Unit 01: Project Scaffold & Variable Inputs

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created**:
  - `playbooks/vars/upgrade.yml`
  - `playbooks/vars/secrets.yml`
  - `playbooks/vars/smtp.yml`
  - `playbooks/vars/paths.yml`
  - `playbooks/vars/report_vars.yml`
  - `playbooks/vars/api_regex.yml`
  - `playbooks/scripts/cli_helpers.sh`
  - Write-only directory anchors (`.gitkeep` in `logs/`, `output/`, `snapshots/`, `roles/`, `tasks/`, `templates/`)

#### Key Architectural Decisions & Rationale:

1. **Vault-Ready Secret Architecture (`vars/secrets.yml`)**:
   - Credentials are not stored in plaintext. They are declared as variable references: `cluster_d01_password: "{{ vault_cluster_d01_password | default('') }}"`.
   - A structured `clusters` map provides display names, API URLs, usernames, and cluster tiers (`DEV`, `STAGE`, `PROD`) for the CLI interactive selection menu.
   - Migrating to CyberArk Conjur Vault in the future will require zero task or role refactoring; only the vault variable source will change.

2. **Portable Dynamic Path Derivations (`vars/paths.yml`)**:
   - No jump host paths are hardcoded. All paths derive dynamically from `{{ playbook_dir }}` (e.g., `{{ playbook_dir }}/logs`, `{{ playbook_dir }}/output`).
   - The kubeconfig path is scoped per target cluster: `{{ playbook_dir }}/.kubeconfig-{{ cluster_name | default('default') }}`. This isolates sessions and prevents clobbering local engineer environments (`~/.kube/config`).

3. **Auto-Remediation Controls & Thresholds (`vars/upgrade.yml`)**:
   - Centralizes the master toggle `auto_remediation_enabled: true` along with granular toggles for individual remediations (`auto_fix_cgroup_v2`, `auto_apply_admin_acks`, `auto_unpause_mcp`).
   - Tier 1 fixes default to `true` (safe, official Red Hat remediation).
   - Tier 2 guided fixes default to `false` (require explicit opt-in).
   - Defines resilient query parameters (`oc_command_retries: 3`, `oc_command_retry_delay: 10`) to protect against transient API server restarts.

4. **UI Design Tokens (`vars/report_vars.yml`)**:
   - Hex color constants and background tints comply with WCAG AA accessibility standards.
   - Status badges pair alphanumeric text with unicode glyphs (`PASS ✔`, `WARN !`, `FAIL ✖`, `AUTO-FIXED ⚙`, `FIX-FAILED ⚠`) so statuses remain distinguishable in monochrome or printed exports.

5. **Input Validation Regex (`vars/api_regex.yml`)**:
   - Standardizes regex patterns for cluster API URLs (`desired_cluster_api_regex`), semantic version strings (`ocp_version_regex`), and cluster names (`cluster_name_regex`) to reject malformed inputs before invoking cluster operations.

6. **Dual-Version Compatibility Compliance**:
   - Every YAML file includes the standard header documenting Ansible 2.7.17 and 2.14.18 compatibility.
   - All optional variables have typed defaults (`| default('')`).

---

### Unit 02: CLI Entrypoint (`00_Run.sh`), Helper Library (`scripts/cli_helpers.sh`) & Master Orchestrator Skeleton (`main.yml`)

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created / Expanded**:
  - `playbooks/scripts/cli_helpers.sh` (expanded to full terminal UI engine)
  - `playbooks/00_Run.sh` (complete operational entrypoint)
  - `playbooks/main.yml` (orchestrator skeleton)

#### Key Architectural Decisions & Rationale:

1. **Terminal UI Engine & Alignment Fidelity (`scripts/cli_helpers.sh`)**:
   - ANSI color codes are mapped with TTY detection (`[[ -t 1 ]]`), gracefully degrading to plain text when piped or executed in non-interactive CI environments.
   - `visible_length()` and `strip_ansi()` functions eliminate ANSI escape sequences from width calculations. This guarantees that UTF-8 box rows (`draw_box_row`) maintain exact right-border alignment at column 72 regardless of embedded color codes.
   - Reusable primitives (`draw_box_header`, `draw_box_row`, `draw_box_divider`, `draw_box_footer`) enforce a uniform 72-column presentation across menus, journey diagrams, risk alerts, and execution summaries.

2. **Concurrency Safety & Clean Signal Traps (`00_Run.sh`)**:
   - A cluster-scoped PID lock file (`/tmp/aro-upgrade-<cluster>.lock`) prevents concurrent runs against the same cluster.
   - Before acquiring the lock, `kill -0 "$PID"` checks whether any existing lock belongs to a living process. Stale lock files from aborted or terminated runs are automatically removed with a warning.
   - A global `trap cleanup EXIT INT TERM` guarantees that lock files are removed and terminal echo attributes restored (`stty echo`) under all exit conditions, including `Ctrl+C` or unhandled errors.

3. **Deterministic Schema & Vars Validation (Zero Awk Fragility)**:
   - Configuration is validated using embedded Python (`yaml.safe_load()`), eliminating fragile shell/regex parsing.
   - Validates existence and YAML correctness across all 6 configuration files (`upgrade.yml`, `secrets.yml`, `smtp.yml`, `paths.yml`, `report_vars.yml`, `api_regex.yml`).
   - Extracts cluster names, tiers, display names, and paths into a clean JSON structure consumed directly by shell menus. If an invalid or unconfigured cluster name is passed, execution halts immediately with exit code 3.

4. **Single JSON String Extra-Vars Invariant**:
   - In accordance with the core architecture invariant, extra-vars are passed to `ansible-playbook` strictly as a single JSON object string:
     `-e '{"cluster_name": "...", "upgrade_path": [...], "dry_run": false}'`.
   - This prevents Ansible's `parse_kv` from incorrectly stringifying array elements into single comma-delimited strings on Ansible 2.7.17.

5. **Production Safety Gate**:
   - Clusters tagged with `tier: PROD` or `tier: PRODUCTION` in `vars/secrets.yml` enforce a strict interactive safety gate requiring the operator to type `UPGRADE` in capital letters. Mismatched confirmation aborts execution with exit code 2.

6. **Structured Exit Code Contract**:
   - The CLI maps playbook outcomes, pre-flight checks, and user actions to deterministic exit codes:
     - `0`: Success — Full lifecycle or requested phase completed cleanly.
     - `1`: Usage error or pre-flight dependency missing (`ansible-playbook`, `oc`, `jq`, `python`, `bash >= 4`).
     - `2`: Cancelled by operator during confirmation gate.
     - `3`: Configuration missing, unparseable, or cluster not found in `vars/secrets.yml`.
     - `10`: Prevalidation gate failed (Phase 02).
     - `20`: Cluster upgrade initiation or hop rollout failed (Phase 03/04).
     - `30`: Monitoring settle-gate timeout exceeded (Phase 04).
     - `99`: Unexpected playbook failure.

7. **Dual-Version Master Orchestrator (`main.yml`)**:
   - Targets both Ansible 2.7.17 and 2.14.18 with `# Targets:` and `# MIGRATION 2.14:` documentation headers.
   - Pre-execution `assert` task validates that `cluster_name` and `upgrade_path` are defined and non-empty.
   - Formatted debug banner displays dispatch parameters. Placeholders establish structured chaining for Phases 01 through 06.

### Unit 03: Session Lifecycle Roles (`login`, `logout`)

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created**:
  - `playbooks/roles/login/defaults/main.yml`
  - `playbooks/roles/login/tasks/main.yml`
  - `playbooks/roles/logout/defaults/main.yml`
  - `playbooks/roles/logout/tasks/main.yml`

#### Key Architectural Decisions & Rationale:

1. **Single Authentication Contract (Login Once)**:
   - `login` executes strictly once at the start of the upgrade lifecycle (in Phase 01).
   - The generated session is preserved in memory and on disk across all subsequent phases (Phases 01 through 05, and Phase 06 operator upgrades), eliminating redundant authentication cycles and token re-generation overhead.

2. **Dedicated Session Kubeconfig Isolation**:
   - In accordance with the system boundary invariants, authentication writes strictly to a dedicated cluster-scoped file: `{{ playbook_dir }}/.kubeconfig-{{ cluster_name }}`.
   - It never mutates or relies on the user's default `~/.kube/config`, ensuring concurrent human operator workflows or background jobs on the jump host remain completely unimpacted.

3. **Zero Credential Leaks (`no_log: true`)**:
   - All credential validation assertions and `oc login` command executions declare `no_log: true`.
   - Service account passwords and tokens are never echoed to stdout, stored in Ansible job logs, or leaked into error messages.

4. **Resilient Transient Fault Tolerance**:
   - The `oc login` execution incorporates standard retry loops (`retries: 3 / delay: 10 / until: rc == 0`) to absorb transient network blips and API server 503 unavailability without failing prematurely.

5. **Server Identity Verification Gate**:
   - Following successful authentication, `oc whoami --show-server` queries the connected API endpoint.
   - An explicit assertion verifies that the server URL matches `desired_cluster_api_regex` (`^https://api\.[a-zA-Z0-9.-]+:6443/?$`), guaranteeing that session traffic is directed to an authentic OpenShift cluster API rather than a hijacked or misdirected endpoint.

6. **Guaranteed Fail-Safe Teardown Contract (`logout`)**:
   - The `logout` role is strictly idempotent and safe to execute under all conditions, including after failed logins or unauthenticated runs.
   - Both token revocation (`{{ oc_binary | default('oc') }} logout`) and file deletion (`file: state=absent`) use `failed_when: false` and `changed_when: false`.
   - All session facts (`cluster_kubeconfig`, `ansible_env_kubeconfig`, `kubeconfig`, `active_cluster_server`) are unset, ensuring session cleanup never masks underlying phase failure causes.

7. **Jump Host Parity & CLI Discovery**:
   - Implements automated discovery for the OpenShift CLI binary (`command -v /usr/local/bin/oc || command -v oc`), ensuring full parity on enterprise jump servers where `oc` is located under `/usr/local/bin/oc`.
   - Replaced folded `command: >-` with `shell: |` using `args: executable: /bin/bash` and strict double quoting (`--username="{{ cluster_username }}" --password="{{ cluster_password }}" "{{ cluster_api_url }}"`) to guard against argument splitting when passwords contain special characters.
   - Configured `insecure_skip_tls_verify: true` by default in `roles/login/defaults/main.yml` and `vars/upgrade.yml` because ARO and OpenShift API servers (port 6443) utilize internal/cluster certificates that are not present in jump host system CA trust stores.
   - Extended credential fact resolution to support flat variables (`cluster_*`), dictionary structures (`cluster.*`), and inventory maps (`clusters[...]`).
   - Broadened `desired_cluster_api_regex` in `vars/api_regex.yml` and `roles/api_check/defaults/main.yml` to `'^https://api\.[a-zA-Z0-9.-]+:6443/?$'` to accommodate both hyphenated (`aro-d01`) and contiguous (`arod01`) naming schemes.



### Unit 04: Email Notification System & Templates

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created**:
  - `playbooks/roles/sendmail/defaults/main.yml`
  - `playbooks/roles/sendmail/tasks/main.yml`
  - `playbooks/templates/error-report.j2`
  - `playbooks/templates/progress-mail.j2`
  - `playbooks/templates/health-overview.j2`

#### Key Architectural Decisions & Rationale:

1. **Native Direct SMTP Architecture (`roles/sendmail/`)**:
   - The suite utilizes Ansible's built-in `mail` module (Python standard library `smtplib`), executing directly on the jump host via `delegate_to: localhost`.
   - Eliminates all external dependencies on local Linux MTA daemons (`/usr/sbin/sendmail`, postfix) while providing 100% identical runtime behavior across Ansible 2.7.17 and 2.14.18.
   - Credentials (`smtp_username`, `smtp_password`) and TLS security modes (`never`, `starttls`, `ssl`) are parameterized with `omit` fallbacks to support unauthenticated internal relays and authenticated gateways alike.

2. **Strict Template Rendering Lifecycle & Fact Reset Contract**:
   - Directly addresses **Anti-Pattern #3 (Sendmail Fact Caching)**: Previous implementations suffered from cross-hop data leakage where a cached `mail_html_body` from an earlier hop was inadvertently re-dispatched.
   - Lifecycle:
     1. Resolve template path relative to `playbook_dir/templates/` or as an absolute path.
     2. Always perform a fresh `lookup('template', resolved_template_path)` into `mail_html_body`.
     3. Validate non-empty body and recipient list with explicit `assert`.
     4. Dispatch via native `mail`.
     5. Mandatory post-dispatch cleanup task immediately resets `mail_html_body`, `mail_final_body`, `mail_attachments`, `mail_template`, and `resolved_template_path`.

3. **Conditional RBAC Permission Failure Callout (`error-report.j2`)**:
   - When rescue blocks detect authorization errors (`forbidden`, `unauthorized`, `cannot patch`), the template conditionally surfaces a prominent warning box.
   - Details the missing API verb, targeted Kubernetes/OpenShift resource, and provides the exact actionable cluster-admin remediation command (`oc adm policy add-cluster-role-to-user cluster-admin <user>`).
   - Includes diagnostic matrix and confirmation of safe session teardown.

4. **Monitoring & Hop-Settle Lifecycle (`progress-mail.j2`)**:
   - Compact notification card (`≤ 580px`) displaying overall hop progress, percentage bar, and elapsed time.
   - MachineConfigPool table is always visible, displaying machine counts (`ready/total`), `Updated`, `Updating`, `Degraded`, and status pills.
   - Actively updating nodes (draining/rebooting) are surfaced while healthy nodes are suppressed to prevent email noise.
   - Degraded or pressured nodes (`NotReady`, `MemoryPressure`, `DiskPressure`) are surfaced prominently.
   - Hop-complete state swaps header badge to `HOP COMPLETE ✔` with settle-gate timing and report attachment notices.

5. **Unified Multi-Purpose Health Overview Report (`health-overview.j2`)**:
   - Serves as the single client-facing HTML report for Prevalidation (Phase 02), Postvalidation (Phase 05), and Operator Validation (Phase 06).
   - Features 5-tile summary metrics (Total, Passed, Warnings, Auto-Fixed, Failed).
   - Fully supports design system status pills: `PASS ✔` (`#1a7f37`), `WARN !` (`#9a6700`), `FAIL ✖` (`#b42318`), `AUTO-FIXED ⚙` (`#1d4ed8`), and `FIX-FAILED ⚠` (`#c2410c`).
   - Auto-Remediation Callout dynamically appears when blockers have been fixed, documenting actions taken and citing Red Hat reference documentation.
   - Incorporates Phase 06 OLM Operator validation matrix (Subscription, Installed CSV, Channel, InstallPlan approval state, CSV phase).
   - Deep diagnostics use `<details>` collapsible sections with `@media print` rules expanding all inspection data during PDF generation.

### Unit 05: Reporting & Error Handling Foundation (`error_handle`, `report` roles)

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created**:
  - `playbooks/roles/error_handle/defaults/main.yml`
  - `playbooks/roles/error_handle/tasks/main.yml`
  - `playbooks/roles/report/defaults/main.yml`
  - `playbooks/roles/report/tasks/main.yml`

#### Key Architectural Decisions & Rationale:

1. **Hierarchical Error Extraction Hierarchy (`roles/error_handle/`)**:
   - Resolves error details strictly in order of diagnostic specificity: `stderr` → `stderr_lines` → `msg` → `failure_observed` → `failure_reason` → fallback log reference string.
   - Eliminates crashes caused by **Anti-Pattern #5**: Never references `ansible_failed_task.name`, which is an internal Ansible `Task` object containing non-serializable `FieldAttribute` instances that trigger unhandled templating exceptions in rescue blocks.

2. **Automated RBAC Failure Detection & Actionable Remediation**:
   - Scans error text and failure descriptions for authorization denial patterns (`forbidden`, `cannot patch`, `unauthorized`, `cannot get`, `cannot list`).
   - Automatically sets `is_rbac_error: true` and constructs the recommended cluster-admin remediation command (`oc adm policy add-cluster-role-to-user cluster-admin <user>`) for immediate inclusion in alert notifications.

3. **Dual Audit Logging Contract (.txt and .csv)**:
   - Enforces the persistence invariant by appending human-readable records to `logs/<cluster>_<ts>.txt` with timestamp, gate type, task name, and observed error details.
   - Automatically checks for existence of `logs/<cluster>_<ts>.csv`, initializes the standardized CSV header (`timestamp,cluster,task_name,gate_type,status,reason,observed`) upon first write, and appends properly escaped and newline-sanitized CSV records.

4. **Structured Health Summary Tracking**:
   - Constructs structured failure dictionary records (`num`, `name`, `gate`, `status: "FAIL"`, `observed`) and appends them to `failed_checks` and `health_summary` facts, ensuring downstream report generators maintain complete visibility of failure history.

5. **Jinja2 Anti-Pattern Prevention on Email Dispatch**:
   - Follows **Anti-Patterns #1 and #2**: Pre-computes all parameters (`mail_template: "error-report.j2"`, `mail_to`, `mail_subject`, `failed_task_name`, `failed_gate_type`, `log_file_path`) via `set_fact` before invoking `include_role: name=sendmail`, preventing recursive variable expansion bugs.

6. **Unified Client-Facing HTML Report Generation (`roles/report/`)**:
   - Dynamically consolidates validation items from `checks` or `health_summary` host facts.
   - Derives 5-tile summary metrics (Total, Passed, Warnings, Auto-Fixed, Failed) with seamless support for both cluster health validation checks and Phase 06 OLM operator compatibility matrices.
   - Evaluates the overall report verdict badge using strict deterministic rules:
     - `FAIL` if any failed items exist (`failed_count > 0`).
     - `AUTO-FIXED` if auto-fixed items exist and no failures (`autofixed_count > 0` and `failed_count == 0`).
     - `WARN` if warnings exist and no failures (`warning_count > 0` and `failed_count == 0`).
     - `PASS` if all passed cleanly.
   - Auto-extracts `autofix_items` from checks to populate the automated remediation callout.
   - Renders `health-overview.j2` and writes standalone HTML artifacts to `output/{{ cluster_name }}_{{ report_type }}_{{ run_timestamp }}.html` via `copy:` with `content:`.
   - Exports the `report_file_path` fact for subsequent notification attachment workflows.

### Unit 06: Snapshot Role & Phase 01 Playbook (`01_Policy_Check.yaml`)

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created**:
  - `playbooks/roles/snapshot/defaults/main.yml`
  - `playbooks/roles/snapshot/tasks/main.yml`
  - `playbooks/01_Policy_Check.yaml`

#### Key Architectural Decisions & Rationale:

1. **Single Cross-Phase Persistence Contract (`snapshots/<cluster>_<ts>_baseline.json`)**:
   - The JSON snapshot created in Phase 01 is the **only** persisted state file across all phases of the automation suite.
   - Captures comprehensive, structured cluster metadata (name, API URL, current version, channel, clusterID, timestamp), full node inventory (names, roles parsed from `node-role.kubernetes.io/*` labels, kubelet versions, Ready condition statuses, unschedulable flags), cluster operators (names, versions, Available/Progressing/Degraded conditions), and exposed routes (names, namespaces, hostnames).
   - Ingested strictly in Phase 05 for pre/post upgrade diffing; no intermediate phase state is persisted to disk.

2. **Resilient Cluster Queries with Dedicated Session Scope**:
   - Every `oc get` query (`clusterversion`, `clusteroperators`, `nodes`, `routes`) executes with retry parameters (`retries: 3 / delay: 10 / until: rc == 0`) and `changed_when: false`.
   - All tasks declare `args: executable: /bin/bash` with `set -o pipefail` to ensure robust error capture across piped shell commands.
   - Enforces invariant #3 by targeting the dedicated session kubeconfig (`KUBECONFIG: "{{ cluster_kubeconfig }}"`) scoped under `playbook_dir`, preventing accidental interaction with jump host global configs (`~/.kube/config`).

3. **Strict jq v1.5 Operator Precedence & Syntax Compatibility**:
   - Adheres strictly to jq v1.5 rules: explicit parentheses wrap `//` and `or`/`and` operands to prevent boolean coercion in string extraction pipelines.
   - Uses `to_entries[]? | select(.key | startswith("node-role.kubernetes.io/")) | .key | split("/")[1]` for dynamic role identification without external regex dependencies.
   - Formats outputs cleanly into JSON objects parsed directly by Ansible's `from_json` filter into native in-memory facts.

4. **Dual Edge Verification (`availableUpdates` & `conditionalUpdates`)**:
   - Queries both standard `availableUpdates` and OpenShift 4.10+ `conditionalUpdates` from `ClusterVersion`.
   - Consolidates all verified edges and verifies `upgrade_path[0]` is present before any write or upgrade action occurs.

5. **HARD Gate Enforcement & Zero-Mutation Policy**:
   - If `upgrade_path[0]` is not found in the verified edge set, execution halts immediately with a HARD gate failure (`fail:`).
   - Detailed failure message names the cluster, current version, channel, target hop, available edges, and conditional edges, ensuring full operational visibility.
   - Guarantees zero cluster mutations occur if policy check fails.

6. **Fail-Safe Session Lifecycle Management (`block/rescue/always`)**:
   - Pre-tasks establish authenticated session via `include_role: name=login`.
   - On success, the authenticated session is preserved for Phase 02 through Phase 06.
   - On failure, `rescue:` extracts error details following the standard hierarchy (`stderr` → `stderr_lines` → `msg`), invokes `error_handle` to send alert email and log failure, marks `phase_01_failed: true`, and invokes `logout`.
   - The `always:` block checks `phase_01_failed | default(false) | bool` to guarantee session teardown even if rescue experienced an unhandled error.

7. **Dual Audit Run Logging (.txt and .csv)**:
   - Appends human-readable confirmation to `logs/<cluster>_<ts>.txt`.
   - Automatically checks for existence of `logs/<cluster>_<ts>.csv`, initializes the 7-column CSV header (`timestamp,cluster,task_name,gate_type,status,reason,observed`) upon first write, and logs structured CSV records.

---

### Unit 07: Health Check Roles (`api_check`, `api_readiness`, `co`, `mcp`, `node`, `etcd`)

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created**:
  - `playbooks/roles/api_check/defaults/main.yml`
  - `playbooks/roles/api_check/tasks/main.yml`
  - `playbooks/roles/api_readiness/defaults/main.yml`
  - `playbooks/roles/api_readiness/tasks/main.yml`
  - `playbooks/roles/co/defaults/main.yml`
  - `playbooks/roles/co/tasks/main.yml`
  - `playbooks/roles/mcp/defaults/main.yml`
  - `playbooks/roles/mcp/tasks/main.yml`
  - `playbooks/roles/node/defaults/main.yml`
  - `playbooks/roles/node/tasks/main.yml`
  - `playbooks/roles/etcd/defaults/main.yml`
  - `playbooks/roles/etcd/tasks/main.yml`

#### Key Architectural Decisions & Rationale:

1. **Six Focused Single-Concern Roles**:
   - Each role queries and evaluates exactly one subsystem without cross-contamination.
   - `api_check` verifies active cluster API endpoint against `desired_cluster_api_regex` to prevent operating on the wrong cluster.
   - `api_readiness` validates `/readyz` endpoint returning HTTP 200 payload `ok`.
   - `co` checks OpenShift platform operators for `Available=True` and `Degraded=False`, supporting `co_allow_list` exclusions.
   - `mcp` checks MachineConfigPools for `Updated=True`, `Degraded=False`, and `spec.paused=false`.
   - `node` checks all cluster nodes for `Ready=True`, absence of pressures (`DiskPressure`, `MemoryPressure`, `PIDPressure`), and verifies unschedulable nodes against `allowed_unschedulable_nodes` threshold.
   - `etcd` checks control-plane etcd pods (`app=etcd`) in `openshift-etcd` for `Running` and `Ready=True`, and verifies ClusterOperator `etcd` for quorum health.

2. **Transient Fault Tolerance on All oc Queries**:
   - Every `oc` CLI command enforces `retries: 3 / delay: 10 / until: rc == 0` with `changed_when: false` to withstand API server restarts, transient timeouts, or 503 responses.
   - Shell commands declare `args: executable: /bin/bash` with `set -o pipefail`.

3. **Strict jq v1.5 Compatibility & String Normalization**:
   - All conditional operands and `//` fallbacks are explicitly parenthesized to conform to jq 1.5 operator precedence rules.
   - Condition values are explicitly normalized with `| tostring` in jq to prevent Python bool deserialization mismatches.
   - Array accesses utilize bracket notation (`['pools']`, `['nodes']`, `['operators']`) to eliminate Jinja2 dictionary method collisions.

4. **MachineConfigPool Fact Exposure Contract**:
   - As mandated by the system architecture, `roles/mcp` exports `mcp_parsed_data` and `mcp_all_pools` into host facts for direct consumption by the `monitor` and `remediate` roles.

5. **Structured health_summary Accumulator**:
   - Each role appends a clean dictionary `{ num, name, gate, status, observed }` to `health_summary` via `set_fact` before gate enforcement, enabling downstream report generators (`health-overview.j2`) and alert templates to consume unified validation state.

6. **Dual-Mode Gate Enforcement (`<role>_enforce_gate: true`)**:
   - Each role defaults to immediate HARD gate halt (`fail:`) upon failure.
   - Setting `<role>_enforce_gate: false` enables prevalidation aggregators to run a non-blocking diagnostic sweep across all 14 checks prior to invoking the auto-remediation engine.

### Unit 08a: Auto-Remediation Engine (`remediate` Role)

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created**:
  - `playbooks/roles/remediate/defaults/main.yml`
  - `playbooks/roles/remediate/tasks/main.yml`
  - `playbooks/roles/remediate/tasks/cgroup_v2.yml`
  - `playbooks/roles/remediate/tasks/admin_acks.yml`
  - `playbooks/roles/remediate/tasks/unpause_mcp.yml`
  - `playbooks/roles/remediate/tasks/restart_operator.yml`

#### Key Architectural Decisions & Rationale:

1. **Dedicated, Modular Auto-Remediation Architecture**:
   - Centralizes automated blocker resolution in `roles/remediate/`, decoupling fix logic from diagnostic health checks.
   - Master toggle `auto_remediation_enabled: true` with granular toggles per remediation (`auto_fix_cgroup_v2`, `auto_apply_admin_acks`, `auto_unpause_mcp`, `auto_restart_degraded_operators`).
   - Tier 1 fixes (safe, official Red Hat remediation procedures) default to enabled (`true`). Tier 2 guided recoveries default to disabled (`false`) requiring explicit cluster opt-in.

2. **Strict 5-Step Verification Cycle**:
   - Every remediation module follows an immutable lifecycle: (1) detect condition, (2) verify feature toggle, (3) apply deterministic `oc patch` / command, (4) re-verify condition via live query, (5) update `health_summary` to `AUTO-FIXED` (if re-verification passed) or `FIX-FAILED` (if still failing).

3. **Blocker 1 — CGroup v1 to v2 Migration (`tasks/cgroup_v2.yml`)**:
   - OpenShift 4.19+ deprecates and removes cgroup v1, blocking upgrades with `Upgradeable=False`.
   - Detects `cgroupMode != "v2"` on `nodes.config/cluster`, applies deterministic merge patch `{"spec":{"cgroupMode":"v2"}}`, re-verifies via jsonpath, records `AUTO-FIXED`, and logs action. Node reboots roll out naturally during subsequent MachineConfigPool updates.

4. **Blocker 2 — Dynamic Administrator Acknowledgements (`tasks/admin_acks.yml`)**:
   - Inspects `ClusterVersion` conditions and dynamically extracts required acknowledgement keys matching `ack-[0-9]+\.[0-9]+-api-removals-in-[0-9]+\.[0-9]+`.
   - Idempotently creates `openshift-config/admin-acks` ConfigMap if missing, patches required keys to `"true"`, re-verifies ConfigMap contents, and unblocks `Upgradeable` condition.

5. **Blocker 3 — MachineConfigPool Unpausing (`tasks/unpause_mcp.yml`)**:
   - Detects paused MachineConfigPools and partitions them against `mcp_auto_unpause_list` (default: `['worker', 'master']`).
   - Unpauses permitted pools via JSON patch (`spec.paused: false`), re-verifies pool states, and surfaces warnings if non-permitted pools remain paused.

6. **Blocker 4 — Degraded Operator Pod Restart (`tasks/restart_operator.yml`)**:
   - Tier 2 guided recovery attempting non-destructive operator controller restart.
   - Resolves operator pods across namespaces, deletes degraded pods with `wait: false`, pauses for `operator_restart_grace_seconds` (default: 180s), and re-verifies `Available=True` and `Degraded=False`.

7. **Unified Audit Logging & Client Reporting Integration**:
   - Every automated fix logs a prominent `[AUTO-FIX]` entry to console, text run log (`.txt`), and CSV run log (`.csv`).
   - Successful remediations append structured metadata to `autofix_items` with Red Hat documentation links, enabling `health-overview.j2` to render the automated remediation callout card and blue `AUTO-FIXED ⚙` status pills.

### Unit 08: Capacity, Storage & Disruption Roles (`utilization`, `pv`, `pvc`, `pdb`)

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created**:
  - `playbooks/roles/utilization/defaults/main.yml`
  - `playbooks/roles/utilization/tasks/main.yml`
  - `playbooks/roles/pv/defaults/main.yml`
  - `playbooks/roles/pv/tasks/main.yml`
  - `playbooks/roles/pvc/defaults/main.yml`
  - `playbooks/roles/pvc/tasks/main.yml`
  - `playbooks/roles/pdb/defaults/main.yml`
  - `playbooks/roles/pdb/tasks/main.yml`

#### Key Architectural Decisions & Rationale:

1. **Drain Headroom Invariant Enforcement (`roles/utilization/`)**:
   - Upgrading cluster nodes requires evacuating running workloads sequentially. If cluster-wide resource requests exceed available capacity headroom, node draining triggers pod scheduling starvation or deadlock.
   - Sourced thresholds from `vars/upgrade.yml` (`max_cpu_percent: 90`, `max_memory_percent: 90`).
   - Enforces a HARD gate (`fail:`) with detailed CPU cores and memory GiB allocation diagnostics if thresholds are exceeded.

2. **Strict jq v1.5 Unit Parsing & `rnd2` Formulation**:
   - Queries allocatable capacity from `oc get nodes -o json` and aggregated workload demand from `oc get pods -A --field-selector=status.phase=Running -o json`.
   - Normalizes CPU requests and capacity to millicores (`m`) and memory to bytes (`Ki`, `Mi`, `Gi`, `Ti`, `Pi`, `m`, `k`, `M`, `G`, `T`, `P`).
   - Adheres strictly to jq v1.5 rules by avoiding `round()` and utilizing the custom formulation `def rnd2: . * 100 | floor / 100;` to calculate request percentages and core/GiB values with exact decimal precision.

3. **Persistent Volume & Storage Claim Non-Blocking Advisory Audits (`roles/pv/` and `roles/pvc/`)**:
   - Evaluates storage infrastructure health without halting upgrades for non-critical workloads (enforced strictly as a non-blocking WARN advisory).
   - `roles/pv/` audits all PersistentVolumes to ensure they reside in `Bound` or `Available` phase, surfacing `Failed` or `Released` volumes for administrator attention.
   - `roles/pvc/` audits PersistentVolumeClaims across all namespaces to verify `Bound` status, highlighting `Pending` or `Lost` volume claims.
   - Designed with safe array slicing and null-coalescing (`.items // []`) to guarantee flawless evaluation on clusters with zero persistent storage resources.
   - **Type Coercion Invariant**: Fixed Jinja2 templating comparison crashes (`TypeError: '>' not supported between instances of 'AnsibleUnsafeText' and 'int'`) by explicitly casting volume and claim counts via `(pv_total_count | default(0) | int)` and `(pvc_total_count | default(0) | int)`.
   - **Non-Blocking Gate Policy**: Completely removed any `fail:` tasks from `roles/pv/tasks/main.yml` and `roles/pvc/tasks/main.yml` (`gate: "WARN"`), and initialized `pv_enforce_gate: false` / `pvc_enforce_gate: false` in `prevalidation/tasks/main.yml` and `vars/upgrade.yml`. Storage findings surface as informative warnings in HTML audit reports and emails without halting the upgrade pipeline.

4. **PodDisruptionBudget Deadlock Prevention (`roles/pdb/`)**:
   - Audits PodDisruptionBudgets across all namespaces to prevent node evacuation stalls during MachineConfigPool rolling reboots.
   - Specifically detects zero-disruption deadlocks (`disruptionsAllowed == 0` AND `expectedPods > 0`).
   - Intentionally permits zero-disruption PDBs where `expectedPods == 0` (e.g. scaled-down deployments) as they do not possess running pods that can block node evacuation.
   - Operates with a configurable gate (`fail_on_zero_disruption_pdb: true` default from `vars/upgrade.yml`), triggering a HARD gate halt in strict environments while supporting advisory WARN evaluation when disabled.

5. **Structured health_summary Accumulator & Report Integration**:
   - Every role appends structured dictionary records `{ num, name, gate, status, observed }` to `health_summary` via `set_fact` before gate enforcement.
   - Emits clean `debug` messages for real-time console tracing and ensures full compatibility with the unified `health-overview.j2` report template.

### Unit 09: Prevalidation Aggregator Role & Phase 02 (`prevalidation`, `02_Pre_upgrade_check.yaml`)

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created**:
  - `playbooks/roles/prevalidation/defaults/main.yml`
  - `playbooks/roles/prevalidation/tasks/main.yml`
  - `playbooks/02_Pre_upgrade_check.yaml`

#### Key Architectural Decisions & Rationale:

1. **The 14-Check Prevalidation Contract (`roles/prevalidation/`)**:
   - Aggregates the 14 mandatory health, capacity, and disruption checks prior to cluster upgrade initiation (8 HARD gates, 6 WARN advisories).
   - Coordinates roles: `co` (Check 01), `node` (Check 02), `mcp` (Check 03), `api_check` (Check 04), `api_readiness` (Check 05), `etcd` (Check 06), `utilization` (Check 08), `pv` (Check 10), `pvc` (Check 11), `pdb` (Check 12).
   - Implements inline evaluation for:
     - Check 07: Administrator Acknowledgements (`ClusterVersion` conditions vs `openshift-config/admin-acks`).
     - Check 09: Pending Node CSRs (`oc get csr` with jq v1.5).
     - Check 13: Critical Namespace Pod Health (`oc get pods -A` auditing `openshift-*` core pods for CrashLoopBackOff/Error).
     - Check 14: CGroup Mode Compatibility (`nodes.config/cluster` cgroupMode v2 enforcement for target >= 4.19). Employs clean string formatting without backslash-escaped quotes to ensure syntax compatibility across all Jinja2 lexer versions.

2. **Gate Suppression During Initial Scan**:
   - To achieve comprehensive reporting and allow the auto-remediation engine to resolve fixable blockers, individual role gates are suppressed during the initial scan (`*_enforce_gate: false`).
   - Every check writes its findings to the unified `health_summary` list before any gate evaluation, ensuring administrators receive complete diagnostic visibility.

3. **Two-Stage One-Touch Remediation Workflow (`02_Pre_upgrade_check.yaml`)**:
   - Stage 1: The playbook evaluates initial findings in `health_summary`. If any auto-fixable check failed (`CGroup Mode Compatibility`, `Administrator Acknowledgement (Admin-Acks)`, `MachineConfigPools Synchronization`, or `ClusterOperators Health`), the phase dynamically sets trigger facts and invokes `roles/remediate`.
   - Stage 2: The `remediate` role applies deterministic Red Hat-approved patches, verifies the state, and transforms the corresponding records in `health_summary` to `AUTO-FIXED` (or `FIX-FAILED`).

4. **Residual HARD Gate Enforcement & Fail-Safe Teardown**:
   - Evaluates residual HARD failures after the remediation pass. If any check remains `FAIL` or `FIX-FAILED`, the playbook triggers a HARD gate `fail:`, halting execution before any upgrade mutations occur.
   - The standardized `rescue:` block extracts error details hierarchically, detects RBAC permissions errors, invokes `error_handle` (sending alert email and logging), and executes `logout`.

5. **Client HTML Report & Dual Audit Logging**:
   - On successful validation (all HARD checks `PASS` or `AUTO-FIXED`), invokes `roles/report` to render `health-overview.j2` into `output/{{ cluster_name }}_prevalidation_{{ run_timestamp }}.html`.
   - Records structured audit logs to human-readable `.txt` and machine-parseable `.csv` files.

### Unit 10: Upgrade Role, Per-Hop Task (`tasks/hop.yml`) & Phase 03 Playbook (`03_Initiate_upgrade.yaml`)

- **Status**: Completed
- **Date**: 2026-09-02
- **Artifacts Created**:
  - `playbooks/roles/upgrade/defaults/main.yml`
  - `playbooks/roles/upgrade/tasks/main.yml`
  - `playbooks/tasks/hop.yml`
  - `playbooks/04_Live_monitoring_upgrade.yaml`
  - `playbooks/03_Initiate_upgrade.yaml`

#### Key Architectural Decisions & Rationale:

1. **Sequential Minor-Version Upgrade Loop (`03_Initiate_upgrade.yaml`)**:
   - Loops over `upgrade_path` executing `include_tasks: tasks/hop.yml` with `loop_var: hop_item` and `index_var: hop_index`.
   - Strictly avoids `import_playbook` inside loops, guaranteeing full execution compatibility on **Ansible 2.7.17** and **Ansible 2.14.18**.
   - Reuses the existing authenticated session established in Phase 01/02 (with an automated fallback login check for standalone invocations).

2. **The 7-Step Per-Hop Execution Contract (`tasks/hop.yml`)**:
   - Step 1: Hop Metadata Computation — computes iteration facts (`hop_number`, `hop_total`, `hop_label: {{ hop_number }}/{{ hop_total }}`).
   - Step 2: Logging & Terminal UI — displays formatted initiation banner and appends start entries to `.txt` and `.csv` run logs.
   - Step 3: Pre-Hop Settle Assertion — verifies the cluster is in a stable, unblocked state before triggering mutation (ClusterVersion is not actively progressing another version, zero degraded MCPs, zero updating MCPs, and zero degraded ClusterOperators).
   - Step 4: Role Invocation (`roles/upgrade`) — executes channel switch, edge verification, dynamic admin-ack check, and upgrade trigger with pre-computed facts to avoid Jinja2 variable recursion.
   - Step 5: Live Monitoring Hand-off — hands off to `playbooks/04_Live_monitoring_upgrade.yaml` to track live rollout progress and heartbeats.
   - Step 6: Settle-Gate Verification — strictly asserts that the cluster has fully settled at target version (cv version matches target, Available=True, Progressing=False, zero degraded/progressing/unavailable COs, and all MCPs Updated=True).
   - Step 7: Completion Notification — formats and dispatches hop-complete email via `roles/sendmail` with the Prevalidation HTML audit report attached, and emits completion records to `.txt` and `.csv`.

3. **Guarded Cluster Mutation & Force Guard (`roles/upgrade/`)**:
   - The single permitted write mutation against the cluster is `oc adm upgrade --to={{ target_version }}`.
   - Channel switching dynamically derives the target channel (`stable-X.Y` from `target_version | regex_search('^[0-9]+\.[0-9]+')`) and updates the cluster channel only if different from the live channel.
   - Re-verifies that `target_version` exists in live `availableUpdates` or `conditionalUpdates` (with up to 6 retry attempts to absorb Cincinnati propagation delays) before triggering the upgrade command.
   - Strictly forbids automatic force upgrades: the `--to-image` emergency path is gated behind `allow_force_upgrade: false` and requires an explicit confirmation token `CONFIRM_FORCE_UPGRADE`, failing unconditionally if invoked automatically.
   - Incorporates dry-run simulation mode (`dry_run: true`) to safely test the entire orchestration lifecycle without mutating live clusters.

4. **Fail-Safe Hop Enclosure & Error Extraction**:
   - Both `tasks/hop.yml` and `03_Initiate_upgrade.yaml` are wrapped in `block/rescue/always`.
   - The standardized rescue block extracts error details hierarchically (`stderr` → `stderr_lines` → `msg`), detects RBAC permission errors, invokes `error_handle` (sending alert email and logging), and executes `logout` to guarantee session teardown.

### Unit 11: Live Monitoring & Settle-Gate (`monitor` Role, `04_Live_monitoring_upgrade.yaml`)

- **Status**: Completed
- **Date**: 2026-09-03
- **Artifacts Created / Modified**:
  - `playbooks/roles/monitor/defaults/main.yml`
  - `playbooks/roles/monitor/tasks/main.yml`
  - `playbooks/roles/monitor/tasks/poll_iteration.yml`
  - `playbooks/04_Live_monitoring_upgrade.yaml`
  - `playbooks/tasks/hop.yml` (enhanced notification facts)

#### Key Architectural Decisions & Rationale:

1. **Inline Bounded Polling Loop (`roles/monitor/`)**:
   - Executes live upgrade tracking inline within the Ansible execution thread using a bounded loop calculated dynamically from `hop_timeout_minutes / poll_interval_minutes` (default: 90m / 2m = 45 iterations).
   - Driven via `include_tasks: poll_iteration.yml` looping over `range(1, monitor_max_iterations + 1)`.
   - Completely avoids detached background daemon processes or brittle shell sleep subprocesses, keeping all execution visible in Ansible output and run logs.
   - Evaluates a skip guard `when: not (hop_settled | default(false) | bool)` on every iteration, so that the moment the cluster settles, all remaining iterations terminate in milliseconds.

2. **Rollout Progress & State Change Detection**:
   - Computes an aggregate rollout progress percentage (0–100%) combining ClusterVersion control plane progression (0–50%) and worker MachineConfigPool rollout (50–100%).
   - Generates a deterministic cluster state signature combining ClusterVersion progressing condition, current version, updating MCPs, degraded MCPs, and actively updating/degraded nodes.
   - Detects state changes vs the previous poll; any state transition (e.g. node enters draining/rebooting, MCP reports degraded, or active node switches) triggers an immediate notification email.
   - Enforces a 20-minute heartbeat cadence (`heartbeat_minutes: 20`): if 20 minutes elapse without a state change, a progress heartbeat email is dispatched automatically.

3. **Node Stall Detection & Tier 2 Auto-Remediation**:
   - Tracks the duration a single node remains in the active updating state (`spec.unschedulable: true` or MCD `Working` state).
   - If a single node exceeds `node_stall_threshold_minutes: 30` and `auto_force_stalled_node: true` is enabled, executes `oc debug node/<node> -- chroot /host touch /run/machine-config-daemon-force` to unstick the MachineConfigDaemon rollout.
   - Emits structured `[AUTO-FIX]` logs to console, `.txt` run log, and `.csv` audit log.

4. **Settle-Gate Contract Enforcement**:
   - Settle-gate executes at the conclusion of monitoring and acts as the mandatory entry condition for subsequent hops.
   - Strictly asserts:
     - `ClusterVersion` version matches target, `Available == "True"`, `Progressing == "False"`, and history state is `"Completed"`.
     - All `ClusterOperators` are `Available == "True"`, `Progressing == "False"`, and `Degraded == "False"` (excluding `co_allow_list`).
     - All `MachineConfigPools` are `Updated == "True"`, `Updating == "False"`, and `Degraded == "False"`.
   - On pass, exports `hop_settled: true` and `hop_elapsed_duration` for downstream notification cards.
   - If the polling loop exhausts its bounded iterations without settling, the HARD timeout guard fails explicitly with: `[HARD GATE FAILURE] Upgrade hop exceeded 90m timeout without settling.`

### Unit 12: Postvalidation Role & Phase 05 Playbook (`postvalidation` Role, `05_post_Upgrade_Checks.yaml`)

- **Status**: Completed
- **Date**: 2026-09-03
- **Artifacts Created**:
  - `playbooks/roles/postvalidation/defaults/main.yml`
  - `playbooks/roles/postvalidation/tasks/main.yml`
  - `playbooks/05_post_Upgrade_Checks.yaml`

#### Key Architectural Decisions & Rationale:

1. **The 10-Check Postvalidation Contract (`roles/postvalidation/`)**:
   - Executes post-upgrade cluster verification following the completion of all minor upgrade hops (6 HARD gates, 4 WARN advisories).
   - Check 01: Final ClusterVersion (HARD) — confirms `cv` has settled at the final target version in `upgrade_path`, `Available=True`, `Progressing=False`, and `Degraded=False`.
   - Check 02: ClusterOperators Status (HARD) — ensures all platform operators are `Available=True`, `Degraded=False`, and `Progressing=False`, excluding optional entries in `co_allow_list`.
   - Check 03: MachineConfigPool Status (HARD) — verifies all pools are `Updated=True`, `Updating=False`, and `Degraded=False`.
   - Check 04: Node Readiness & Version (HARD) — validates all nodes are `Ready=True` and dynamically derives the expected Kubernetes kubelet minor version prefix (`1.(Y+13)` e.g. `v1.29.*` for OpenShift 4.16), verifying that all nodes have completed node reboot and rollout.
   - Check 05: Node Pressures (HARD) — ensures zero `DiskPressure`, `MemoryPressure`, or `PIDPressure` across all nodes and asserts unschedulable nodes are within `allowed_unschedulable_nodes` threshold.
   - Check 06: etcd Cluster Health (HARD) — verifies >= 3 control-plane etcd pods in `openshift-etcd` are Running/Ready and `clusteroperator/etcd` is `Available=True` and `Degraded=False`.
   - Check 07: PersistentVolume Status (WARN) — audits PVs to confirm storage volumes remain in `Bound` or `Available` state.
   - Check 08: Core Namespace Pods (WARN) — audits platform pods in `openshift-*` namespaces to confirm absence of `CrashLoopBackOff`, `ImagePullBackOff`, `ErrImagePull`, or `Failed` phases.
   - Check 09: Firing Critical Alerts (WARN) — queries the OpenShift Prometheus / Thanos Querier API for active alerts with `severity: critical` and `state: firing`.
   - Check 10: Baseline Diff Audit (WARN) — performs full inventory diffing against the Phase 01 baseline snapshot.

2. **The Baseline Diff Engine (Check 10)**:
   - Ingests the Phase 01 baseline snapshot (`snapshots/<cluster>_<ts>_baseline.json`) using `slurp` and `from_json`. If `baseline_snapshot_file_path` is not explicitly passed, auto-detects the most recent baseline snapshot file in `snapshots/`.
   - Computes structural parity across three key infrastructure vectors:
     - Node Parity: Compares baseline node inventory against live nodes (`oc get nodes -o json`). Flags any missing nodes or negative count deltas.
     - Operator Parity: Compares baseline operator inventory against live operators (`oc get clusteroperators -o json`). Flags any missing operators and tracks version progression.
     - Route Availability: Compares baseline route inventory (`namespace/name`) against live routes (`oc get routes -A -o json`). Confirms that all exposed cluster application endpoints remain intact post-upgrade.
   - Emits structured parity metrics to the health record and client HTML report.

3. **Session Preservation Contract (`05_post_Upgrade_Checks.yaml`)**:
   - In accordance with the 7-process architecture invariant, Phase 05 **does NOT log out on success**.
   - Preserves the authenticated session established in Phase 01 so Phase 06 can perform OLM operator compatibility checks, approval of InstallPlans, and CSV validation without re-authenticating.
   - Wraps execution in `block/rescue/always`. If any gate fails or an unexpected error occurs, `rescue:` extracts error details hierarchically, invokes `error_handle` to alert the team, sets `phase_05_failed: true`, and invokes `roles/logout` to guarantee fail-safe token revocation.

4. **Client-Facing Postvalidation HTML Report Generation**:
   - Invokes `roles/report` with `report_type: "postvalidation"` and `report_title: "Post-Upgrade Validation Report"`.
   - Renders `health-overview.j2` into `output/{{ cluster_name }}_postvalidation_{{ run_timestamp }}.html`.
   - Populates 5-tile summary metrics, status pills, and collapsible inspection details.


### Unit 13: Operator Lifecycle Roles & Phase 06 Playbook (`operator_compat`, `operator_upgrade`, `operator_validate`, `06_Operator_Upgrade.yaml`)

- **Status**: Completed
- **Date**: 2026-09-03
- **Artifacts Created / Modified**:
  - `playbooks/roles/operator_compat/defaults/main.yml`
  - `playbooks/roles/operator_compat/tasks/scan_subscription.yml`
  - `playbooks/roles/operator_compat/tasks/main.yml`
  - `playbooks/roles/operator_upgrade/defaults/main.yml`
  - `playbooks/roles/operator_upgrade/tasks/approve_installplan.yml`
  - `playbooks/roles/operator_upgrade/tasks/poll_csv_iteration.yml`
  - `playbooks/roles/operator_upgrade/tasks/main.yml`
  - `playbooks/roles/operator_validate/defaults/main.yml`
  - `playbooks/roles/operator_validate/tasks/validate_subscription.yml`
  - `playbooks/roles/operator_validate/tasks/main.yml`
  - `playbooks/06_Operator_Upgrade.yaml`
  - `playbooks/templates/progress-mail.j2` (added `is_upgrade_complete` / `all_phases_complete` support)
  - `playbooks/main.yml` (uncommented Phase 01 through Phase 06 orchestrator imports)

#### Key Architectural Decisions & Rationale:

1. **Phase 06 Lifecycle & Independent Failure Domain**:
   - Numbered consistently as Phase 06 (`06_Operator_Upgrade.yaml`) maintaining the clean sequential automation chain (`01 → 02 → 03/04 → 05 → 06`).
   - In accordance with the non-interfering failure domain invariant, an operator upgrade failure in Phase 06 is recorded as a HARD finding for this phase only; it never rolls back or invalidates completed cluster version hops.
   - Serves as the definitive closeout phase executing token revocation and session teardown via `roles/logout` upon completion.

2. **Operator Compatibility Scanning (`roles/operator_compat/`)**:
   - Resiliently queries all installed OLM `Subscription` resources via `oc get subscriptions.operators.coreos.com -A -o json` with jq v1.5 parsing.
   - For each subscription, queries `PackageManifest` across source namespaces and parses available update channels.
   - Identifies if a channel matching the cluster target minor version (e.g. `stable-4.16`, `fast-4.16`, or `4.16`) is available, and flags channel switch recommendations in `operator_compat_plan`.
   - Cleanly handles clusters with zero installed OLM operators without failure.

3. **Sequential InstallPlan Approval & Rollout Monitoring (`roles/operator_upgrade/`)**:
   - Discovers unapproved manual InstallPlans (`spec.approved == false`) across all namespaces.
   - Sequentially approves each InstallPlan via `oc patch installplan <name> -n <ns> --type=merge -p '{"spec":{"approved":true}}'`.
   - Monitors CSV rollout in a bounded polling loop calculated from `operator_upgrade_timeout_seconds // operator_upgrade_poll_interval_seconds` (default: 600s / 15s = 40 iterations).
   - **Tier 2 Automated Recovery**: If a CSV fails with `InstallCheckFailed` or stalls, deletes the failed CSV once (`oc delete csv <name> -n <ns>`) to trigger OLM Subscription reconciliation before reporting failure.
   - Records `[AUTO-FIX]` events to run logs and `autofix_items`.

4. **Post-Upgrade Operator Health Validation & Client HTML Report (`roles/operator_validate/`)**:
   - Asserts that all installed subscriptions have valid `installedCSV` references matching active CSVs in the namespace.
   - Asserts that all active CSVs report `status.phase == "Succeeded"`.
   - Invokes `roles/report` with `report_type: "operators"` and `is_operator_report: true` to render `health-overview.j2` into `output/{{ cluster_name }}_operators_{{ run_timestamp }}.html` displaying subscription namespaces, installed CSVs, channels, approval modes, and status pills.
   - Enforces HARD gate halting closeout if any operator remains in a failed state.

5. **Upgrade-Complete Digest Email & 4-Attachment Manifest (`06_Operator_Upgrade.yaml`)**:
   - Upon full workflow success, dispatches the final completion email via `roles/sendmail` using `progress-mail.j2` with the `ALL PHASES COMPLETE ✔` header badge and 100% progress indicator.
   - Resolves and attaches all 4 core audit artifacts:
     1. Prevalidation HTML Report (`<cluster>_prevalidation_<ts>.html`)
     2. Postvalidation HTML Report (`<cluster>_postvalidation_<ts>.html`)
     3. Operator Validation HTML Report (`<cluster>_operators_<ts>.html`)
     4. Complete Run Log (`logs/<cluster>_<ts>.txt`)
   - Performs definitive session logout and token revocation via `roles/logout` in both success and rescue branches.


### Unit 14: Master Wiring & End-to-End Integration (`main.yml`)

- **Status**: Completed
- **Date**: 2026-09-03
- **Artifacts Created / Modified**:
  - `playbooks/main.yml`

#### Key Architectural Decisions & Rationale:

1. **Fixed Master Process Chaining (`playbooks/main.yml`)**:
   - Master orchestrator establishes the definitive end-to-end execution pipeline across all six automation phases:
     ```
     01_Policy_Check.yaml
         └── 02_Pre_upgrade_check.yaml
                 └── [Dry-Run Intercept: Stop if dry_run=true]
                         └── 03_Initiate_upgrade.yaml (loops hop.yml ──▶ 04_Live_monitoring)
                                 └── 05_post_Upgrade_Checks.yaml
                                         └── 06_Operator_Upgrade.yaml
     ```
   - Uses `import_playbook` for isolated phase boundaries, guaranteeing play-level state isolation while preserving host facts (such as cluster session and kubeconfig) set on `localhost`.
   - Ingests all 6 `vars/` files (`upgrade.yml`, `secrets.yml`, `paths.yml`, `smtp.yml`, `report_vars.yml`, `api_regex.yml`) with dual-version headers (`# Targets: Ansible 2.7.17 / 2.14.18`).
   - Asserts non-empty values for mandatory runtime inputs (`cluster_name` and `upgrade_path`) before triggering phase execution.

2. **Dry-Run Intercept & Early Teardown**:
   - When `dry_run: true` is passed (via CLI `--dry-run`), the master workflow executes Phase 01 (baseline snapshot and edge validation) and Phase 02 (14-check prevalidation and auto-remediation scan), generating the client HTML prevalidation report.
   - Immediately following Phase 02, the dedicated `Dry-Run Intercept & Early Teardown` play executes (`when: dry_run | default(false) | bool`).
   - Invokes `roles/logout` to cleanly revoke the OpenShift session token and delete temporary kubeconfig files.
   - Invokes `meta: end_play` and guards all downstream mutation phases (03, 05, 06) with `when: not (dry_run | default(false) | bool)`, preventing any cluster mutation or disruption.

3. **Selective Phase Execution (`skip_to_phase`)**:
   - Enforces Jinja2 integer evaluation guards (`when: skip_to_phase is not defined or (skip_to_phase | int) <= N`) across all imported phase playbooks.
   - Allows operators to bypass early validation phases during recovery workflows (e.g. `--skip-to-phase 05` to execute postvalidation and baseline diff, or `--skip-to-phase 06` to trigger operator compatibility and InstallPlan approval).
   - Seamlessly normalizes string and integer inputs (`"05"`, `5`, `"06"`).

4. **Session Continuity Invariant**:
   - A single authenticated cluster session established in Phase 01 (or verified/re-established via fallback `pre_tasks:` in standalone phase runs) persists across Phase 02, Phase 03, Phase 05, into Phase 06.
   - Definitive token revocation and kubeconfig removal is guaranteed in Phase 06 `always:` block or in the Dry-Run Intercept play, ensuring zero leftover security artifacts.
---

## 4. Verification & Testing

### Unit 01 Verification Results:
- **Directory Hierarchy**: All required subdirectories in `playbooks/` verified present.
- **YAML Syntax Validation**: All 6 files parsed with `yaml.safe_load()` in Python; 0 syntax errors.
- **Security Check**: Verified no plaintext passwords, bearer tokens, or sensitive API secrets exist in the repository.
- **Shell Library Check**: `playbooks/scripts/cli_helpers.sh` syntax verified; library guard prevents direct execution and requires sourcing.

### Unit 02 Verification Results:
- **Script Executability**: `chmod +x playbooks/00_Run.sh` applied and verified.
- **Shell Syntax Validation**: `bash -n playbooks/00_Run.sh` and `bash -n playbooks/scripts/cli_helpers.sh` passed with zero errors.
- **Help Screen**: `./00_Run.sh --help` renders formatted ASCII banner and options screen (exit code 0).
- **Flag Validation**: Passing unknown flags returns error and exits with code 1.
- **Pre-flight Dependency Check**: Executing on environment lacking `ansible-playbook`/`oc`/`jq` halts with clear missing-tool errors (exit code 1).
- **Configuration & Cluster Validation**: Passing `--cluster nonexistent_cluster` correctly detects missing configuration in `vars/secrets.yml` and exits with code 3.
- **Concurrency Run Lock**: Simulating active PID in `/tmp/aro-upgrade-cluster_d01.lock` correctly blocks parallel execution (exit code 1). Normal execution acquires lock and removes it upon exit.
- **Simulation Execution**: Dry run (`--cluster cluster_d01 --no-menu --dry-run --yes`) verifies visual journey diagram, risk assessment box, JSON extra-vars encoding, live log teeing (`logs/cluster_d01_<ts>.txt`), and formatted 72-column post-run summary (exit code 0).
- **YAML Syntax Validation**: `main.yml` parsed with `yaml.safe_load()`; syntax valid.

### Unit 03 Verification Results:
- **Role YAML Syntax Validation**: Python `yaml.safe_load()` parsing of `roles/login/defaults/main.yml`, `roles/login/tasks/main.yml`, `roles/logout/defaults/main.yml`, and `roles/logout/tasks/main.yml`; 0 syntax errors.
- **Dual-Version Compatibility Compliance**: All files verified for `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` and `# MIGRATION 2.14:` headers.
- **Task Naming & Deprecation Audit**: 100% of tasks explicitly named; verified zero occurrences of deprecated parameters (e.g. `warn:`).
- **Security Audit**: `no_log: true` confirmed on all credential assertion and `oc login` tasks; credentials sourced via variable references.
- **Regex Validation Verification**: Python regex testing confirmed `desired_cluster_api_regex` correctly matches valid ARO API endpoints (`https://api.aro-d01.example.com:6443`) and rejects non-standard or invalid ports/protocols.
- **Teardown Safety**: Verified `logout` tasks declare `failed_when: false` to ensure guaranteed execution in `always:` blocks without masking playbook failures.

### Unit 04 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed `playbooks/roles/sendmail/defaults/main.yml` (12 default keys) and `playbooks/roles/sendmail/tasks/main.yml` (5 tasks); 0 syntax errors.
- **Task Naming & Deprecation Audit**: All 5 tasks explicitly named; 0 deprecated parameters detected.
- **Native Mail Dispatch Verification**: Confirmed `mail` task targets localhost with required parameters (`host`, `port`, `from`, `to`, `subject`, `body`, `subtype`, `charset`, `attach`, `username`, `password`, `secure`).
- **Post-Dispatch Fact Reset Audit**: Confirmed task explicitly resets `mail_html_body`, `mail_final_body`, `mail_attachments`, `mail_template`, and `resolved_template_path` to empty values.
- **Error Report Template (`error-report.j2`)**: Tested under strict undefined settings; verified clean rendering with defaults; verified conditional rendering of RBAC warning callout, missing verb/resource highlighting, and `oc adm policy` remediation command when `is_rbac_error` is true.
- **Progress Email Template (`progress-mail.j2`)**: Tested under strict undefined settings; verified compact header, MCP table, active nodes, degraded node warning callouts, and `HOP COMPLETE ✔` settle-gate state.
- **Health Overview Template (`health-overview.j2`)**: Tested under strict undefined settings; verified 5 summary metric tiles, status table with `PASS ✔`, `WARN !`, `FAIL ✖`, `AUTO-FIXED ⚙` (blue `#1d4ed8`), and `FIX-FAILED ⚠` (orange `#c2410c`) pills, automated remediation callout, OLM operator lifecycle table, and print expansion styles.
- **Universal Boolean Normalization**: Verified templates handle boolean values and string representations (`[true, 'True', 'true', 1, '1']`) without relying on non-standard Jinja2 filters.
- **Path Resolution Variations**: Tested and validated path resolution for relative names (`error-report.j2`), template-prefixed names (`templates/error-report.j2`), absolute Unix paths (`/opt/...`), and absolute Windows paths (`C:/...`).

### Unit 05 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` parsed `error_handle/defaults/main.yml`, `error_handle/tasks/main.yml`, `report/defaults/main.yml`, and `report/tasks/main.yml`; 0 syntax errors.
- **Header & Task Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` headers in all 4 files; verified all 14 `error_handle` tasks and 12 `report` tasks are explicitly named; 0 deprecated parameters (e.g. `warn:`).
- **Anti-Pattern Compliance**: Confirmed zero references to `ansible_failed_task.name` and zero bare `include:` statements across all files.
- **Hierarchical Error Extraction Simulation**: Verified priority order extracts `stderr` before `stderr_lines` before `msg` before fallback string.
- **RBAC Detection Simulation**: Verified detection accurately identifies authorization denials (`forbidden`, `cannot patch`, `unauthorized`, `cannot get`, `cannot list`) without false positives on network timeouts.
- **Dual Logging Formatter Verification**: Verified exact formatted `.txt` entries and sanitized, escaped `.csv` records with header initialization.
- **Report Metric & Verdict Engine**: Verified metric counting and deterministic verdict resolution (`FAIL` > `AUTO-FIXED` > `WARN` > `PASS`).
- **End-to-End Template Rendering**: Verified `health-overview.j2` renders standalone HTML (15,921 bytes) with metric tiles, status pills, and autofix callouts; verified `error-report.j2` renders failure card (12,135 bytes) with RBAC alert box and remediation command.

### Unit 06 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed `playbooks/roles/snapshot/defaults/main.yml`, `playbooks/roles/snapshot/tasks/main.yml`, and `playbooks/01_Policy_Check.yaml`; 0 syntax errors.
- **Header & Standards Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` headers in all 3 files; verified all 10 `snapshot` tasks and 21 `01_Policy_Check` tasks are explicitly named; 0 occurrences of deprecated `warn:` or bare `include:`.
- **Anti-Pattern Compliance**: Confirmed zero references to `ansible_failed_task.name` in `01_Policy_Check.yaml` rescue block; error details resolved via hierarchical `stderr` → `stderr_lines` → `msg` extraction.
- **jq v1.5 Compatibility Audit**: All jq filter strings verified for strict jq 1.5 operator precedence (parenthesized `//` and `or` expressions) and executed cleanly against mock OpenShift `ClusterVersion`, `ClusterOperator`, `Node`, and `Route` data.
- **Snapshot Serialization**: Verified `baseline_dict` assembly and JSON formatting (`to_nice_json` / `from_json`) with cluster metadata, node roles, operator conditions, and route hosts.
- **Update Edge Validation Simulation**: Tested and verified edge verification logic against valid available edges, valid conditional edges, and invalid/skipped hops triggering HARD gate failure.
- **CSV Logging Schema**: Verified exact 7-column CSV output format matching `timestamp,cluster,task_name,gate_type,status,reason,observed`.

### Unit 07 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed all 12 files (`defaults/main.yml` and `tasks/main.yml` for `api_check`, `api_readiness`, `co`, `mcp`, `node`, `etcd`); 0 syntax errors.
- **Header & Standards Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` headers in all 12 files; verified all 43 tasks across the 6 roles are explicitly named; 0 occurrences of deprecated `warn:`, 0 bare `include:`.
- **Transient Fault Tolerance Audit**: Verified 100% of cluster query tasks (`oc whoami`, `oc get --raw=/readyz`, `oc get clusteroperators`, `oc get mcp`, `oc get nodes`, `oc get pods`, `oc get clusteroperator etcd`) configure retry parameters (`retries: 3 / delay: 10 / until: rc == 0`) and `changed_when: false`.
- **Shell & Pipefail Safety**: Verified all shell query tasks using pipelines declare `set -o pipefail` and `args: executable: /bin/bash`.
- **jq v1.5 Compatibility & Precedence**: Verified all jq filter strings parenthesize conditional operands and `//` fallback expressions; validated absence of unsupported jq functions (e.g. `round()`); confirmed string conversion `| tostring` for OpenShift condition booleans.
- **Mock Evaluation & Filtering Logic**: Tested and verified unit logic in Python test harness for:
  - `api_check`: Exact regex matching against `desired_cluster_api_regex` and rejection of non-matching endpoints.
  - `api_readiness`: Valid `/readyz` response parsing (`ok`) and non-zero rc failure handling.
  - `co`: Detection of degraded/unavailable operators and allow-list (`co_allow_list`) exclusion filtering.
  - `mcp`: Detection of paused, degraded, and not-updated pools, plus verification of `mcp_parsed_data` and `mcp_all_pools` fact exports.
  - `node`: Detection of unready nodes, resource pressures (disk, memory, PID), and evaluation of unschedulable nodes against `allowed_unschedulable_nodes` threshold.
  - `etcd`: Quorum verification across control-plane pods (Running & Ready) and ClusterOperator etcd condition states.
- **Report Template Integration**: Verified end-to-end Jinja2 template rendering using `playbooks/templates/health-overview.j2` with all 6 health check records; verified HTML generation (17,030 bytes) with metric tiles and status pills.

### Unit 08a Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed all 6 files (`defaults/main.yml`, `tasks/main.yml`, `tasks/cgroup_v2.yml`, `tasks/admin_acks.yml`, `tasks/unpause_mcp.yml`, `tasks/restart_operator.yml`); 0 syntax errors.
- **Header & Standards Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` headers in all 6 files; verified all 84 tasks across the role are explicitly named; 0 occurrences of deprecated `warn:`, 0 bare `include:`, shell tasks with pipefail declare `args: executable: /bin/bash`.
- **Logic & Regex Verification**:
  - Admin-ack regex extraction confirmed against OpenShift API removal notice strings (`ack-4.15-api-removals-in-4.16`).
  - MCP allow-list partitioning verified for permitted (`worker`, `master`) vs blocked custom pools.
  - CGroup v2 patch and verification logic verified in mock test harness.
  - `health_summary` list transformation verified for `AUTO-FIXED` and `FIX-FAILED` status transitions.
- **End-to-End Template Integration**: Verified `health-overview.j2` renders valid HTML (15,744 bytes) displaying the Automated Remediation Applied callout card, documentation reference links, and `AUTO-FIXED` status badge pills.

### Unit 08 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed all 8 files (`defaults/main.yml` and `tasks/main.yml` for `utilization`, `pv`, `pvc`, `pdb`); 0 syntax errors.
- **Header & Standards Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` and `# MIGRATION 2.14:` headers in all 8 files; verified all 31 tasks across the 4 roles are explicitly named; 0 occurrences of deprecated `warn:`, 0 bare `include:`, shell tasks with pipefail declare `args: executable: /bin/bash`.
- **Transient Fault Tolerance Audit**: Verified 100% of cluster query tasks (`oc get nodes`, `oc get pods`, `oc get pv`, `oc get pvc`, `oc get pdb`) configure retry parameters (`retries: 3 / delay: 10 / until: rc == 0`) and `changed_when: false`.
- **Logic & Unit Calculations**:
  - `utilization`: Verified CPU unit conversion (cores, millicores, microcores) and memory unit conversion (Ki, Mi, Gi, Ti, Pi) against mock cluster data (48 cores allocatable, 20 cores requested = 41.66%; 192 GiB allocatable, 40 GiB requested = 20.83%) matching jq v1.5 `rnd2` rounding rules.
  - `pv`: Verified handling of empty clusters (0 PVs -> PASS), healthy PVs (Bound/Available -> PASS), and problematic PVs (Failed/Released -> WARN).
  - `pvc`: Verified handling of empty clusters (0 PVCs -> PASS), healthy PVCs (Bound -> PASS), and unfulfilled PVCs (Pending/Lost -> WARN).
  - `pdb`: Verified handling of empty clusters (0 PDBs -> PASS), healthy PDBs (disruptionsAllowed > 0 -> PASS), scaled-down PDBs (disruptionsAllowed == 0, expectedPods == 0 -> PASS), and deadlock PDBs (disruptionsAllowed == 0, expectedPods > 0 -> FAIL in strict mode).
- **Report Template Integration**: Verified end-to-end Jinja2 template rendering using `playbooks/templates/health-overview.j2` with all 10 cumulative validation checks; verified HTML generation (19,727 bytes) with metric tiles and status pills.

### Unit 09 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed all 3 files (`roles/prevalidation/defaults/main.yml`, `roles/prevalidation/tasks/main.yml`, `02_Pre_upgrade_check.yaml`); 0 syntax errors.
- **Header & Standards Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` headers across all files; 100% of tasks named; 0 occurrences of deprecated `warn:`; 0 bare `include:` statements; all shell tasks using `pipefail` declare `args: executable: /bin/bash`.
- **Anti-Pattern Compliance**: Confirmed zero references to `ansible_failed_task.name` in `02_Pre_upgrade_check.yaml` rescue block; error details resolved hierarchically via `stderr` → `stderr_lines` → `msg`.
- **14-Check Prevalidation Contract Mapping**:
  - Verified sequential orchestration of all 14 checks: Check 01 (`co`), Check 02 (`node`), Check 03 (`mcp`), Check 04 (`api_check`), Check 05 (`api_readiness`), Check 06 (`etcd`), Check 07 (`admin_acks`), Check 08 (`utilization`), Check 09 (`csr`), Check 10 (`pv`), Check 11 (`pvc`), Check 12 (`pdb`), Check 13 (`critical_pods`), Check 14 (`cgroup_mode`).
- **Inline Checks Logic**:
  - Check 07 (Admin-Acks): Verified regex extraction (`ack-4.15-api-removals-in-4.16`), ConfigMap missing detection -> FAIL, and ConfigMap satisfied -> PASS.
  - Check 09 (CSRs): Verified pending condition filter extracting unapproved certificates as WARN and reporting 0 pending as PASS.
  - Check 13 (Critical Pods): Verified filtering of core `openshift-*` containers with CrashLoopBackOff/Error while properly ignoring user namespace workloads.
  - Check 14 (CGroup Mode): Verified evaluation logic across versions (target 4.14–4.18 with v1 -> PASS; target >= 4.19 with v1 -> FAIL; target >= 4.19 with v2 -> PASS).
- **Auto-Remediation & Residual Gate**:
  - Verified that auto-fixable HARD failures dynamically trigger `roles/remediate`, transform `health_summary` to `AUTO-FIXED`, and clear the residual HARD gate.
  - Verified that persistent unfixable HARD failures (or `FIX-FAILED`) cleanly trigger the residual HARD gate `fail:`, routing into `rescue:` for alert dispatch and logout.
- **Report Template Integration**:
  - Verified end-to-end Jinja2 template rendering using `playbooks/templates/health-overview.j2` with all 14 prevalidation checks; verified HTML generation (23,205 bytes) displaying all 14 checks, summary metric tiles, and automated remediation callout cards.

### Unit 10 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed all 5 files (`roles/upgrade/defaults/main.yml`, `roles/upgrade/tasks/main.yml`, `tasks/hop.yml`, `04_Live_monitoring_upgrade.yaml`, `03_Initiate_upgrade.yaml`); 0 syntax errors.
- **Header & Standards Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` and `# MIGRATION 2.14:` headers across all 5 files; 100% of tasks (31 tasks total) named; 0 occurrences of deprecated `warn:`; 0 bare `include:` statements; all shell tasks using `pipefail` declare `args: executable: /bin/bash`.
- **Anti-Pattern Compliance**: Zero references to `ansible_failed_task.name` in rescue blocks; error extraction uses hierarchical `stderr` → `stderr_lines` → `msg`; facts pre-computed via `set_fact` before `include_role` to prevent Jinja2 lazy recursion.
- **Loop & Orchestration Verification**:
  - Verified that `03_Initiate_upgrade.yaml` implements per-hop looping using `include_tasks: tasks/hop.yml` over `upgrade_path` with `loop_var: hop_item` and `index_var: hop_index` (no looped `import_playbook`).
  - Verified `vars_files` loading in `03_Initiate_upgrade.yaml` includes all 6 vars files.
- **Task Sequence & Boundary Checks**:
  - Confirmed `tasks/hop.yml` executes all 7 steps in order: (1) hop metadata, (2) start banner & logging, (3) pre-hop settle assertion, (4) `roles/upgrade` execution, (5) monitoring hand-off (`04_Live_monitoring_upgrade.yaml`), (6) settle-gate verification, (7) hop completion notification via `sendmail` with report attachment.
  - Confirmed rescue block invokes `error_handle` and `logout`, and sets `phase_03_failed: true`.
- **Upgrade Driver Logic & Regex Parsing**:
  - Verified Jinja2 `regex_search('^[0-9]+\\.[0-9]+')` correctly extracts major.minor version prefix across version strings (`4.15.35` -> `4.15`, `4.16.18` -> `4.16`, `4.17.0-rc.1` -> `4.17`).
  - Verified channel update logic, update edge re-verification with retries, dynamic admin-ack task inclusion (`roles/remediate/tasks/admin_acks.yml`), force upgrade safety guard (`CONFIRM_FORCE_UPGRADE`), and standard `oc adm upgrade --to` trigger.
- **CLI & Entrypoint Sanity**: Verified `bash -n playbooks/00_Run.sh playbooks/scripts/cli_helpers.sh` passed with zero syntax errors.

### Unit 11 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed all 5 files (`roles/monitor/defaults/main.yml`, `roles/monitor/tasks/main.yml`, `roles/monitor/tasks/poll_iteration.yml`, `04_Live_monitoring_upgrade.yaml`, `tasks/hop.yml`); 0 syntax errors.
- **Header & Standards Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` and `# MIGRATION 2.14:` headers across all 5 files; 100% of tasks (82 tasks total across all blocks and rescues) are explicitly named; 0 occurrences of deprecated `warn:`, 0 bare `include:` statements, all shell tasks using `pipefail` declare `args: executable: /bin/bash`.
- **Anti-Pattern Compliance**: Zero references to `ansible_failed_task.name`; error facts pre-computed via `set_fact` before `include_role` to prevent Jinja2 lazy recursion; boolean condition normalization with `| bool` and `| string | trim`.
- **Loop Bounds & Early Exit Logic**:
  - Verified `monitor_max_iterations` calculation (`(((90 + 2 - 1) // 2) = 45)` iterations).
  - Verified dry-run simulation mode immediately sets `hop_settled: true`, bypassing sleep and terminating cleanly.
  - Verified that setting `hop_settled: true` skips all subsequent polling iterations without delay.
- **Jinja2 Notification Integration (`progress-mail.j2`)**:
  - Test 1: In-progress monitoring email rendered cleanly (14,764 bytes) with `UPGRADE MONITORING ℹ` badge, progress bar at 65%, MachineConfigPool status table, and active updating node (`worker-02`).
  - Test 2: State-change notification with degraded node rendered cleanly (15,476 bytes) surfacing the `DiskPressure` warning callout box.
  - Test 3: Hop-complete notification rendered cleanly (13,533 bytes) with `HOP COMPLETE ✔` badge, 100% progress fill, settle-gate pass callout, and attached report notice.
- **CLI & Entrypoint Sanity**: Verified `bash -n playbooks/00_Run.sh playbooks/scripts/cli_helpers.sh` passed with 0 syntax errors; verified `./00_Run.sh --help` displays banner and structured options cleanly.

### Unit 12 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed all 3 files (`roles/postvalidation/defaults/main.yml`, `roles/postvalidation/tasks/main.yml`, `05_post_Upgrade_Checks.yaml`); 0 syntax errors.
- **Header & Standards Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` headers across all 3 files; 100% of tasks (37 tasks total) explicitly named; 0 occurrences of deprecated `warn:`; 0 bare `include:` statements; all shell tasks declaring `pipefail` specify `args: executable: /bin/bash`.
- **Anti-Pattern Compliance**: Zero references to `ansible_failed_task.name`; error facts pre-computed via `set_fact` before `include_role`; boolean condition normalization with `| string | trim | lower`.
- **10-Check Postvalidation Contract Verification**:
  - Check 01 (CV): Verified version equality, Available=True, Progressing=False, Degraded=False.
  - Check 02 (CO): Verified operator condition evaluation with `co_allow_list` exclusions.
  - Check 03 (MCP): Verified Updated=True, Updating=False, Degraded=False.
  - Check 04 (Nodes & Version): Verified node readiness and dynamic derivation of kubelet prefix (`v1.29.*` for OCP 4.16 from `1.(Y+13)` formula).
  - Check 05 (Pressures): Verified disk, memory, PID pressures and unschedulable threshold check.
  - Check 06 (etcd): Verified control-plane pod quorum and operator condition.
  - Check 07 (PV): Verified storage volume phase checking (Bound/Available).
  - Check 08 (Core Pods): Verified platform pod crashloop and phase check in `openshift-*`.
  - Check 09 (Alerts): Verified Prometheus firing critical alerts query with fallback.
  - Check 10 (Baseline Diff): Verified snapshot slurping, node inventory parity, operator list parity, route availability parity, and version progression tracking.
- **Report Template Integration**: Verified end-to-end Jinja2 template rendering using `playbooks/templates/health-overview.j2` with all 10 postvalidation checks; verified standalone HTML generation (19,731 bytes) with metric tiles and status pills.
- **CLI & Entrypoint Sanity**: Verified `bash -n playbooks/00_Run.sh playbooks/scripts/cli_helpers.sh` passed with 0 syntax errors; verified `./00_Run.sh --help` displays banner and structured options cleanly.

### Unit 13 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed all 12 files (`defaults/main.yml` and tasks for `operator_compat`, `operator_upgrade`, `operator_validate`, `06_Operator_Upgrade.yaml`, and `main.yml`); 0 syntax errors.
- **Header & Standards Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` headers in all 12 files; verified 100% of tasks (71 tasks total across all blocks, loops, and rescues) are explicitly named; 0 occurrences of deprecated `warn:`, 0 bare `include:`, shell tasks with pipefail declare `args: executable: /bin/bash`.
- **Anti-Pattern Compliance**: Confirmed zero references to `ansible_failed_task.name`; error details in `06_Operator_Upgrade.yaml` resolved hierarchically via `stderr` → `stderr_lines` → `msg`; facts pre-computed before `include_role`.
- **Operator Lifecycle Logic**:
  - `operator_compat`: Verified PackageManifest channel resolution for target version prefix (e.g. `4.16`), empty subscription handling, and `operator_compat_plan` export.
  - `operator_upgrade`: Verified unapproved manual InstallPlan detection, sequential JSON merge patch approval, bounded CSV polling loop bounds calculation, and one-shot CSV deletion recovery for failed/stalled CSVs.
  - `operator_validate`: Verified subscription-to-CSV parity matching, `Succeeded` phase assertion, and generation of `output/<cluster>_operators_<ts>.html`.
- **Report Template Integration**: Verified end-to-end Jinja2 template rendering using `playbooks/templates/health-overview.j2` with operator records; verified standalone HTML generation (16,292 bytes) with OLM Operator Compatibility & CSV Lifecycle table and status pills.
- **Digest Email Integration**: Verified `progress-mail.j2` rendered final completion digest email (13,743 bytes) with `ALL PHASES COMPLETE ✔` badge and 4 audit attachment references.
- **CLI & Entrypoint Sanity**: Verified `bash -n playbooks/00_Run.sh playbooks/scripts/cli_helpers.sh` passed with 0 syntax errors; verified `./00_Run.sh --help` displays banner and structured options cleanly.


### Unit 14 Verification Results:
- **YAML Syntax Validation**: Python `yaml.safe_load()` parsed `playbooks/main.yml`; 0 syntax errors, 7 top-level plays/imports verified.
- **Header & Standards Audit**: Verified `# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)` and `# MIGRATION 2.14:` headers; 100% of tasks (6 tasks across 2 plays) explicitly named; 0 deprecated parameters (e.g. `warn:`).
- **Dry-Run Intercept & Teardown Audit**: Verified dedicated intercept play triggers conditionally on `dry_run | default(false) | bool`, logs completion, includes `roles/logout`, and invokes `meta: end_play`. Confirmed all downstream mutation phases (03, 05, 06) declare `when: not (dry_run | default(false) | bool)`.
- **Selective Phase Execution Simulation**: Tested and verified evaluation matrix across 4 scenarios:
  - Scenario A (Full Run): All phases execute (`01 -> 02 -> 03 -> 05 -> 06`), intercept skipped.
  - Scenario B (Dry Run): Phase 01 and 02 execute, intercept halts workflow, phases 03/05/06 skipped.
  - Scenario C (`skip_to_phase: "05"`): Phases 01, 02, 03 skipped; Phase 05 and 06 execute.
  - Scenario D (`skip_to_phase: "06"`): Phases 01, 02, 03, 05 skipped; Phase 06 executes.
- **CLI & Entrypoint Sanity**:
  - `bash -n playbooks/00_Run.sh playbooks/scripts/cli_helpers.sh` passed with 0 syntax errors.
  - `./00_Run.sh --help` rendered formatted ASCII banner and options screen.
  - Full dry-run execution (`--cluster cluster_d01 --no-menu --dry-run --yes`) with `ARO_MOCK_PREFLIGHT=1` successfully acquired concurrency lock, validated extra-vars JSON, dispatched `main.yml`, released lock, and displayed 72-column post-run execution summary (exit code 0).
  - Selective execution test (`--cluster cluster_d01 --skip-to-phase 05 --no-menu --yes`) confirmed extra-vars JSON payload `{"cluster_name": "cluster_d01", "upgrade_path": [...], "dry_run": false, "skip_to_phase": "05"}` and clean completion (exit code 0).


### Unit 15: Exception Handling & Error Extraction Patterns (Cross-Cutting Specification)

#### Purpose & Architectural Standard
Unit 15 establishes the authoritative, production-grade exception handling and failure recovery standard across all roles, tasks, and phase playbooks in the ARO Cluster Upgrade Automation suite. It eliminates runtime crashes caused by unhandled Ansible exceptions, Jinja2 template recursion, and non-serializable internal task objects.

#### Key Patterns & Implementation Details
1. **Hierarchical Error Resolution Cascade**:
   - In any `rescue:` block, root cause error text is extracted using a strict priority cascade:
     - Priority 1: `ansible_failed_result.stderr` (raw command standard error)
     - Priority 2: `ansible_failed_result.stderr_lines | join('\n')` (line-buffered standard error)
     - Priority 3: `ansible_failed_result.msg` (Ansible task execution error message)
     - Priority 4: Explicit fallback string (`'Unknown error — inspect logs'`)
   - Guarantees that actionable error messages (e.g., OpenShift API errors) are never masked by generic non-zero return codes.

2. **OpenShift RBAC & Authorization Error Detection**:
   - Automated keyword scanning across `resolved_error` and `failure_reason` detects permission failures:
     - `forbidden`, `cannot patch`, `unauthorized`, `cannot get`, `cannot list`, `cannot create`.
   - Exposes boolean fact `is_rbac_error` consumed by downstream alert templates (`error-report.j2`) to render high-visibility diagnostic callout boxes with missing verbs/resources and actionable copy-paste remediation commands (`oc adm policy add-cluster-role-to-user cluster-admin ...`).

3. **Zero `ansible_failed_task` Templating Invariant**:
   - Strict avoidance of `ansible_failed_task.name` and all internal `Task` object properties in rescue blocks. Internal `Task` objects contain non-serializable `FieldAttribute` instances that trigger unhandled Ansible exceptions when templated.
   - All task context is supplied through pre-computed facts (`current_task_name`, `current_gate_type`, `current_step_no`).

4. **Anti-Pattern: Eliminating Self-Referencing Variables**:
   - Prohibits passing `vars:` blocks into `include_role` that reference same-named variables in the outer scope (`vars: failure_reason: "{{ failure_reason }}"`).
   - Facts are pre-computed cleanly via `set_fact` before `include_role: name: error_handle` or `include_role: name: logout` is invoked.

5. **Fail-Safe Session Teardown Invariant**:
   - All phase playbooks (`01`–`06`) and sub-playbooks (`tasks/hop.yml`) encapsulate operations within `block/rescue/always`.
   - Every `always:` block explicitly invokes `include_role: name: logout` with `failed_when: false`, guaranteeing that cluster session tokens are revoked and temporary `.kubeconfig-<cluster>` files are purged from disk even in the event of catastrophic playbook halts.

6. **Shell Pipeline Execution**:
   - All `oc` CLI shell tasks utilizing pipes (`|`) or redirects explicitly set `args: executable: /bin/bash` with `set -o pipefail` to ensure proper exit code propagation and prevent dash/sh subshell incompatibilities.

### Unit 15 Verification Results:
- **Verification Checklist Audit**: Automated Python verification script evaluated all 6 cross-cutting specification criteria across 100% of codebase files:
  1. *Rescue extraction cascade*: Verified `stderr` before `stderr_lines` before `msg` across all 6 rescue blocks (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `tasks/hop.yml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`).
  2. *Zero `ansible_failed_task` references*: 0 references across all roles, tasks, and playbooks.
  3. *RBAC detection logic*: Verified keyword coverage (`forbidden`, `cannot patch`, `unauthorized`, `cannot get`, `cannot list`, `cannot create`) in `roles/error_handle/tasks/main.yml` and all rescue blocks.
  4. *Jinja2 self-referencing variable avoidance*: Verified 0 occurrences of self-referencing `vars:` blocks on `include_role`.
  5. *Fail-safe teardown*: Verified all phase playbooks invoke `logout` with `failed_when: false` in `always:` blocks.
  6. *Shell pipe execution*: Verified 100% of shell tasks using pipes specify `args: executable: /bin/bash`.
- **YAML Syntax Validation**: Python `yaml.safe_load()` successfully parsed all 6 modified playbooks/tasks/roles; 0 syntax errors.
- **Jinja2 Template Rendering Tests**: Tested `error-report.j2` rendering under standard failure and RBAC failure conditions; confirmed high-visibility amber callout rendering with missing permissions and remediation command.
- **Shell Sanity**: `bash -n playbooks/00_Run.sh playbooks/scripts/cli_helpers.sh` passed with 0 syntax errors.

---

### Technical Deep-Dive: CLI Interactive Menu & Terminal Box Geometry Engine

#### Problem Investigation & Analysis
During remote execution on Linux jump hosts (e.g. RHEL 8 environment `pwauslapp105`), terminal interactions with `./00_Run.sh` displayed critical formatting and behavioral anomalies:
1. Raw ANSI escape sequences (e.g., `[\033[1m1\033[0m]`, `\033[1;32m* (Default)\033[0m`) rendered verbatim on the screen instead of displaying colored/bold text.
2. The selection menu presented only 2 cluster options (`[1]` and `[2]`), omitting `cluster_p01 (PROD)` despite the prompt specifying `[1-3, default: 1]`.
3. The right vertical border (`│` or `|`) was displaced well beyond column 90 on line 1, and the top header border rendered at 74 columns instead of 72.
4. Under Bash `set -euo pipefail`, making any selection from `render_menu` immediately aborted the script with exit code 1.
5. Menu lines rendered sluggishly with noticeable per-line latency.

#### Root-Cause Findings
1. **ANSI Escape Interpretation**: Color constants (`C_RESET`, `C_BOLD`, etc.) in `playbooks/scripts/cli_helpers.sh` were defined using standard double quotes (`"\033[...m"`). In Bash, double-quoted `"\033"` represents the 4-character literal string `\` `0` `3` `3`, rather than the ASCII ESC control byte (0x1B). Passed through `printf "%s"`, `%s` printed the raw character sequence verbatim without terminal interpretation.
2. **Inner Loop Variable Collision**: The outer loop in `render_menu` (`for ((i=1; i<=num_options; i++))`) and the inner padding loop in `draw_box_row` (`for ((i=0; i<pad_len; i++))`) both used the un-scoped variable `i`. `draw_box_row` overwrote `i` with `pad_len` (21+), causing `render_menu`'s increment to jump to 22+, which immediately violated `i <= num_options` and prematurely terminated the loop before option 3 could be rendered.
3. **Header Embellishment Math Off-by-Two**: `draw_box_header` added 4 to `title_len` for `" [ "` and `" ] "`. However, each sequence contains 3 characters (space, bracket, space), totaling 6 characters. This under-calculation added 2 extra characters to `left_pad + right_pad`, producing a 74-column header.
4. **`set -e` Function Return Invariant**: `render_menu` concluded with `return "$choice"`. Under `set -e`, returning 1 is interpreted as an unhandled error condition, terminating the script immediately.
5. **Slow Subprocess Piping**: `strip_ansi` spawned `sed` in a piped subshell on every length check. Spawning dozens of subprocesses per menu call caused noticeable latency.
6. **Locale Byte vs Character Counting**: On remote environments where `LANG` or `LC_ALL` defaults to `C` or is unset, Bash's `${#string}` counts bytes rather than characters, causing 3-byte UTF-8 glyphs (`─`, `╭`, `★`, `—`) to be counted as 3 columns each.

#### Implementation & Architecture Solutions
1. **ANSI-C Quoting**: Replaced all double-quoted color variables with Bash ANSI-C quoting: `$'\033[...m'`. This evaluates directly to genuine ESC (0x1B) byte sequences recognized by every terminal emulator.
2. **Strict Loop Index Scoping**: Declared `local i` across all library functions (`render_menu`, `draw_box_row`, `draw_box_header`, `draw_box_divider`, `draw_box_footer`, `draw_horizontal_line`).
3. **Instant O(1) Padding**: Replaced string-building loops in `draw_box_row` with Bash's built-in `printf -v padding "%*s" "$pad_len" ""` to eliminate loop overhead and collisions entirely.
4. **Subprocess-Free ANSI Stripping**: Implemented pure-Bash regex pattern matching in `strip_ansi`:
   ```bash
   strip_ansi() {
       local text="$1"
       local esc_pattern=$'\033\\[[0-9;?]*[a-zA-Z]'
       while [[ "$text" =~ $esc_pattern ]]; do
           text="${text//${BASH_REMATCH[0]}/}"
       done
       local lit_pattern='(\\033|\\e)\[[0-9;?]*[a-zA-Z]'
       while [[ "$text" =~ $lit_pattern ]]; do
           text="${text//${BASH_REMATCH[0]}/}"
       done
       printf "%s" "$text"
   }
   ```
5. **Locale Normalization & Dual-Mode Box Geometry**:
   - Automatically normalizes locale to `C.UTF-8` or `en_US.UTF-8` if unset or `C`.
   - Supports clean UTF-8 box characters (`╭`, `╮`, `│`, `─`, `★ (Default)`) by default.
   - Provides clean 72-column ASCII fallback (`+`, `-`, `|`, `* (Default)`) when `ARO_CLI_ASCII=true` or when running in pure ASCII environments.
   - Both modes guarantee mathematically identical 72-column line widths with zero border misalignment.
6. **Clean `return 0` & `MENU_CHOICE` Export**:
   - Replaced `return "$choice"` with clean `return 0` on selection in `render_menu`. Because the function returns 0, it satisfies `set -euo pipefail` without requiring `|| SELECTED_CHOICE=$?`.
   - Exported selected index to `MENU_CHOICE`. Callers in `00_Run.sh` assign directly via `SELECTED_CHOICE="$MENU_CHOICE"`, `PATH_CHOICE="$MENU_CHOICE"`, `MODE_CHOICE="$MENU_CHOICE"`.
   - Completely eliminated complex parameter expansion `${MENU_SELECTED_INDEX:-$SELECTED_CHOICE}`, preventing `bad substitution` errors caused by markdown italicization (`_SELECTED_`) or clipboard space conversions.

#### Verification & Test Results
- **Automated Verification Suite (`scratch/verify_menu_fix.sh`)**:
  - Test 1 (Hex Inspection): Confirmed `C_BOLD` is a genuine 0x1B escape sequence, 0 literal `\033` strings.
  - Test 2 (Width Calculation): Confirmed `visible_length` strips escape codes cleanly and returns accurate visible width (59 cols).
  - Test 3 (Menu Item Completeness): Confirmed all 3 cluster options (`cluster_d01`, `cluster_s01`, `cluster_p01`) rendered in UTF-8 mode with zero raw `\033` sequences.
  - Test 4 (72-Column Geometry Assertion): Line-by-line verification confirmed header (72 cols), option 1 (72 cols), option 2 (72 cols), option 3 (72 cols), and footer (72 cols) all align at column 72.
  - Test 5 (Multi-Option Menu): Confirmed all 4 options in "Select Execution Mode" rendered successfully without loop truncation.
  - Test 6 (ASCII Fallback Mode): Confirmed ASCII mode (`+`, `-`, `|`, `* (Default)`) renders all options and aligns at column 72 on every line.
  - Test 7 (`00_Run.sh --help`): Confirmed CLI entrypoint executes cleanly with new ASCII banner and returns exit code 0.
  - Test 8 (Interactive 3-Menu Pipeline): Confirmed end-to-end simulated interaction across Cluster Selection, Path Selection, and Run Mode Selection with zero `set -e` aborts and zero `bad substitution` errors.

---

### Technical Deep-Dive: Ansible IncludeRole Syntax Attribute Rules

#### Problem Description
When executing `ansible-playbook 01_Policy_Check.yaml` (or running any phase playbook standalone), Ansible halted immediately during playbook parsing with:
```text
ERROR! 'failed_when' is not a valid attribute for a IncludeRole
The error appears to be in '.../01_Policy_Check.yaml': line 195, column 11
The offending line appears to be:
        - name: "Execute session logout on Phase 01 failure"
```

#### Root-Cause Analysis
1. **Dynamic Inclusion Directive Boundaries**:
   In Ansible, `include_role` is a dynamic task inclusion mechanism rather than a code execution module. Unlike task action modules (`command`, `shell`, `file`, `template`), dynamic inclusion directives do not support result evaluation attributes such as `failed_when`, `changed_when`, `until`, or `retries`.
2. **Double-Guarded Logout Redundancy**:
   `failed_when: false` had been appended to `include_role: name: logout` in rescue and always blocks as a defensive measure. However, `roles/logout/tasks/main.yml` already defines `failed_when: false` at the task level on all of its constituent tasks (`oc logout` and temporary kubeconfig file removal). Consequently, placing `failed_when: false` on the outer `include_role` directive was both syntactically invalid and logically redundant.

#### Implementation & Architecture Solutions
- Removed `failed_when: false` from all 11 `include_role: name: logout` occurrences across all phase playbooks (`01_Policy_Check.yaml`, `02_Pre_upgrade_check.yaml`, `03_Initiate_upgrade.yaml`, `05_post_Upgrade_Checks.yaml`, `06_Operator_Upgrade.yaml`) and workflow tasks (`tasks/hop.yml`).
- Fail-safe teardown invariant is strictly preserved because `roles/logout/tasks/main.yml` internally ensures that neither `oc logout` nor file unlinking can ever fail or mask an upstream error.
- Verified across the entire codebase that zero invalid execution attributes (`failed_when`, `changed_when`, `until`, `retries`) exist on `include_role` or `import_role`.

---

### Technical Deep-Dive: Phase 06 Playbook Block Structure & Standalone Safety

#### Problem Description
In `06_Operator_Upgrade.yaml`:
1. The `always:` teardown section was indented at 2 spaces (play-level) instead of 6 spaces (block-level), triggering:
   ```text
   ERROR! 'always' is not a valid attribute for a Play
   ```
2. Unprotected `upgrade_path[-1]` list subscriptions in banner output, email facts, and CSV audit lines caused:
   ```text
   IndexError: list index out of range
   ```
   when running `ansible-playbook 06_Operator_Upgrade.yaml` standalone without passing `--extra-vars '{"upgrade_path":[...]}'`.

#### Root-Cause Analysis
- In Ansible playbook structure, `block`, `rescue`, and `always` form a unified error-handling trio within a task block. Placing `always:` at play-level (column 2) detaches it from the block and makes Ansible parse it as a play attribute, which is illegal.
- `vars/upgrade.yml` defines the default `upgrade_path: []` as an empty list. Direct subscription `upgrade_path[-1]` without a length or existence check fails when the list is empty.

#### Implementation & Architecture Solutions
- **Block Alignment**: Indented `always:` to 6 spaces to nest within `tasks -> block -> rescue -> always`, and indented child tasks to 8 spaces.
- **Conditional List Guarding**: Sourced `upgrade_path[-1]` safely using conditional Jinja expressions:
  ```jinja2
  {{ (upgrade_path[-1] if (upgrade_path is defined and upgrade_path | length > 0) else 'Final Target') }}
  ```
- Guaranteed 100% crash-free standalone execution whether invoked with or without extra-vars.


### 4.4. Prevalidation 14-Check Contract Residual HARD Gate Fix (Checks 06, 12, and 14)

#### Problem Description
During Phase 02 Prevalidation (`playbooks/02_Pre_upgrade_check.yaml`) execution on cluster `arod01`, execution halted at the HARD Gate with 3 residual failures:
```text
fatal: [localhost]: FAILED! => {"changed": false, "msg": "[HARD GATE FAILURE] Phase 02 Prevalidation contract failed for cluster 'arod01'. Residual failed HARD checks (3):
- Check 6: etcd Quorum and Member Health [FAIL] — etcd unhealthy: pods=3 (unready: []), CO etcd Available=True, Degraded=False
- Check 12: PodDisruptionBudgets Health [FAIL] — Zero-disruption PDBs detected (disruptionsAllowed=0, expectedPods>0): [app00046995-q6/elasticsearch-kibana, openshift-logging/logging-loki-distributor, openshift-logging/logging-loki-index-gateway, openshift-logging/logging-loki-ingestor, openshift-logging/logging-loki-querier, openshift-logging/logging-loki-query-frontend]
- Check 14: CGroup Mode Compatibility [FIX FAILED] — cgroupMode patch failed; observed: Execution halted before upgrade initiation with zero cluster mutations."}
```

#### Root-Cause Analysis
1. **Check 06 (etcd Health Type Normalization)**:
   - In `playbooks/roles/etcd/tasks/main.yml`, `etcd_check_valid` evaluated:
     ```yaml
     (etcd_co_available == 'True') and (etcd_co_degraded != 'True')
     ```
   - When `set_fact` parses values from JSON output, Ansible auto-casts `"True"` into Python boolean `True`. In Python, `True == 'True'` evaluates to `False`. This caused completely healthy etcd clusters (3 control-plane pods Running/Ready, CO etcd Available=True, Degraded=False) to falsely fail the check.
2. **Check 12 (PodDisruptionBudgets Strict Gate vs WARN Default)**:
   - In `playbooks/vars/upgrade.yml`, `fail_on_zero_disruption_pdb: true` was set.
   - In `context/feature-spec/09-prevalidation-and-phase02.md`, Check 12 is specified as a non-blocking `WARN` advisory.
   - OpenShift platform logging components (`openshift-logging/logging-loki-*`) intentionally run single-replica or quorum services with `disruptionsAllowed: 0`. Escalating this check to a HARD gate caused an immediate fatal halt.
3. **Check 14 (CGroup Mode Detection, Version Gating & Error Masking)**:
   - In `playbooks/roles/remediate/tasks/cgroup_v2.yml`, `cgroup_needs_patch` tested `detected_cgroup_mode != 'v2'` without checking whether the upgrade target version actually requires cgroup v2 (`>= 4.19`). OpenShift 4.14–4.18 fully supports cgroup v1.
   - When `oc patch nodes.config/cluster` failed (e.g. ARO service account permissions), `failed_when: false` silenced the error, `.spec.cgroupMode` remained unset (returning empty string `""` from jsonpath), and `cgroup_patch_result.stderr` was ignored, rendering `cgroupMode patch failed; observed: ` (completely blank).

#### Implementation & Architecture Solutions
- **Check 06 Normalization**:
  In `roles/etcd/tasks/main.yml`, extracted status with `| string | trim | lower == 'true'` and evaluated validity using native boolean filters `(etcd_co_available | bool)` and `(not (etcd_co_degraded | bool))`.
- **Check 12 Policy Realignment & System Namespace Filtering**:
  In `vars/upgrade.yml` and `roles/pdb/defaults/main.yml`, reset default to `fail_on_zero_disruption_pdb: false` (non-blocking `WARN` advisory per the 14-check contract). Added `pdb_ignore_system_namespaces: true` in `roles/pdb/tasks/main.yml` to filter out `openshift-*` and `kube-*` namespaces if strict mode is ever enabled.
- **Check 14 Target Version Gating, Skip Controls & RBAC Graceful Degradation**:
  - **Version Guarding**: If the upgrade target version is `< 4.19`, cgroupMode v2 is not required; Check 14 evaluates `PASS` and skips auto-remediation cleanly.
  - **Skip Toggle (`skip_cgroup_check`)**: Sourced from `vars/upgrade.yml` (and `--skip-cgroup` flag in `00_Run.sh`), allowing operators or automated CI pipelines to completely bypass Check 14 validation and remediation.
  - **Advisory Gate Policy (`cgroup_enforce_gate`)**: Defaulted `cgroup_enforce_gate: false` in `vars/upgrade.yml` and `roles/prevalidation/defaults/main.yml`, converting Check 14 to a non-blocking `WARN` advisory so cgroupMode v1 status never halts upgrades at the HARD gate.
  - **Cluster-Scope RBAC Authorization Handling**: In `roles/remediate/tasks/cgroup_v2.yml`, detected when `oc patch` fails due to RBAC restrictions (`Forbidden` / `cannot patch`). On managed Azure Red Hat OpenShift (ARO) clusters, customers cannot patch `nodes.config/cluster` at cluster scope. When detected, the engine downgrades status to `WARN` with a clear explanation: service account lacks patch permissions, and managed cluster SRE will handle node rollout during upgrades.

### 4.5. Execution Mode Boundary & Phase Isolation Fix (Pre-check Only / Dry Run / Post-check Only)

#### Problem Description
When operators selected Menu Option 3 ("Pre-check Only (Run Phase 01 & 02 Prevalidation Gate)") from `00_Run.sh`, the orchestrator surprisingly triggered Phase 03 ("Sequential Upgrade Hops") instead of stopping after Phase 02. On clusters where the operational account lacked cluster-scoped update permissions, the run failed at Phase 03 with an RBAC forbidden error:
```text
TASK [Halt execution on Phase 03 playbook failure] *************************************
fatal: [localhost]: FAILED! => {"changed": false, "msg": "Phase 03 Sequential Upgrade Hops failed: Phase 03 Upgrade Hop 1/1 failed for cluster 'arod01': error: Unable to upgrade: clusterversions.config.openshift.io \"version\" is forbidden: User \"a46878073\" cannot patch resource \"clusterversions\" in API group \"config.openshift.io\" at the cluster scope"}
```

#### Root-Cause Analysis
1. **Misconfigured Extra-Vars in `00_Run.sh`**:
   - In `00_Run.sh`, selecting Option 3 executed:
     ```bash
     case "$MODE_CHOICE" in
         3)
             DRY_RUN=false
             SKIP_TO_PHASE="02"
             ;;
     ```
   - This passed `-e '{"dry_run": false, "skip_to_phase": "02", ...}'` to Ansible.
2. **Start-From Semantics in `playbooks/main.yml`**:
   - `skip_to_phase` was implemented across all playbooks as a *lower bound* / *start-from* filter (`(skip_to_phase | int) <= N`).
   - Consequently:
     - Phase 01: `(2 <= 1)` evaluated to `false` $\rightarrow$ Phase 01 was skipped.
     - Phase 02: `(2 <= 2)` evaluated to `true` $\rightarrow$ Phase 02 ran.
     - Dry-Run Intercept: `when: dry_run | default(false) | bool` $\rightarrow$ evaluated to `false` because `DRY_RUN=false`, so execution did not halt.
     - Phase 03: `when: not (dry_run) and (skip_to_phase <= 3)` $\rightarrow$ evaluated to `true` and `true` $\rightarrow$ **Phase 03 executed, initiating cluster upgrade!**
3. **Absence of Upper Phase Bounds (`stop_after_phase`)**:
   - A similar issue affected Option 4 ("Post-check Only"): setting `SKIP_TO_PHASE="05"` skipped Phases 01–03, ran Phase 05, and then cascaded into Phase 06 Operator Upgrades because `5 <= 6` is `true`.

#### Implementation & Architecture Solutions
- **Introduction of `stop_after_phase`**:
  Added an upper execution bound to complement `skip_to_phase`. Each phase in `main.yml` is now guarded by both a start-from condition (`skip_to_phase <= N`) and a stop-after condition (`stop_after_phase >= N`).
- **Dedicated Phase Intercept Plays**:
  - **Prevalidation Intercept (Post-Phase 02)**: Executes when `dry_run: true` OR `(stop_after_phase <= 2)`. Revokes the active OpenShift session token via `roles/logout` and cleanly halts execution via `meta: end_play`. This guarantees that Phases 03, 04, 05, and 06 can never execute during pre-checks or dry runs.
  - **Post-Check Intercept (Post-Phase 05)**: Executes when `stop_after_phase <= 5`. Revokes cluster session token via `roles/logout` and halts execution via `meta: end_play`, preventing Mode 4 from cascading into Phase 06.
- **Deterministic Run Mode Mapping in `00_Run.sh`**:
  - **Mode 1 (Full Upgrade)**: `dry_run: false`, `skip_to_phase: ""`, `stop_after_phase: ""` (Executes Phases 01 $\rightarrow$ 06).
  - **Mode 2 (Dry Run)**: `dry_run: true`, `stop_after_phase: "02"`, `auto_remediation_enabled: false` (Zero mutations; validates edges and pre-upgrade health).
  - **Mode 3 (Pre-check Only)**: `dry_run: true`, `stop_after_phase: "02"`, `auto_remediation_enabled: true` (Runs Phase 01 & 02 with auto-remediation, generates report, and halts cleanly before Phase 03).
  - **Mode 4 (Post-check Only)**: `dry_run: false`, `skip_to_phase: "05"`, `stop_after_phase: "05"` (Runs Phase 05 postvalidation, halts cleanly before Phase 06).
- **CLI Flags & Production Guard Refinement**:
  - Added CLI flags: `--pre-check` (or `--pre-check-only`), `--post-check` (or `--post-check-only`), and `--stop-after-phase <NN>`.
  - Refined PROD confirmation: only prompts the operator to type `UPGRADE` on mutating upgrade runs (`dry_run: false` and `stop_after_phase != "02"`). For non-mutating validation/pre-checks on PROD, provides a standard confirmation prompt.

### 4.6. Prevalidation HTML Report Email Notification System

#### Problem Description
When executing pre-upgrade validation (Option 3 / `--pre-check` / `--dry-run`), the orchestrator successfully evaluated all 14 checks and wrote the standalone HTML report to `output/<cluster>_prevalidation_<timestamp>.html` and run logs to `logs/<cluster>_<timestamp>.txt`. However, unlike hop completions and final upgrade closeout, Phase 02 lacked automated email dispatch for successful prevalidation runs. Operators had to manually pull reports from remote disk rather than receiving immediate email delivery.

#### Implementation & Architecture Solutions
- **Automated Dispatch in Phase 02 (`02_Pre_upgrade_check.yaml`)**:
  - Embedded an automated notification dispatch step directly into `playbooks/02_Pre_upgrade_check.yaml` immediately following report generation.
  - Formats the email body with the complete, interactive HTML prevalidation report using `health-overview.j2` and attaches the generated `.html` file from disk (`report_file_path`).
  - Pre-configures subject lines following enterprise standards: `{{ prevalidation_subject_prefix }} — {{ overall_verdict }} — {{ cluster_name }}` (e.g. `[ARO Upgrade PREVALIDATION] — PASS — arod01`).
- **Configurable Routing & SMTP Defaults (`vars/smtp.yml`)**:
  - Added `preval_mail_to` (distribution list for prevalidation health reports, defaulting to `mail_to`).
  - Added `prevalidation_subject_prefix: "[ARO Upgrade PREVALIDATION]"`.
  - Added master toggle `send_prevalidation_email: true` to enable/disable prevalidation email dispatch globally.
- **CLI Recipient Override (`--mail-to`)**:
  - Added `-m, --mail-to <email>` to `playbooks/00_Run.sh` (supports single addresses or comma-separated lists), allowing operators to dynamically route reports to ad-hoc or personal addresses during testing without modifying YAML configurations.
- **Non-Fatal Delivery Fault-Tolerance**:
  - Wrapped email dispatch in an Ansible `block/rescue` structure. If the upstream SMTP relay fails, times out, or is unreachable, the engine emits a clear `[WARN]` diagnostic to the console and run log while preserving the exit code 0 verdict and generated artifacts on disk.

### 4.7. Postvalidation HARD Gate Resolution & Diagnostic Observability (Checks 01 & 02)

#### Problem Description
When running Phase 05 postvalidation (Option 4 / `--post-check`) against cluster `arod01`, execution unexpectedly halted at the HARD gate with:
```text
fatal: [localhost]: FAILED! -> {"changed": false, "msg": "HARD GATE FAILURE [postvalidation]: One or more postvalidation HARD checks failed on cluster 'arod01'. Failed checks: Final ClusterVersion, ClusterOperators Status."}
```
Following this failure:
1. The postvalidation HTML report was marked `(Not Generated)` because the gate failed before report generation.
2. The CLI entrypoint `00_Run.sh` printed a misleading post-run verdict attributing the failure to Phase 03/04 (`Execution halted: Cluster upgrade initiation or rollout failed (Phase 03/04) [Exit Code: 20]`).
3. The operator had no diagnostic visibility into which operators were failing or why `Final ClusterVersion` failed.

#### Deep Root-Cause Analysis
1. **Inverted JQ Condition Fallbacks**:
   - In Check 01 (`roles/postvalidation/tasks/main.yml`), the JQ fallback for `progressing` defaulted to `// "True"`. If the condition was missing or null, it falsely flagged the cluster as progressing.
   - In Check 02, the JQ fallback for `degraded` defaulted to `// "True"`. Any operator lacking an explicit `Degraded` condition was falsely categorized as degraded.
2. **Target Version Resolution in Standalone Post-Check Mode**:
   - `postval_resolved_target_version` resolved to `upgrade_path[-1]`. In Mode 4 (`--post-check`), `00_Run.sh` defaulted `upgrade_path` to the entire configured 3-hop journey (`["4.14.40", "4.15.35", "4.16.18"]`), causing postvalidation to check whether the cluster was at `4.16.18`. Since `arod01` was at its current version (4.14.x), Check 01 failed.
3. **OpenShift ClusterVersion & ClusterOperators Interdependence**:
   - In OpenShift 4, `ClusterVersion` conditions directly aggregate `ClusterOperators` health. If any operator is flagged degraded or progressing, `ClusterVersion` automatically reflects `Degraded=True` or `Progressing=True`. This caused Check 01 and Check 02 to fail simultaneously.
4. **Diagnostic Truncation in Failure Message**:
   - `Enforce HARD postvalidation gate` printed only check names (`Failed checks: Final ClusterVersion, ClusterOperators Status`), hiding the detailed `observed` string containing the current vs expected version and the offending operator names.
5. **Premature Gate Enforcement Bypassing HTML Reports**:
   - Because `fail:` was executed inside `roles/postvalidation`, Ansible jumped directly to the rescue block of `05_post_Upgrade_Checks.yaml`, skipping the `report` role invocation.
6. **Exit Code Mapping Collisions in `00_Run.sh`**:
   - The regex `(initiate_upgrade.*failed|hop.*failed|upgrade.*failure)` matched the string `"Phase 05 Post-Upgrade Checks & Baseline Diff failed"`, misreporting Phase 05 postvalidation failures as Phase 03/04 upgrade failures with Exit Code 20.

#### Implementation & Architecture Solutions
- **Corrected JQ Condition Fallbacks**:
  - Check 01 JQ extraction now safely defaults `progressing` to `"False"`.
  - Check 02 JQ extraction now safely defaults `degraded` to `"False"` and `progressing` to `"False"`, aligning with `tasks/hop.yml` and `poll_iteration.yml`.
- **Dynamic Effective Target Version Resolution**:
  - Added `postval_effective_target_version`. If `postval_resolved_target_version` is `'current'`, `'auto'`, or empty, postvalidation dynamically resolves to the cluster's current settled version (`postval_cv_data.current_version`), enabling standalone health verification on live clusters without requiring an upgrade path.
  - Added `| string | trim` normalization across all version comparisons to prevent whitespace mismatches.
- **Operator Settle Re-check Window**:
  - Implemented an automated settle loop in Check 02: if operators report temporary instability or progressing conditions, postvalidation executes up to 3 retries with a 10-second delay to allow routine controller reconciliation and telemetry sync to settle cleanly.
- **Detailed Diagnostic Gate Failure Message**:
  - Refactored `Enforce HARD postvalidation gate` to display each failed check's number, name, gate, and `observed` explanation, ensuring complete terminal and log visibility.
- **Fail-Safe Postvalidation HTML Report Generation**:
  - Added an automated report generation block within the `rescue:` block of `playbooks/05_post_Upgrade_Checks.yaml`. If postvalidation checks ran before a failure, the HTML report is always generated and saved to disk.
- **Dedicated Exit Code 25 in CLI Entrypoint (`00_Run.sh`)**:
  - Added `Exit Code 25: Postvalidation Gate Failed (Phase 05)` and updated log inspection regexes to evaluate Phase 05 failures before Phase 03/04 rules.
  - Enhanced the interactive path selection menu in Mode 4 to offer `Current Live Cluster Version` as the default validation target.
- **Global `co_allow_list` Configuration (`vars/upgrade.yml`)**:
  - Exposed `co_allow_list: []` in `vars/upgrade.yml` with clear operator documentation for excluding non-critical or environment-specific components.

### 4.8. Automated Post-Upgrade Validation & Upgrade Success Email Notification System

#### Problem Description
While Phase 02 (Prevalidation), Phase 03 (Hop Completions), and Phase 06 (Operator Upgrades Closeout) had automated email notifications, Phase 05 (Post-Upgrade Checks & Baseline Diff) lacked an automated email dispatch step upon successful completion. Operators executing standalone post-validation sweeps (Option 4 / `--post-check`), running with `--stop-after-phase 05`, or verifying post-upgrade cluster parity did not receive automated email delivery of the postvalidation audit report. Furthermore, in Phase 06, the completion subject line did not use `completion_subject_prefix` and lacked non-fatal SMTP fault tolerance.

#### Implementation & Architecture Solutions
- **Automated Dispatch in Phase 05 (`05_post_Upgrade_Checks.yaml`)**:
  - Embedded an automated notification dispatch step directly into `playbooks/05_post_Upgrade_Checks.yaml` immediately following successful postvalidation gate evaluation and report generation.
  - Formats the email body with the interactive HTML postvalidation report using `health-overview.j2` (displaying all 10 checks, status pills, and baseline diff parity) and attaches the generated `output/<cluster>_postvalidation_<timestamp>.html` file from disk.
  - Pre-configures subject lines adhering to enterprise standards: `{{ postvalidation_subject_prefix | default('[ARO Upgrade POSTVALIDATION]') }} — SUCCESS ✔ — {{ cluster_name }} ({{ postval_cv_data.current_version }})`.
- **Configurable Routing & SMTP Defaults (`vars/smtp.yml`)**:
  - Added `postval_mail_to` (distribution list for post-upgrade validation & success reports, defaulting to `mail_to`).
  - Added `postvalidation_subject_prefix: "[ARO Upgrade POSTVALIDATION]"`.
  - Added master toggles `send_postvalidation_email: true` and `send_upgrade_success_email: true`.
- **CLI Recipient Override Integration (`00_Run.sh`)**:
  - Updated `playbooks/00_Run.sh` extra-vars generation so `-m, --mail-to <email>` overrides dynamically populate `mail_to`, `preval_mail_to`, and `postval_mail_to`.
- **Standardized Phase 06 Completion & Resilient Delivery (`06_Operator_Upgrade.yaml`)**:
  - Updated Phase 06 digest email subject line to use `completion_subject_prefix: "[ARO Upgrade COMPLETE]"` (`[ARO Upgrade COMPLETE] — ALL PHASES COMPLETE ✔ — <cluster>`).
  - Wrapped Phase 06 completion email dispatch in a non-fatal `block/rescue` structure to guarantee that transient SMTP relay issues never cause playbook failure after all upgrades have passed.

### 4.9. Phase 06 Operator Upgrade InstallPlan Query & JSON Parsing Resolution

#### Problem Description
When executing Phase 06 (`--skip-to-phase 06` or during final operator upgrades), the playbook failed at the fact initialization task with a fatal JSON decode error:
```text
TASK [operator_upgrade : operator_upgrade: Set unapproved InstallPlans fact] ***
fatal: [localhost]: FAILED! => {"msg": "the field 'args' has an invalid value ({'unapproved_installplans': '{{ ip_parsed_raw.stdout | from_json }}'}), and could not be converted to an dict. The error was: Extra data: line 2 column 1 (char 3)"}
```

#### Root-Cause Analysis
1. **Two-Step Query & Shell Interpolation Anti-Pattern**:
   - `roles/operator_upgrade`, `roles/operator_compat`, and `roles/operator_validate` were executing a two-step pattern:
     - Task 1: `oc get installplan -A -o json 2>/dev/null || echo '{"items":[]}'`
     - Task 2: `echo '{{ ip_query_raw.stdout | default("{}") }}' | jq -c '...'`
     - Task 3: `set_fact: unapproved_installplans: "{{ ip_parsed_raw.stdout | from_json }}"`
   - If `oc get installplan` returned output alongside fallback echoes, or if the pipe produced multiple JSON objects, `jq -c` printed multiple arrays across sequential lines (`[]\n[]`).
   - Python's `json.loads` (invoked by Jinja2's `from_json` filter) strictly expects a single JSON document. When reading line 2 column 1, it encountered the second `[` and raised `JSONDecodeError: Extra data: line 2 column 1 (char 3)`.
2. **Bash String Quote Collision**:
   - Expanding raw multi-kilobyte JSON strings with `echo '{{ ... }}'` in bash caused bash syntax errors whenever operator CSV descriptions, annotations, or error messages contained single quotes `'` (e.g. `'installplan-xyz' is not ready` or `can't find package`).
3. **Missing KUBECONFIG Environment Context**:
   - None of the tasks in `operator_upgrade`, `operator_compat`, or `operator_validate` declared `environment: KUBECONFIG: "{{ cluster_kubeconfig }}"`. When invoked standalone via `--skip-to-phase 06`, `oc` fell back to default paths rather than the active session established by `roles/login`.

#### Implementation & Architecture Solutions
- **Single-Step Streamlined Piped Execution**:
  - Replaced the brittle two-step tasks across `operator_upgrade`, `operator_compat`, and `operator_validate` with single atomic shell tasks that stream JSON directly from `oc` to `jq` via Linux pipe:
    ```bash
    oc get installplan -A -o json 2>/dev/null | jq -c '
      [ .items[]? | select(.spec.approved == false) | { ... } ]
    ' || echo '[]'
    ```
  - This eliminates intermediate Jinja2 string expansions, prevents bash single-quote collisions, and guarantees that `jq` operates purely in memory.
- **Explicit KUBECONFIG Context**:
  - Attached `environment: KUBECONFIG: "{{ cluster_kubeconfig | default(playbook_dir ~ '/.kubeconfig-' ~ (cluster_name | default('default'))) }}"` to all `oc` tasks across `operator_upgrade`, `operator_compat`, and `operator_validate`.
- **Resilient JSON Fact Parsing**:
  - Updated all fact assignments to safely extract and parse the primary line:
    ```jinja2
    {{ ((ip_parsed_raw.stdout | default('[]') | trim).split('\n') | first | from_json)
       if (ip_parsed_raw.stdout | default('') | trim | length > 0)
       else [] }}
    ```
  - Prevents any `Extra data: line 2 column 1` errors even in edge cases with trailing whitespace or warnings.

### 4.10. Phase 06 Operator Mutation Bypass & Validation-Only Control

#### Problem Description
During Phase 06 execution (`playbooks/06_Operator_Upgrade.yaml`), the playbook scans the cluster for pending manual OLM InstallPlans (`spec.approved == false`) and attempts to approve them sequentially via `oc patch installplan <name> -n <namespace> --type=merge -p '{"spec":{"approved":true}}'`.
If the cluster service account or operator user lacks RBAC permissions in specific namespaces (for example, in tenant or restricted namespaces such as `openshift-lightspeed` with `403 Forbidden: User cannot patch resource "installplans"`), the unhandled failure in Step 2 halted Phase 06. Consequently, operators were unable to complete read-only operator compatibility audits, generate the final Operator Health HTML report, or dispatch the final Upgrade-Complete completion email digest.

#### Architectural Solution
The operator lifecycle in Phase 06 was decoupled into a selective execution pipeline guarded by the `skip_operator_upgrade` control flag:
1. **`roles/operator_compat` (Step 1)**: Purely read-only; inspects subscriptions, queries PackageManifests, and determines channel compatibility against the target OpenShift version. Always executes.
2. **`roles/operator_upgrade` (Step 2)**: Mutating; discovers unapproved InstallPlans and executes `oc patch`. Now conditionally guarded with `when: not (skip_operator_upgrade | default(false) | bool)`. When `skip_operator_upgrade: true`, an explicit notification is emitted and this step is completely bypassed.
3. **`roles/operator_validate` (Step 3)**: Purely read-only; inspects live subscriptions and CSVs across all namespaces, validates CSV status against subscriptions, generates `output/<cluster>_operators_<ts>.html` via `roles/report`, and passes report paths to the final completion digest.
4. **Final Completion Digest & Teardown (Steps 4 & 5)**: Resolves all 4 audit attachments (Prevalidation, Postvalidation, Operator report, and Run log), dispatches the completion email via `roles/sendmail`, and executes terminal cluster session logout via `roles/logout`.

#### Configuration & CLI Usage
- **Playbook / Inventory Variable**: `skip_operator_upgrade: false` (default) in `playbooks/vars/upgrade.yml` and `playbooks/roles/operator_upgrade/defaults/main.yml`.
- **CLI Flag**: Added `--skip-operator-upgrade` to `playbooks/00_Run.sh`:
  ```bash
  # Standalone Phase 06 validation-only run
  ./00_Run.sh --cluster arod01 --skip-to-phase 06 --skip-operator-upgrade --yes

  # Full workflow without mutating OLM operators
  ./00_Run.sh --cluster arod01 --path "4.15.35,4.16.18" --skip-operator-upgrade --yes
  ```
- **Direct Playbook Invocation**:
  ```bash
  ansible-playbook playbooks/06_Operator_Upgrade.yaml -e "cluster_name=arod01 skip_operator_upgrade=true"
  ```
- **Exit Code Attribution**: Added `Exit Code 35: Operator Upgrade / Validation Failed (Phase 06)` in `00_Run.sh` to prevent Phase 06 errors from being misidentified as Phase 05 postvalidation failures.

### 4.11. Phase 06 Consolidated Operator Failure Notification & Attached HTML Report

#### Problem Description
When Phase 06 encountered an operator failure (e.g. an unapproved InstallPlan failing with HTTP 403 Forbidden due to RBAC restrictions, or an operator CSV failing to reach `Succeeded` within the polling timeout), the playbook halted and invoked `roles/error_handle`. However:
1. If the failure occurred during `roles/operator_upgrade`, `roles/operator_validate` had not yet executed, leaving the standalone client-facing operator HTML report (`output/<cluster>_operators_<ts>.html`) ungenerated on disk.
2. `roles/error_handle` did not configure or pass email attachments (`mail_attachments`), so failure alert emails lacked diagnostic attachments.
3. Alert email recipient routing defaulted exclusively to `alert_mail_to`, bypassing the user or operator who launched the playbook via `--mail-to`.
4. The failure alert template (`error-report.j2`) did not render attachment visibility callouts.

#### Architectural Solution
The Phase 06 rescue workflow was enhanced to provide guaranteed diagnostic artifact generation and consolidated notification delivery:
1. **Fail-Safe Operator HTML Report Generation**:
   - Within `06_Operator_Upgrade.yaml`'s `rescue:` block, the playbook verifies whether `output/<cluster>_operators_<run_timestamp>.html` exists.
   - If missing, it invokes `roles/operator_validate` with `operator_validate_enforce_gate: false` inside a non-fatal block. This scans live subscriptions and CSVs across all namespaces, evaluates health, and renders `output/<cluster>_operators_<ts>.html` via `roles/report`.
2. **Consolidated Audit Attachment Resolution**:
   - Collects all four primary diagnostic files (`operators_<ts>.html`, `postvalidation_<ts>.html`, `prevalidation_<ts>.html`, and `<cluster>_<ts>.txt`) into `p06_rescue_final_attachments` and exports `mail_attachments`.
3. **User & Platform Alert Recipient Merging**:
   - Sets `resolved_alert_recipients` combining `mail_to` (the user's email address) and `alert_mail_to` (the platform alert distribution list).
4. **Enhanced Error Report Template (`error-report.j2`)**:
   - Added an "Attached Diagnostic Reports" callout section rendering clean bulleted links to all attached artifacts alongside the failure reason, observed return code, and RBAC remediation guidance.
5. **SMTP Relay Fault Tolerance**:
   - Encapsulated `sendmail` invocation within `roles/error_handle` in `block/rescue` to ensure transient SMTP timeouts or connection refusals never disrupt terminal cluster session teardown and token revocation in `logout`.

### 4.12. Unit 16: Developer Comments & Documentation Standards (Cross-Cutting Specification)

#### Goal & Philosophy
To ensure long-term maintainability, auditability, and team onboarding without tribal knowledge, the codebase enforces a strict **Zero-Ambiguity Engineering Standard** across all 71 YAML files, 3 Jinja2 presentation templates, and supporting Bash scripts:
- **Zero-Ambiguity Architecture**: Any platform engineer reading any playbook, role task, or template immediately understands its purpose, dual-version behavior, dependencies, gate severity, and failure implications without consulting external documentation.
- **Explain the "Why", Not the "What"**: Comments articulate *why* a particular pattern or workaround was selected (e.g. jq 1.5 lexer collision avoidance, Debian dash shell avoidance, Python dictionary `.items()` collisions, OpenShift condition boolean-string deserialization normalization) rather than restating the task name.
- **Continuous Documentation Parity**: Code and documentation are updated simultaneously to prevent architectural drift.

#### 1. Standardized File Header Blocks
Every playbook (`.yaml`/`.yml`), role task file, sub-playbook, and variable definition file begins with the mandatory 6-field header block:
```yaml
# ============================================================================
# <Single-Line Component Description>
# ============================================================================
# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)
# MIGRATION 2.14: <Specific migration notes or "No syntax changes needed">
#
# Purpose: <Detailed multi-line explanation of what this component executes>
# Role / Playbook Dependencies: <List of roles/vars required by this file>
# Gate Type: <HARD / WARN / AUTO-REMEDIATION / N/A>
# Outputs: <Facts exposed, files written, or notifications dispatched>
# ============================================================================
```

#### 2. Role Defaults Documentation Contract (`defaults/main.yml`)
Every variable in all 24 `defaults/main.yml` files is documented with its operational purpose, data type, and override source:
```yaml
# <Clear Description> (<data type>, <mandatory/optional/default>)
# Sourced from <vars file / CLI flag / runtime derivation>
<variable_name>: <default_value>
```

#### 3. Task-Level Inline `# Why:` Logic Annotations
All tasks implementing workarounds for tooling limitations or platform behaviors are preceded by explicit `# Why:` comments:
- **Shell Pipefail**: Shell tasks executing piped commands declare `# Why: set -o pipefail requires /bin/bash; Ansible default /bin/sh defaults to dash on Debian` alongside `args: executable: /bin/bash`.
- **jq 1.5 Rounding (`rnd2`)**: Mathematical expressions declare `# Why: jq 1.5 does not support round(); custom rnd2 function avoids lexer token collision`.
- **Kubernetes Bracket Querying (`['items']`)**: Jinja2/JSON queries declare `# Why: Bracket notation ['items'] avoids collisions with Python dict.items()`.
- **Boolean Normalization**: Condition evaluations declare `# Why: | string | trim | lower == 'true' applied because OpenShift conditions may deserialize as boolean True or strings`.

#### 4. Rescue Block 3-Point Documentation Standard
Every `rescue:` section across playbooks explicitly documents:
1. **Error Extraction Cascade**: `ansible_failed_result.stderr` -> `stderr_lines` -> `msg` -> fallback string without referencing internal non-serializable task objects.
2. **Alerts Dispatched**: `error_handle` invocation, failure alert email (`error-report.j2`), and dual execution logs (`.txt` and `.csv`).
3. **Session Teardown Guarantee**: Token revocation and kubeconfig removal guaranteed by caller `always:` block or inline `logout` role invocation.

#### 5. Jinja2 Presentation Template Documentation
Every template in `playbooks/templates/*.j2` includes a top-level documentation block declaring:
- **Context**: Target rendering environment (Email alert card, Standalone HTML report, Upgrade progress email).
- **Dependencies**: Inbound facts consumed (e.g. `health_summary`, `mcp_summary_table`, `autofix_items`, UI tokens).
- **Constraints**: Viewport constraints (e.g. `≤ 580px` for email clients, `≤ 1080px` for standalone HTML), zero external CDN dependencies, and WCAG AA contrast compliance.

#### 6. Automated Verification
Validated via automated test suite `scratch/verify_unit16.py`:
- 100% header compliance across all 71 YAML files.
- 100% action-oriented `name:` attributes across all tasks.
- 100% `# Why:` comments on all 53 pipefail and jq workarounds.
- 100% variable type and source annotations across all 24 role defaults.
- 100% clean PyYAML syntax validation and Jinja2 rendering tests.

---

## 5. Next Steps

- **Antigravity Word/PowerPoint Documentation Generation Prompt** (`Documentation_Prompt.md`)


