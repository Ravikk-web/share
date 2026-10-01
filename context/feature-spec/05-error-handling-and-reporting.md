# Unit 05: Error Handling & Reporting Roles (`error_handle`, `report`)

> **Revision 2026-10-01 (review remediation)** — `roles/error_handle` writes the run status file once and sends exactly one alert per run (`failure_alert_sent`). Reports are written before HARD gates; `roles/report` clears its inputs after each render; Phase 02 cards show only measured values. See `code-standards.md` → Failure Reporting.

## Goal

Build the unified error handling and reporting roles: `error_handle` (standardized rescue handling, dual `.txt`/`.csv` audit logging, RBAC detection, and alert dispatch) and `report` (rendering client-facing HTML reports to `output/` using `health-overview.j2`).

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/error_handle/` and `playbooks/roles/report/`.
- **Anti-Pattern Prevention**:
  - Never reference `ansible_failed_task.name` (crashes on templating).
  - Never pass self-referencing variables in `vars:` blocks. Set facts upstream.
- **Hierarchical Error Extraction**: Extract error details from `ansible_failed_result.stderr` → `stderr_lines` → `msg` → fallback string.
- **Dual Audit Logging**: Maintain simultaneous human-readable `.txt` run logs and machine-parseable `.csv` logs.
- **Report Writing**: The `report` role takes evaluated `health_summary` facts, renders `health-overview.j2`, and writes standalone HTML files to `output/`.

---

## Implementation Details

### 1. `roles/error_handle/`
- **`defaults/main.yml`**:
  ```yaml
  current_step_no: 0
  current_task_name: ""
  current_gate_type: "HARD"
  failure_reason: ""
  failure_observed: ""
  resolved_error: ""
  is_rbac_error: false
  ```
- **`tasks/main.yml`**:
  1. Extract and sanitize error details using the standard priority hierarchy.
  2. Detect if the failure is an RBAC/permission denial (`forbidden`, `cannot patch`, `unauthorized`) and set `is_rbac_error: true`.
  3. Record structured failure item to `failed_checks` and `health_summary` lists via `set_fact`.
  4. Append formatted failure entry to the cluster `.txt` log file:
     ```yaml
     - name: "Append failure entry to run log (.txt)"
       lineinfile:
         path: "{{ log_dir }}/{{ cluster_name }}_{{ run_timestamp }}.txt"
         line: "[{{ lookup('pipe', 'date +%Y-%m-%dT%H:%M:%S') }}] [FAIL] [{{ current_gate_type }}] Task '{{ current_task_name }}': {{ failure_reason }} | Observed: {{ resolved_error }}"
         create: true
     ```
  5. Append structured CSV row to `.csv` log (with automated header initialization if file is new).
  6. Dispatch immediate failure alert email via `sendmail` role with `mail_template: "error-report.j2"`.
  7. Note: Calling playbooks maintain the `always:` block that invokes `logout`.

### 2. `roles/report/`
- **`defaults/main.yml`**:
  ```yaml
  report_type: "prevalidation"  # prevalidation | postvalidation | operator
  report_title: "Pre-Upgrade Validation Report"
  overall_status: "PASS"
  ```
- **`tasks/main.yml`**:
  1. Calculate summary counters: total checks, passed, warnings, auto-fixed, failed.
  2. Determine overall verdict badge:
     - `FAIL` if any failed items exist.
     - `AUTO-FIXED` if auto-fixed items exist and no failures.
     - `WARN` if warnings exist and no failures.
     - `PASS` if all passed cleanly.
  3. Render `health-overview.j2` template into HTML content.
  4. Write standalone HTML file to `output/{{ cluster_name }}_{{ report_type }}_{{ run_timestamp }}.html` using `copy:` with `content:`.
  5. Export `report_file_path` fact for downstream notification attachments.

---

## Verification Checklist

- [ ] `error_handle` extracts `stderr` before `msg` without evaluating `ansible_failed_task.name`.
- [ ] RBAC errors set `is_rbac_error: true` and surface in alert emails.
- [ ] Both `.txt` and `.csv` logs receive structured failure records.
- [ ] `report` generates valid HTML reports in `output/`.
- [ ] Status counts and verdict badges (`AUTO-FIXED`, `FAIL`, etc.) calculate accurately.
