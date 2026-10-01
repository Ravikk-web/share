# Architecture Context — ARO Cluster Upgrade Automation

This document defines the system structure, boundaries, storage model, and invariants. Read `project-overview.md` first for the product definition, then this file before making any architectural decision.

---

## Stack

| Layer | Technology | Role |
|---|---|---|
| Orchestration engine | Ansible (**2.7.17 test / 2.14.18 prod**, single codebase) | Runs `main.yml`, chains the phase playbooks, drives the per-hop loop and operator upgrades. Written to 2.7.17 syntax with inline `# MIGRATION 2.14:` notes. |
| CLI entrypoint | Bash (`00_Run.sh` + `scripts/cli_helpers.sh`) | One-touch interface: pre-flight checks, Vault-tolerant config validation, static path validation, menus, change-scope display, PROD confirmation (`UPGRADE`, never bypassed by `--yes`), per-cluster run lock, tee'd logging, exit code from the run status file. |
| Cluster interface | `oc` CLI | All reads, remediations and upgrade triggers. Queries use retries or bounded in-shell wait loops; `--request-timeout` on monitor queries. |
| Update graph | OpenShift Update Service (`upgrade_graph_url`, via `curl`) | Phase 01 validates every edge of the path against the graph of the channel each hop uses. TLS verification follows `insecure_skip_tls_verify` (skipped by design). |
| Data parsing | `jq` (**v1.5**) | Parses `oc ... -o json`. jq 1.5 syntax only: every `if` has an `else`; no `IN`, `walk`, `$ENV`, `ascii`, `halt`, `?//`. |
| Scripting glue | Bash via `shell` | Every shell task using `set -o pipefail` declares `executable: /bin/bash`. |
| Notifications | Ansible `mail` module (community.general on 2.14), through `tasks/notify.yml` → `roles/sendmail` | Heartbeat every 20 min, degradation alerts, one failure alert, prevalidation mail (full runs), one closing summary per run. SMTP failures never fail the run. |
| Reporting | Jinja2 templates (`.j2`) | HTML reports (Phase 01, 02, 05, 06) and mails. Statuses: PASS, WARN, FAIL, AUTO-FIXED, FIX-FAILED, SKIPPED. |
| Secrets source | Ansible vars file now → **Conjur Vault** later | Variable references only (`{{ vault_* }}`), `no_log: true`; the login password is passed on stdin, never on a command line. |
| Host platform | RHEL 8 jump server | Runs the playbooks with `oc`, `jq`, `curl`, `flock`, Python. |

---

## Process Surface (Seven Process Files)

| File | Phase / Step | Responsibility | Chain Type |
|---|---|---|---|
| `00_Run.sh` | Entrypoint | Pre-flight, config and path validation, menus, change scope, PROD confirmation, run lock, execution, exit code from `logs/<cluster>_<ts>.status` | Bash + `scripts/cli_helpers.sh` |
| `main.yml` | Master orchestrator | Imports Phases 01, 02, 03, 05, 06 (each guards itself with `skip_to_phase` / `stop_after_phase` / dry-run rules), then a close-out play that sends the run's single summary mail and logs out | `import_playbook` |
| `01_Policy_Check.yaml` | Phase 01 | Login + identity check, baseline snapshot, whole-path validation (`tasks/validate_upgrade_path.yml`), Phase 01 report | `import_playbook` |
| `02_Pre_upgrade_check.yaml` | Phase 02 | 15-check scan, auto-remediation, rollout wait (`roles/monitor` rollout mode), full re-scan, AUTO-FIXED / FIX-FAILED merge, report, HARD gate, prevalidation mail | `import_playbook` |
| `03_Initiate_upgrade.yaml` | Phase 03 | Hop loop over `upgrade_path` through `tasks/hop.yml`; dry run prints the plan only | `include_tasks` + `loop` |
| `04_Live_monitoring_upgrade.yaml` | Phase 04 | Per-hop hand-off to `roles/monitor` (hop mode); not runnable on its own | `include_tasks` (from `hop.yml`) |
| `05_post_Upgrade_Checks.yaml` | Phase 05 | 10-check postvalidation, baseline diff, report, HARD gate (enforced on live runs) | `import_playbook` |
| `06_Operator_Upgrade.yaml` | Phase 06 | Operator compatibility (report), approval of each pending subscription's current InstallPlan, operator validation, Developer perspective, operators report | `import_playbook` |

Exit codes (written by `roles/error_handle` to the status file): 5 Phase 01, 10 Phase 02, 20 hop failed, 25 Phase 05, 30 hop timeout / no progress, 35 Phase 06, 99 other.

---

## System Boundaries

- `playbooks/` — `00_Run.sh`, `main.yml`, the phase playbooks.
- `playbooks/scripts/` — `cli_helpers.sh` (terminal UI, menus, change scope, run lock, artifact purge).
- `playbooks/tasks/` — shared task files:
  - `hop.yml` — one hop: plan (skip / resume / trigger) → stable-cluster wait → start (channel, offered edge, conditional-risk policy, removed-API check + admin-ack, trigger, confirm) → monitor → result; one alert on failure.
  - `validate_upgrade_path.yml` — whole-path validation (live ClusterVersion + update graph); used by Phase 01, and by Phase 03 when Phase 01 did not run.
  - `log_event.yml` — the only writer of the run logs (append-only `.txt` line + `.csv` row).
  - `notify.yml` — the only composer of mails (recipients, subject, template, attachments) → `roles/sendmail`.
  - `send_run_summary.yml` — the single closing summary of a successful run (also used for the prevalidation mail and standalone phase mails).
- `playbooks/roles/` — 26 single-purpose roles:
  - **Session & baseline**: `login`, `logout`, `snapshot`
  - **Health checks**: `api_check`, `api_readiness`, `co`, `mcp`, `node`, `etcd`
  - **Capacity & disruption**: `utilization`, `pv`, `pvc`, `pdb`
  - **Aggregators & gates**: `prevalidation`, `postvalidation`
  - **Upgrade engine**: `upgrade` (`main.yml` plan, `apply.yml` start), `monitor` (hop / rollout mode)
  - **Auto-remediation**: `remediate` (cgroup v2, MCP unpause, operator pod restart; `admin_acks.yml` evaluate / apply engine), `api_usage` (removed-API callers from APIRequestCount)
  - **Operators & console (Phase 06)**: `operator_compat`, `operator_upgrade`, `operator_validate`, `console`
  - **Reporting & notifications**: `report`, `sendmail`, `error_handle`
- `playbooks/vars/` — input only: `upgrade.yml` (path, graph validation, thresholds, cadences, toggles), `secrets.yml` (per-cluster API URL, credentials as vault references, optional `cluster_id` pin), `smtp.yml` (server, recipient lists per mail type, toggles), `paths.yml`, `report_vars.yml`, `api_regex.yml`.
- `playbooks/templates/` — presentation only:
  - `phase01-policy-check.j2` — Phase 01 report (one row per step and per path edge).
  - `phase02-prevalidation.j2` — Phase 02 report (15-check table, one data-driven card per check, auto-fix list).
  - `health-overview.j2` — Phase 05 and Phase 06 reports.
  - `email-summary.j2` — prevalidation mail, standalone phase mails and the closing summary.
  - `progress-mail.j2` — heartbeat and degradation mails.
  - `error-report.j2` — the failure alert.
- `playbooks/logs/` — `<cluster>_<ts>.txt` (console tee + events), `.csv` (events), `.status` (failure exit class). Write-only.
- `playbooks/output/` — HTML reports `<cluster>_{phase01,prevalidation,postvalidation,operators}_<ts>.html`. Write-only.
- `playbooks/snapshots/` — `<cluster>_<ts>_baseline.json`.

---

## Storage & Concurrency Model

- **Baseline snapshot** (`snapshots/`): captured in Phase 01, read by Phase 05 (`baseline_snapshot_file_path`, else the newest snapshot of the cluster). The only cross-phase state file.
- **Run status file** (`logs/<cluster>_<ts>.status`): written once per failed run by `roles/error_handle` (`exit_code`, `phase`, `task`, `reason`); `00_Run.sh` maps it to the exit code. Never read by Ansible.
- **Run lock** (`/tmp/aro-upgrade-<cluster>.lock`): `flock` held for the whole run (released by the kernel if the process dies); atomic `mkdir` lock with PID ownership where `flock` is missing. A second run for the same cluster exits 1 without touching the active lock; `--clean` refuses while a run is active.
- **In-memory run facts**: `health_summary`, `run_phase_results`, `hop_results`, `admin_acks_applied`, `preval_autofix_items`, `notification_ledger`, `path_validation`, … live only for the run. Per-report inputs (`checks`, `autofix_items`, `output_file`, `diagnostic_details`) are cleared by `roles/report` after every render; mail inputs (`notify_*`) by `roles/sendmail` after every send.
- **Logs**: only `tasks/log_event.yml` writes them, by appending (`printf >>`). `lineinfile` is not used on run logs: it replaces the file by rename and detached the CLI's `tee` from the console log.

---

## Auth, Session Lifecycle & Safety Model

- **Login**: `roles/login` writes a dedicated kubeconfig (`playbooks/.kubeconfig-<cluster>`, git-ignored), passes the password on stdin, does not retry authentication failures, and verifies the session: API URL matches the configured one, `cluster_id` matches the optional pin, server matches `api_regex`.
- **Session reuse**: Phase 01 logs in; later phases log in only when `cluster_session_active` is false (standalone phases, `--skip-to-phase`). The monitor logs in again if the API returns Unauthorized (expired token on long runs).
- **Logout**: the close-out play of `main.yml` logs out after a successful run; standalone phases log out themselves; every rescue logs out, and an `always:` guard logs out if a rescue itself failed. `roles/logout` removes the kubeconfig. `~/.kube/config` is never touched.
- **Failure domains**: a Phase 06 operator failure never rolls back finished hops; the alert says the cluster upgrade itself is complete.

---

## Notification Architecture

- Callers set `notify_event`, `notify_headline`, `notify_attachments_requested` (optional `notify_event_tag`) and include `tasks/notify.yml`.
- Routing: `alert` / `degradation` → `alert_mail_to` + (`--mail-to` or `mail_to`); informational mails → `--mail-to`, else the list for that type (`preval_mail_to`, `postval_mail_to`, `dry_run_mail_to` for dry-run / pre-check summaries, `mail_to`).
- Subject: `[ARO Upgrade][<cluster>][<TAG>] <headline> (run <ts>)`, ASCII only.
- Mails per run: full upgrade = prevalidation mail + heartbeats / degradation alerts + one closing summary; dry run / pre-check / partial run = one closing summary; standalone phase = one closing mail; any failure = exactly one alert (`failure_alert_sent`) and no summary. No hop-started, hop-completed or per-node mails.
- `roles/sendmail` renders inside `block/rescue`: an SMTP failure is logged and the run continues. Each send is recorded in `notification_ledger` (shown in the closing summary).

---

## Auto-Remediation & Resilience Architecture

```
 Phase 02: 15-check scan ──► failed checks the engine can act on?
               │                 ├─ Check 14 cgroup v1 (path reaches 4.19+)   → set cgroupMode v2        (auto_fix_cgroup_v2)
               │                 ├─ Check 03 paused allow-listed pool           → spec.paused=false        (auto_unpause_mcp)
               │                 └─ Check 01 Degraded operator                  → restart operator pods    (auto_restart_degraded_operators, opt-in)
               ▼
   node rollout started? ──► roles/monitor (rollout mode: heartbeats, degradation alerts, timeouts)
               ▼
   full 15-check re-scan ──► remediated check PASS/WARN → AUTO-FIXED, else FIX-FAILED
               ▼
   any HARD FAIL / FIX-FAILED ──► report, one alert, logout, exit 10
```

- **Per hop (Phase 03)**: before a minor hop, `remediate/tasks/admin_acks.yml` (apply mode) checks APIRequestCount for callers of APIs removed on the way (fails the hop if any), sets the `ack-<minor>-…` key(s) in `openshift-config/admin-acks`, and waits for `Upgradeable=True`.
- **During a hop (Phase 04, opt-in)**: `auto_force_stalled_node` creates `/run/machine-config-daemon-force` on a node whose machine-config daemon has been Degraded for `node_stall_threshold_minutes` (once per node).
- **Phase 06**: `operator_upgrade_auto_recover` restarts, once, the operator Deployments of an approved operator whose CSV is Failed. CSVs are never deleted.
- **Hard stops**: anything else (conditional-update risks that apply, removed APIs in use, foreign update in progress, unstable cluster before a hop) stops with the exact reason.

---

## Cluster Writes (complete list)

| Where | Write | Condition |
|---|---|---|
| Phase 02 | `nodes.config/cluster` `spec.cgroupMode: v2` | Check 14 failed, `auto_fix_cgroup_v2`, remediation enabled |
| Phase 02 | MachineConfigPool `spec.paused: false` | Check 03 failed, pool on `mcp_auto_unpause_list`, `auto_unpause_mcp` |
| Phase 02 | delete operator pods (ReplicaSet-owned, operator namespace) | Check 01 Degraded operator, `auto_restart_degraded_operators` (default off) |
| Phase 03 | ClusterVersion `spec.channel` | hop channel differs |
| Phase 03 | `openshift-config/admin-acks` key(s) | minor hop, no removed-API callers, `auto_apply_admin_acks` |
| Phase 03 | `oc adm upgrade --to=<hop>` (`--allow-not-recommended` only with `allow_conditional_updates`) | hop plan = trigger |
| Phase 04 | `/run/machine-config-daemon-force` on a node | `auto_force_stalled_node` (default off) |
| Phase 06 | InstallPlan `spec.approved: true` | the plan is `status.installPlanRef` of an UpgradePending subscription |
| Phase 06 | `oc rollout restart deployment -l olm.owner=<csv>` | approved operator's CSV Failed, `operator_upgrade_auto_recover` (once) |
| Phase 06 | `consoles.operator.openshift.io/cluster` perspectives (`dev` → Enabled) | Developer perspective Disabled, live run, `enable_developer_perspective` |

Dry runs make none of these writes. `--pre-check` makes only the Phase 02 writes.

---

## Invariants

1. **No AI in the execution path**: all decisions are deterministic rules (`when:`, `fail:`, fixed `oc` commands).
2. **Dual-version compatibility**: code runs unchanged on Ansible 2.7.17 and 2.14.18 (see `code-standards.md` for the 2.7 pitfalls: attribute access on undefined values, fact vs task-var precedence, `until` + `failed_when`).
3. **Single kubeconfig scope**: only the run's own kubeconfig is used; `~/.kube/config` is never read or modified.
4. **Logout on every path**: every phase has `block/rescue/always`; the close-out play logs out after success.
5. **No intermediate state persistence**: live state is re-read from the cluster; the Phase 01 snapshot and the failure status file are the only files read later (the status file only by the CLI).
6. **Whole path validated before any change**: every remaining edge is checked (graph per hop channel + cluster offer); minor versions are never skipped; each hop is re-verified live before it is triggered.
7. **Deterministic gates**: HARD stops the run, WARN records and continues, AUTO-FIXED only after a full re-check passes.
8. **Force upgrades are manual only**: `--to-image … --force` needs `allow_force_upgrade`, a pullspec and the confirmation token.
9. **Zero plaintext secrets**: vault references, `no_log: true`, password on stdin; secrets never reach logs, reports or mails.
10. **Concurrency safety**: one run per cluster (flock / mkdir lock); a lock is only released by its owner.
11. **Only the listed cluster writes**: any new write must be added to the table above, to `code-standards.md` and to the CLI change scope.
12. **One alert per failed run, one summary per successful run**: guarded by `failure_alert_sent`; per-mail inputs reset after each send.
