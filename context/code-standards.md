# Code Standards — ARO Cluster Upgrade Automation

These standards are **mandatory** for all playbooks, roles, tasks, templates, and vars in this project. The suite is **production-grade** and must run **unchanged on Ansible 2.7.17 (test) and 2.14.18 (prod)** using only `oc`, `jq`, and shell. When in doubt, favour **determinism, explicit failure, and readability** over cleverness.

---

## General

- Keep each role single-purpose. One role owns exactly one concern (e.g. `mcp` health check never queries nodes). If a role grows a second responsibility, split it.
- Fix root causes, never layer workarounds. Do not paper over a failing gate with `ignore_errors` or a retry that masks a real problem.
- **No AI, no inference, no non-determinism** anywhere in the execution path. Every branch is a hardcoded `when:` or `fail:` rule.
- Every task must be idempotent-safe or explicitly read-only. Cluster reads must never mutate state. The only cluster writes are the ones listed in `architecture.md` → **Cluster Writes**; a new write must be added there, here and to the CLI change scope (`compute_change_scope` in `00_Run.sh`) in the same change.
- Prefer many small, verifiable tasks over one large opaque task. Each task should be understandable and testable in isolation.
- Never hardcode machine-specific paths. Everything derives from `playbook_dir`.
- Keep the project simple: only the seven main files (`00_Run.sh`, `01`–`06`) drive the process; all heavy lifting lives in roles/tasks/templates so the main files stay thin and readable.

---

## Ansible & YAML

- **Write to 2.7.17 syntax.** Use **short module names** (`shell`, `command`, `template`, `copy`, `set_fact`, `fail`, etc.). Add `# MIGRATION 2.14:` inline notes wherever 2.14 behaviour differs.
- **Never use bare `include:`.** Always use `include_tasks:` (dynamic, for loops/conditionals) or `import_tasks:` (static). Choose deliberately and comment why.
- **Never use `import_playbook` inside a loop** — it cannot loop on 2.7.17. Per-hop iteration must use a play with `include_tasks:` + `loop:`.
- **Add `| default('')`** (or a sensible typed default) to every optional variable. 2.14 Jinja2 is stricter and undefined vars must not break the run.
- Every YAML file starts with a header comment stating it targets 2.7.17 and listing any 2.14 migration notes.
- Name every task with a clear, action-oriented `name:`. Unnamed tasks are not allowed.
- Use `changed_when:` and `failed_when:` explicitly on shell/command tasks — never rely on Ansible's default exit-code interpretation for gate logic.
- Use `block/rescue/always` for any phase that can fail; the `always` block must guarantee logout.
- Keep booleans, gates, and thresholds in `vars/` — never buried as literals inside tasks.

---

## Shell & Command Modules

- **Never use the `warn:` parameter** on shell/command — it was removed in 2.14 and breaks the dual-version contract.
- Prefer `command` over `shell` unless you need pipes, redirection, or heredocs (e.g. `oc ... | jq ...`). Comment why `shell` was chosen.
- Always set `changed_when: false` on read-only `oc`/`jq` queries so reporting stays honest.
- Capture output with `register:` and validate `rc` / `stdout` explicitly before acting on it.
- Pipe `oc` JSON output through `jq` (v1.5-compatible syntax only) for parsing — do not parse JSON with fragile string/regex hacks.
- Quote all variable interpolations inside shell blocks to survive empty or spaced values.
- Minimise terminal noise: surface only meaningful status lines; suppress verbose success chatter.

### Shell Compatibility

- **Always set `args: executable: /bin/bash`** on shell tasks that use `set -o pipefail`. Ansible defaults to `/bin/sh`, which on Debian/Ubuntu points to `dash` (a POSIX shell that lacks `pipefail` support). Without this, tasks crash with `/bin/sh: 1: set: Illegal option -o pipefail`.
- Use `shell: |` with explicit `\` line continuations for multi-line jq commands — **not** `shell: >-`, which strips newlines and can cause shell parsing errors (e.g. `--arg` on a new line treated as a standalone command).

---

## jq v1.5 Compatibility Rules

All `jq` expressions must be compatible with **jq v1.5** (the version available on RHEL 8). The following rules prevent runtime failures:

- **`round` is not defined in jq 1.5.** Use a custom function with a name that does **not** start with `round` — e.g. `def rnd2: . * 100 | floor / 100;`. jq 1.5's lexer tokenizes `round2` as `round` + `2`, still producing `round/0 is not defined`. Use `rnd2`, `rnd`, or similar.
- **Always add explicit parentheses around `or`/`and` operands.** jq's operator precedence can feed booleans into string functions. For example:
  ```
  # WRONG — jq parses as: tostring | (endswith("k") or tostring) | endswith("K")
  (tostring | endswith("k") or tostring | endswith("K"))

  # CORRECT — explicit grouping
  ((tostring | endswith("k")) or (tostring | endswith("K")))
  ```
- **Test all jq expressions** with `jq --version` 1.5 on RHEL 8 before considering them done.
- **Comment every jq expression** with a short explanation of what it extracts and what the expected output shape is.

---

## Jinja2 & Templates

- Templates (`.j2`) are **presentation-only**. No cluster queries or decision logic in a template.
- Guard every optional value with `| default('')` (or `| default('N/A')` for display) so a missing field never renders `Undefined`.
- All colour-coding (green/amber/red) is driven by **status variables passed in**, not computed in the template.
- HTML **reports** (`phase01-policy-check.j2`, `phase02-prevalidation.j2`, `health-overview.j2`) include a summary section, colour-coded status, collapsible detail, and a copy button. **Mail** templates (`email-summary.j2`, `progress-mail.j2`, `error-report.j2`) use inline CSS and tables only — no JavaScript, max width 580 px — and escape every cluster-provided string with `| e`.
- Keep template logic flat and readable; move any non-trivial computation into a `set_fact` before rendering.

### Jinja2 Anti-Patterns (Mandatory Avoidance)

These patterns were discovered during the v1 build and caused production-breaking bugs. **Never use any of them.**

1. **Never self-reference variables in `vars:` blocks.**
   ```yaml
   # WRONG — causes infinite recursion:
   #   AnsibleError: An unhandled exception occurred while templating
   include_role:
     name: error_handle
   vars:
     failure_reason: "{{ failure_reason }}"
     failure_observed: "{{ failure_observed }}"

   # CORRECT — use set_fact to pre-compute, then let the role consume host facts directly:
   - set_fact:
       failure_reason: "The edge check failed"
   - include_role:
       name: error_handle
   # (error_handle reads failure_reason from host facts, no vars: block needed)
   ```

2. **Never pass `vars:` into `include_role` that match the role's own defaults.**
   ```yaml
   # WRONG — creates lazy evaluation loops:
   include_role:
     name: sendmail
   vars:
     is_rbac_error: "{{ is_rbac_error | default(false) | bool }}"

   # CORRECT — set the fact first, let the role consume it:
   - set_fact:
       is_rbac_error: true
   - include_role:
       name: sendmail
   ```

3. **Always apply `| string | trim` before comparing OpenShift condition statuses.**
   ```yaml
   # WRONG — OpenShift may return Python bool True, not string "True":
   when: postval_cv_available == 'True'

   # CORRECT — normalize types first:
   - set_fact:
       postval_cv_available: "{{ raw_available | string | trim }}"
   - fail:
       msg: "CV not available"
     when: not (postval_cv_available | bool)
   ```

4. **Use `['items']` bracket notation to access Kubernetes JSON array keys.**
   ```yaml
   # WRONG — .items resolves to Python's dict.items() method:
   some_var: "{{ result.stdout | from_json | json_query('items') }}"

   # CORRECT — bracket notation:
   some_var: "{{ (result.stdout | from_json)['items'] }}"
   ```

5. **Never reference `ansible_failed_task.name` in rescue blocks.**
   `ansible_failed_task` is an internal Ansible `Task` object containing un-serializable `FieldAttribute` instances. Templating it crashes with an unhandled exception. Use `ansible_failed_result.msg` or `ansible_failed_result.stderr` instead.

6. **Never read an attribute of a value that may be undefined, even with `| default`.**
   On Ansible 2.7 an undefined variable is a Jinja `StrictUndefined`: `x.attr` raises *before* `default` runs (2.14's undefined is chainable, 2.7's is not).
   ```yaml
   # WRONG on 2.7 when poll_cv was never set:
   "{{ poll_cv.latest | default('unknown') }}"
   # CORRECT:
   "{{ (poll_cv | default({})).latest | default('unknown') }}"
   ```
   A missing *key* of a defined dict is fine (`upgrade_edge_state.message | default('')`).

7. **Never use regex backreferences (`'\\1'`, `'\\2'`) in Jinja inside YAML strings.**
   Jinja decodes string literals with `unicode_escape`, so `'\1'` becomes the control character chr(1). This made the old Check 14 read every minor version as 0 (cgroup v2 never required) and the old postvalidation expect kubelet `v1.13.` (Check 04 failed every live run). Parse versions with `split('.')` and compare with the `version` test.

8. **A fact beats a task `vars:` entry.** Precedence: play vars < task / include vars < `set_fact` facts < extra vars. To override something that may already be a fact (for example `operator_compat_target_version`, set by Prevalidation Check 15), use `set_fact`, not `include_role … vars:`.

9. **`until` + `retries` marks the task failed when retries run out — `failed_when: false` does not prevent it.** Use `until` only for commands whose failure should fail the task. A wait whose outcome is *data* (operators settling, a CSV reaching Succeeded, the cluster offering an update) is a bounded loop inside the shell that prints the final state.

10. **Do not use the Jinja `in` *test*** (`selectattr('x', 'in', list)`, Jinja 2.10+). Use the `in` operator inside a `{% for %}` / `{% if %}`.

11. **Never compute elapsed time or timers from `ansible_date_time`.** It is captured once at fact gathering; every duration computed from it is 0. Read `lookup('pipe', 'date +%s')` when the value is needed.

12. **Build lists / dicts in Jinja with `{% set out = [] %}…{% set _ = out.append(…) %}…{{ out }}`** (or `.update()` for dicts). `{% set %}` inside a `{% for %}` does not leave the loop scope; mutate a container instead.

---

## Exception Handling & Error Extraction

Every rescue block must follow this standardized error extraction hierarchy. This prevents generic "non-zero return code" messages in alert emails and ensures RBAC errors get actionable remediation guidance.

### Error Extraction Order

Extract error details in this priority order (first non-empty wins):

1. `ansible_failed_result.stderr` — raw stderr from the failed command
2. `ansible_failed_result.stderr_lines | join('\n')` — stderr as joined lines
3. `ansible_failed_result.msg` — Ansible's generic failure message
4. Fallback: `"Unknown error — inspect run logs at {{ log_dir }}"`

```yaml
# Standard error extraction pattern for rescue blocks (always fresh — never reuse a
# resolved_error left by an earlier phase):
- name: Extract error details from failed task
  set_fact:
    resolved_error: >-
      {{ (ansible_failed_result.stderr | default('') | string | trim)
         or (ansible_failed_result.stderr_lines | default([]) | join('\n'))
         or (ansible_failed_result.msg | default('') | string | trim)
         or 'Unknown error - inspect the run log' }}
```

### Failure Reporting (one alert, one exit class)

- Every rescue sets `current_step_no`, `current_task_name`, `current_gate_type`, `failure_reason`, `failure_observed`, `phase_exit_code` and `failure_attachments`, then includes `roles/error_handle`.
- `error_handle` writes `logs/<cluster>_<ts>.status` once (`run_status_written`) and sends the alert once (`failure_alert_sent`). The innermost handler (e.g. `hop.yml`) reports; outer rescues (Phase 03) only log out.
- Exit classes: 5 Phase 01, 10 Phase 02, 20 hop failed, 25 Phase 05, 30 hop timeout / no progress (set by `roles/monitor`), 35 Phase 06, 99 other.
- Write the phase report **before** the HARD gate so the alert can attach it; the rescue renders a report only when the failure happened earlier (and then lists every check, the first missing one as FAIL, the rest SKIPPED).

### RBAC Error Detection

Automatically detect permission/authorization errors and surface them with actionable remediation:

```yaml
- name: Detect RBAC or permission error
  set_fact:
    is_rbac_error: >-
      {{ (resolved_error | lower is search('forbidden'))
         or (resolved_error | lower is search('cannot patch'))
         or (resolved_error | lower is search('unauthorized'))
         or (resolved_error | lower is search('cannot get'))
         or (resolved_error | lower is search('cannot list')) }}
```

When `is_rbac_error` is true, the `error-report.j2` template renders a dedicated warning box with the missing API resource and remediation guidance.

### Notification Lifecycle (`tasks/notify.yml` → `roles/sendmail`)

Every mail goes through one path; never include `roles/sendmail` directly.

1. The caller sets `notify_event` (`prevalidation`, `heartbeat`, `degradation`, `alert`, `postvalidation`, `summary`), `notify_headline`, `notify_attachments_requested` (and optionally `notify_event_tag`), then includes `tasks/notify.yml`. Template content comes from explicit facts (`summary_*`, `progress_*`, failure context) — never from facts left over by an earlier mail.
2. `notify.yml` resolves recipients (alerts / degradation always include `alert_mail_to`), the enable toggle for that mail type, the ASCII subject `[ARO Upgrade][<cluster>][<TAG>] <headline> (run <ts>)`, the template, and the attachments that exist on disk.
3. `sendmail` renders fresh inside `block/rescue` (an SMTP failure is logged, never fatal), records `notification_ledger`, and resets every `notify_*` input.
4. Mail rules: no hop-started / hop-completed / per-node mails; the heartbeat is time-based (`heartbeat_minutes`, continuous across hops); a degradation alert is sent once per condition after its grace period and also counts as the heartbeat; a failed run sends exactly one alert and no summary; a successful run sends exactly one closing summary.

---

## Auto-Remediation & Resilience Standards (One-Touch Automation)

To achieve true **one-touch execution**, the system must not fail prematurely on known, safe-to-remediate conditions or transient network blips. All automated fixes adhere to strict deterministic rules:

### Retry Pattern for `oc` Commands (Transient Fault Tolerance)
- Monitoring polls do **not** use task retries: one poll reads all state in one call with `--request-timeout=60s` and never fails the task; the monitor tolerates an unreadable API for `monitor_api_outage_minutes` and logs in again on Unauthorized.
- Waits whose outcome is data use bounded in-shell loops (see anti-pattern 9) and `wait_for: timeout:` between polls (never `pause`, which touches the terminal and can stop a backgrounded run).
- Other one-shot `oc` commands include retry parameters to absorb API server restarts, transient timeouts, or 503 blips:
  ```yaml
  - name: "Query clusterversion (resilient)"
    shell: "oc get clusterversion version -o json"
    register: cv_raw
    until: cv_raw.rc == 0
    retries: "{{ oc_command_retries | default(3) }}"
    delay: "{{ oc_command_retry_delay | default(10) }}"
    changed_when: false
  ```

### Deterministic Remediation Rules
- **Rule-Based Only**: Never guess or apply non-deterministic heuristics. Every fix maps 1:1 to official Red Hat/OpenShift upgrade documentation (e.g., `cgroupMode: v2`, unpause MCP, admin-ack ConfigMap).
- **Gated by Feature Toggles**: Every remediation action must check `auto_remediation_enabled | bool` and its specific toggle (e.g., `auto_fix_cgroup_v2 | bool`) before executing.
- **Idempotent and Verified**: Any remediation task must re-verify state after applying changes. If verification fails, escalate cleanly without corrupting facts.
- **Never rewrite check results in a remediation task.** A remediation records only what it applied (`remediation_attempted_nums`, `remediation_rollout_needed`, `preval_autofix_items`). Phase 02 re-runs the full scan; a remediated check is `AUTO-FIXED` only when the whole check passes afterwards, otherwise `FIX-FAILED`. A check counts as "attempted" only when something was actually changed (a failure the engine could not act on stays `FAIL`).
- **Wait for side effects.** A change that makes the Machine Config Operator reboot nodes (cgroup mode, unpaused pool) is followed by `roles/monitor` in rollout mode before anything is re-checked.
- **Clear Audit Logging**: Log every remediation action through `tasks/log_event.yml` with status `AUTO-FIX` (or `FIX-FAILED`) and the action taken.

### Health Summary Status Values
The `health_summary` list tracks all validation and remediation items:
- `PASS` — Check passed on first evaluation.
- `WARN` — Advisory finding (non-blocking).
- `FAIL` — Hard blocker; halt triggered (if auto-remediation disabled or unavailable).
- `AUTO-FIXED` — Check failed initially, remediation executed successfully, and re-verification passed.
- `FIX-FAILED` — Remediation was attempted but re-verification failed; escalated to `FAIL`.

---

## Gates & Error Handling

- **HARD gates use `fail:`** with a clear, specific message naming the check, the cluster, and the observed value. A HARD failure halts the chain and triggers logout.
- **WARN items never block.** They are recorded and surfaced in the report only — never auto-remediated.
- **Prevalidation (15 checks) runs once** as a gate before any hop (**Phase 02**). It runs an initial pass over 15 checks (including cgroup v2 compatibility and OLM operator upgrade compatibility), executes the `remediate` role for any failed auto-remediable checks if enabled, re-evaluates, and only halts if residual HARD failures persist.
- **Postvalidation (10 checks) runs once** after the final hop (**Phase 05**). The **settle-gate** runs between hops (**Phase 04**) and requires `settle_consecutive_polls` settled polls in a row.
- Timeout guards are mandatory on monitoring loops: a hop fails when nothing progresses for `hop_timeout_minutes` (90) or after `hop_max_minutes` (480) in total, when the release is not accepted for `release_not_accepted_fail_minutes`, or when ClusterVersion reports Failing for `cv_failing_fail_minutes`. A stall must fail → alert → logout, never hang indefinitely.
- **Before a hop**: the hop plan comes from the live cluster (skip a completed version, resume an update running to the target, refuse an update running elsewhere), the cluster must be stable (`prehop_settle_wait_minutes`), the cluster must offer the target in the hop's channel, and conditional-update risks that apply stop the hop unless `allow_conditional_updates`.
- Do not use `ignore_errors: true` to bypass a gate. If a step is genuinely non-fatal, model it explicitly as a WARN with `failed_when: false` and a recorded status.
- Every failure path must emit an alert email and log the reason before logout.
- **Operator upgrade failures never roll back cluster hops.** A failed operator upgrade in Phase 06 is a HARD finding for that phase only — it is reported and alerted but does not undo any cluster version changes. Phase 06 approves only the current InstallPlan of each UpgradePending subscription, gates only on the operators it approved and on regressions, and recovers a Failed CSV with one restart of the operator Deployments (never by deleting the CSV).

---

## Secrets & Security

- Passwords and tokens are **always variable references** (`{{ vault_cluster_d01_password }}`) — never inline literals. This keeps the later Conjur Vault swap a source-only change.
- Secrets must never be written to logs, reports, snapshots, or email bodies. Use `no_log: true` on any task that could echo a credential.
- The kubeconfig is written under `playbook_dir` and must be removed or invalidated on logout.
- One service account per run performs all actions; never embed personal credentials.

---

## Data, Logging & Storage

- **Live cluster state is ephemeral** — read fresh from `oc` at execution time and held only in registers/facts. Never persist derived state between phases.
- **The Phase 01 baseline JSON snapshot is the single sanctioned cross-phase persistence** — written to `snapshots/<cluster>_<timestamp>_baseline.json`, read only by **Phase 05** for the diff.
- Logs are written to `logs/` in **both `.txt` and `.csv`** for every run, **only** through `tasks/log_event.yml` (append-only `printf >>`). Never use `lineinfile` on a run log: it replaces the file by rename, which detached the CLI's `tee` and silently dropped the rest of the console log. Pass the event through include `vars:` (`event_status`, `event_gate`, `event_task`, `event_reason`, `event_observed`), never `set_fact` them.
- HTML reports are written to `output/` only; they are write-only artifacts never read back by the automation.
- Report inputs (`checks`, `autofix_items`, `diagnostic_details`, `output_file`) are set immediately before each `include_role: report` and cleared by the role afterwards. Report cards show only measured values (`n/a` when not measured) and take their verdict from the check record — never a hard-coded "healthy" line.
- Use `to_json` / `from_json` for snapshot handling; **retest snapshot parsing on 2.14 (Python 3)** as part of migration.

---

## Developer Comment Standard

Every file must contain sufficient inline documentation for a developer to understand the project without external context. Follow these rules:

### File Headers

Every YAML file must open with a header block:
```yaml
# ============================================================================
# <File purpose — one line>
# ============================================================================
# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)
# MIGRATION 2.14: <specific migration notes, or "No changes needed">
#
# Purpose: <2-3 line description of what this file does>
# Dependencies: <list of roles/vars/templates this file requires>
# Gate type: <HARD / WARN / N/A>
# ============================================================================
```

### Task Comments

- Every task must have a `name:` — unnamed tasks are not allowed.
- Add a comment explaining **why** (not just what) for any non-obvious logic:
  ```yaml
  # Why: jq 1.5 does not support round(); use custom rnd2 function
  # Why: bracket notation because .items resolves to dict.items() in Jinja2
  # Why: | string | trim because OpenShift may return bool instead of string
  ```
- Every `rescue:` block must comment the error extraction strategy used.
- Every `jq` expression must have a preceding comment explaining what it extracts.

### Role Defaults

Every role's `defaults/main.yml` must document each variable:
```yaml
# The target cluster name (string, required)
# Passed via vars/upgrade.yml or --extra-vars
cluster_name: ""

# Maximum CPU utilization threshold (integer, percentage)
# Sourced from vars/upgrade.yml — do not hardcode in tasks
max_cpu_percent: 90
```

---

## File Organization

- `playbooks/` — `00_Run.sh`, `main.yml`, and the six phase playbooks (`01_Policy_Check`, `02_Pre_upgrade_check`, `03_Initiate_upgrade`, `04_Live_monitoring_upgrade`, `05_post_Upgrade_Checks`, `06_Operator_Upgrade`). Orchestration only.
- `playbooks/tasks/` — `hop.yml` (one hop, `block/rescue`), `validate_upgrade_path.yml`, `log_event.yml`, `notify.yml`, `send_run_summary.yml`.
- `playbooks/roles/` — one concern per role; each role has `tasks/main.yml` and sensible `defaults/main.yml`.
- `playbooks/vars/` — secrets, SMTP, HTML vars, log paths, API regex, and `upgrade_path`. Inputs only, no logic.
- `playbooks/templates/` — `phase01-policy-check.j2`, `phase02-prevalidation.j2`, `health-overview.j2`, `email-summary.j2`, `progress-mail.j2`, `error-report.j2`. Presentation only.
- `playbooks/logs/` — run logs (`.txt` + `.csv`). Write-only.
- `playbooks/output/` — prevalidation/postvalidation/operator HTML reports. Write-only.
- `playbooks/snapshots/` — baseline JSON snapshot. The only persisted cluster state.

---

## `00_Run.sh` (CLI Entrypoint) Standards

- Derive all paths from the script's own location (`playbook_dir` base); create `logs/`, `output/`, `snapshots/` if missing. Nothing machine-specific hardcoded.
- Accept the target cluster and ordered `upgrade_path` via args or prompt, then print a confirmation summary before executing anything.
- Provide an interactive upgrade path selection menu when no `--path` is specified, with a `--no-menu` flag to bypass and use the configured default.
- Run `main.yml` with live output tee'd to `logs/` in `.txt`; return the exit class from `logs/<cluster>_<ts>.status` (0 success, 1 lock conflict, 2 aborted confirmation / invalid input, 5 / 10 / 20 / 25 / 30 / 35 by phase, 99 other).
- A PROD run that can change the cluster requires typing `UPGRADE`; `--yes` never bypasses it and a non-interactive PROD mutating run exits 2.
- Keep terminal noise minimal and colour-coded; never echo secrets. `set -euo pipefail` for safe failure.
- Pass extra-vars as a single valid JSON object string (`-e '{"cluster_name":"...","upgrade_path":[...]}'`) — never as space-separated `key=value` pairs, which causes Ansible's `parse_kv` to stringify lists.

---

## Pre-Merge Checklist

- Runs cleanly on **both** Ansible 2.7.17 and 2.14.18 with no source edits.
- No bare `include:`, no `warn:` param, all optionals carry `| default('')`.
- Every task is named; every shell/command sets `changed_when:`/`failed_when:` explicitly.
- All secrets are variable references with `no_log: true`; nothing sensitive appears in logs/reports/snapshots.
- Every failure path logs out via `block/rescue/always`.
- HARD gates use `fail:`; WARN items only report.
- All paths derive from `playbook_dir`; nothing machine-specific is hardcoded.
- `ansible-playbook --syntax-check` passes on the affected playbooks.
- All jq expressions tested on jq v1.5 (every `if` has an `else`; no post-1.5 builtins).
- All Jinja2 condition comparisons use `| string | trim` normalization.
- Rescue blocks extract `stderr` before `msg`; RBAC errors are detected; `phase_exit_code` is set.
- Mails go through `tasks/notify.yml` only; subjects are ASCII; `notify_*` inputs are reset after each send.
- Run logs are written only through `tasks/log_event.yml` (no `lineinfile`).
- No `ansible_date_time` in timers or durations; no regex backreferences; no attribute access on possibly undefined facts.
- Shell tasks using `pipefail` set `args: executable: /bin/bash`.
- Offline checks pass (see `feature-spec/17-verification-and-testing.md`): YAML parse, Jinja compile, jq compile of every embedded program, and the scenario simulations.
